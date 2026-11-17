//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//
// 本文件改自 Swiftfin：Shared/Views/VideoPlayer/Components/Toolbar/OverlayButtonStyle.swift
// Modifications for MoviePilot-TV are also licensed under MPL-2.0.
//
// 修改：删去 iOS 专用分支；外观换成播放界面统一的玻璃圆形按钮（`PlayerGlassControl`），各系统版本同一套。
//

import SwiftUI

extension VideoPlayer.PlaybackControls {

    struct OverlayMenuStyle: MenuStyle {

        func makeBody(configuration: Configuration) -> some View {
            Menu(configuration)
                .menuStyle(.button)
                .buttonStyle(OverlayButtonStyle(isMenu: true))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.primary, .secondary)
        }
    }

    struct OverlayBarButtonStyleModifier: ViewModifier {

        func body(content: Content) -> some View {
            content
                .buttonStyle(OverlayButtonStyle())
        }
    }

    /// 工具栏按钮和「…」菜单：玻璃圆形按钮，按下菜单期间暂停自动收起控制条。
    struct OverlayButtonStyle: ButtonStyle {

        @AdaptiveLayout
        private var viewLayout

        @Environment(ViewState.self)
        private var viewState

        @State
        private var interactionID = UUID()

        var isMenu: Bool = false

        private var interaction: ViewState.Interaction {
            isMenu ? .menu(interactionID) : .button(interactionID)
        }

        func makeBody(configuration: Configuration) -> some View {
            let size = viewLayout.toolbarButtonSize

            PlayerGlassControl(shape: Circle(), isPressed: configuration.isPressed) {
                configuration.label
                    .labelStyle(.iconOnly)
                    .font(.system(size: viewLayout.toolbarIconSize, weight: .semibold))
                    // Menu's outer frame does not size the styled label or its focus surface.
                    .frame(width: size, height: size)
                    .contentTransition(.symbolEffect(.replace))
            }
            .onChange(of: configuration.isPressed) {
                // Button menus remain pressed through their nested menu hierarchy.
                viewState.setInteraction(interaction, active: configuration.isPressed)
            }
            .onDisappear {
                viewState.setInteraction(interaction, active: false)
            }
        }
    }
}
