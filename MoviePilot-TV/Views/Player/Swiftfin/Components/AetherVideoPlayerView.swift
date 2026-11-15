//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//
// 本文件改自 Swiftfin：Shared/Views/VideoPlayer/Components/MPVVideoPlayerView.swift
// Modifications for MoviePilot-TV are also licensed under MPL-2.0.
//
// 修改：
// - 播放画面换成 AetherEngine 的画面（`AetherPlayer.surface`），去掉画中画分支（tvOS 播放不提供画中画）。
// - 引擎把文字和图片字幕都交给应用绘制：字幕叠层显示 `SubtitlePresentation` 给出的当前字幕。
//

import SwiftUI

struct AetherVideoPlayerView: View {

    @Environment(\.scenePhase)
    private var scenePhase

    let player: AetherPlayer
    let layout: VideoPlayer.VideoLayout

    var body: some View {
        player.surface
            .frame(width: layout.renderSize.width, height: layout.renderSize.height)
            .scaleEffect(layout.renderScale)
            .offset(layout.renderOffset)
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            .overlay {
                if let snapshot = player.subtitles.snapshot {
                    TextSubtitleOverlay(snapshot: snapshot, videoLayout: layout, reportCaptions: nil)
                }
            }
            .modifier(
                TextSubtitleReporting(
                    snapshot: player.subtitles.snapshot,
                    isVisible: scenePhase == .active
                )
            )
    }
}
