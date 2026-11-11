//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//
// 本文件改自 Swiftfin：Shared/Views/VideoPlayer/Components/Toolbar/ActionButtons/AutoPlayActionButton.swift
// Modifications for MoviePilot-TV are also licensed under MPL-2.0.
//
// 修改：原版读写 Jellyfin 服务器上当前用户的 `enableNextEpisodeAutoPlay`（经 `ServerUserAdminViewModel` 保存）。
// MoviePilot-TV 用适配层的 `UserSession.isAutoPlayEnabled`（本机保存，默认开，与 Jellyfin/Emby 用户默认值相同）；
// 去掉 `FactoryKit`、`JellyfinAPI` 依赖。原版写死的英文提示（Auto Play on/off、On/Off）换成中文。
// 图标名改从 AppSymbol 取（项目统一图标来源），图标本身不变。
//

import SwiftUI

// TODO: static width for tvOS

extension VideoPlayer.PlaybackControls.Toolbar.ActionButtons {

    struct AutoPlay: View {

        @AdaptiveLayout
        private var viewLayout

        @ViewContextContains(.isInMenu)
        private var isInMenu

        @Environment(MediaSession.self)
        private var mediaSession

        @Toaster
        private var toaster

        private var isAutoPlayEnabled: Bool {
            mediaSession.userSession.isAutoPlayEnabled
        }

        private var systemImage: String {
            if isAutoPlayEnabled {
                VideoPlayerActionButton.autoPlay.systemImage
            } else {
                VideoPlayerActionButton.autoPlay.secondarySystemImage
            }
        }

        var body: some View {
            Button {
                let newValue = !isAutoPlayEnabled

                mediaSession.userSession.isAutoPlayEnabled = newValue

                if newValue {
                    toaster.present("自动播放已开启", systemName: AppSymbol.autoPlayOn)
                } else {
                    toaster.present("自动播放已关闭", systemName: AppSymbol.autoPlayOff)
                }
            } label: {
                Label(
                    L10n.autoPlay,
                    systemImage: systemImage
                )

                if isInMenu {
                    Text(isAutoPlayEnabled ? "开" : "关")
                }
            }
            .if(isInMenu && !viewLayout.isLarge) { button in
                button
                    .id(isAutoPlayEnabled)
            }
            .disabled(mediaSession.queue == nil)
        }
    }
}
