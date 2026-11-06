//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//
// 本文件改自 Swiftfin：Shared/Views/VideoPlayer/VideoPlayer.swift
// Modifications for MoviePilot-TV are also licensed under MPL-2.0.
//
// 修改：
// - 播放画面直接用（同样移植自 Swiftfin 的）`MPVVideoPlayerView`：MoviePilot-TV 只把 mpv 内核交给这个界面，
//   不再经由 `VideoMediaPlayer` 协议；视频尺寸取自 `MediaSession.videoSize`。
// - 原版 `onAppear` 里 `attach(player:)` 换成 `mediaSession.start()`（起播与上报由 `PlaybackSession` 负责）。
// - 不用 Router：会话停止时由 `MediaSession` 调外部传入的退出闭包，去掉 `router.dismiss()`。
// - 起播失败由 `PlaybackSession` 结束会话并在外层提示，去掉原版的错误重试弹窗；去掉投屏、iOS 状态栏与屏幕方向相关修饰。
// - 图标名改从 AppSymbol 取（项目统一图标来源），图标本身不变。
// - 等电视切换显示模式（`MediaSession.isCoveringForDisplay`）时整屏盖黑，画面和控制层切好后一起出现。
//

import MPVUI
import SwiftUI

struct VideoPlayer: View {

    @State
    private var viewState: ViewState = .init()

    let mediaSession: MediaSession

    var body: some View {
        Container(
            viewState: viewState,
            mediaSession: mediaSession,
            videoSize: { mediaSession.videoSize }
        ) { videoLayout in
            MPVVideoPlayerView(
                player: mediaSession.mpvPlayer,
                textSubtitles: mediaSession.textSubtitles,
                layout: videoLayout,
                isPictureInPictureActive: mediaSession.mpvPlayer.pictureInPicture.isActive
            )
        } playbackControls: {
            PlaybackControls()
        }
        .overlay {
            // 切换显示模式时 HDMI 会黑屏，切换前露出的画面或控件都会像闪了一下，所以整屏保持黑色。
            if mediaSession.isCoveringForDisplay {
                Color.black
                    .ignoresSafeArea()
            }
        }
        .onAppear {
            mediaSession.start()
        }
        .onChange(of: mediaSession.commandError, initial: true) { _, message in
            guard let message else { return }

            viewState.toastProxy.present(message, systemName: AppSymbol.playbackError)
        }
        .colorScheme(.dark)
        .ignoresSafeArea()
        .persistentSystemOverlays(.hidden)
        .toolbar(.hidden, for: .navigationBar)
    }
}
