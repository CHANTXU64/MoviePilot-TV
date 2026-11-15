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
// - 播放画面直接用 `AetherVideoPlayerView`（改自 Swiftfin 的 `MPVVideoPlayerView`）：MoviePilot-TV 只把 AetherEngine
//   播放器交给这个界面，不再经由 `VideoMediaPlayer` 协议；视频尺寸取自 `MediaSession.videoSize`。
// - 原版 `onAppear` 里 `attach(player:)` 换成 `mediaSession.start()`（起播与上报由 `PlaybackSession` 负责）。
// - 不用 Router：会话停止时由 `MediaSession` 调外部传入的退出闭包，去掉 `router.dismiss()`。
// - 起播失败由 `PlaybackSession` 结束会话并在外层提示，去掉原版的错误重试弹窗；去掉投屏、iOS 状态栏与屏幕方向相关修饰。
// - 图标名改从 AppSymbol 取（项目统一图标来源），图标本身不变。
// - 引擎报告音频无法交付时，用播放器的提示条显示几秒后自动收起；起播遮挡（外层 `InAppPlaybackScreen`）揭开后再出。
//

import SwiftUI

struct VideoPlayer: View {

    @State
    private var viewState: ViewState = .init()

    let mediaSession: MediaSession

    /// 一句话要读完，比默认的 2 秒长一些。
    private static let droppedAudioToastDuration: TimeInterval = 5

    /// 引擎报告音频无法交付时的提示；起播遮挡期间先不出，揭开后再出（提示条在遮挡下面）。
    private var droppedAudioMessage: String? {
        guard mediaSession.startupCover == nil, mediaSession.enginePlayer.hasDroppedAudio else { return nil }
        return mediaSession.enginePlayer.audioTracks.count > 1 ? L10n.audioDroppedWithTracks : L10n.audioDropped
    }

    var body: some View {
        Container(
            viewState: viewState,
            mediaSession: mediaSession,
            videoSize: { mediaSession.videoSize }
        ) { videoLayout in
            AetherVideoPlayerView(
                player: mediaSession.enginePlayer,
                layout: videoLayout
            )
        } playbackControls: {
            PlaybackControls()
        }
        .onAppear {
            mediaSession.start()
        }
        .onChange(of: mediaSession.commandError, initial: true) { _, message in
            guard let message else { return }

            viewState.toastProxy.present(message, systemName: AppSymbol.playbackError)
        }
        .onChange(of: droppedAudioMessage, initial: true) { _, message in
            guard let message else { return }

            viewState.toastProxy.present(message, systemName: AppSymbol.playbackError, duration: Self.droppedAudioToastDuration)
        }
        .colorScheme(.dark)
        .ignoresSafeArea()
        .persistentSystemOverlays(.hidden)
        .toolbar(.hidden, for: .navigationBar)
    }
}
