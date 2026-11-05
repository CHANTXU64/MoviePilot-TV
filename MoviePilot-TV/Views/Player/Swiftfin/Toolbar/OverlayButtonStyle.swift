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
// 修改：删去 iOS 专用分支；按钮不用 Liquid Glass / 毛玻璃，统一改成不透明深色圆底，
// 聚焦时白底黑图标并略微放大（玻璃会随画面变色，亮画面上看不清）；图标缩小到 22pt，四周留白接近系统播放器按钮。
//

import SwiftUI

extension VideoPlayer.PlaybackControls {

    struct OverlayMenuStyle: MenuStyle {

        func makeBody(configuration: Configuration) -> some View {
            Menu(configuration)
                .menuStyle(.button)
                .buttonStyle(OverlayButtonStyle(isInBar: true, isMenu: true))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.primary, .secondary)
        }
    }

    struct OverlayBarButtonStyleModifier: ViewModifier {

        @AdaptiveLayout
        private var viewLayout

        func body(content: Content) -> some View {
            content
                .font(.system(size: viewLayout.isLarge ? 30 : 20, weight: .semibold))
                .buttonStyle(OverlayButtonStyle(isInBar: true))
        }
    }

    struct OverlayButtonStyle: ButtonStyle {

        private static let padding: CGFloat = 8

        @AdaptiveLayout
        private var viewLayout

        @Environment(\.isEnabled)
        private var isEnabled
        @Environment(\.isFocused)
        private var isFocused

        @Environment(ViewState.self)
        private var viewState

        @State
        private var interactionID = UUID()

        var isInBar: Bool = false
        var isMenu: Bool = false
        var symbolEffectSpeed: Double = 1

        private var labelSize: CGFloat? {
            isInBar && viewLayout.isLarge ? viewLayout.toolbarButtonSize - 2 * Self.padding : nil
        }

        private var interaction: ViewState.Interaction {
            isMenu ? .menu(interactionID) : .button(interactionID)
        }

        func makeBody(configuration: Configuration) -> some View {
            styledLabel(configuration)
                .onChange(of: configuration.isPressed) {
                    // Button menus remain pressed through their nested menu hierarchy.
                    viewState.setInteraction(interaction, active: configuration.isPressed)
                }
                .onDisappear {
                    viewState.setInteraction(interaction, active: false)
                }
        }

        private func label(_ configuration: Configuration) -> some View {
            configuration.label
                .font(.system(size: isInBar && viewLayout.isLarge ? 22 : 18, weight: .semibold))
                .foregroundStyle(isEnabled ? isFocused ? AnyShapeStyle(Color.black) : AnyShapeStyle(HierarchicalShapeStyle.primary) :
                    AnyShapeStyle(Color.gray)
                )
                .labelStyle(.iconOnly)
                // Menu's outer frame does not size the styled label or its focus surface.
                .frame(width: labelSize, height: labelSize)
                .contentTransition(.symbolEffect(.replace, options: .speed(symbolEffectSpeed)))
        }

        private func styledLabel(_ configuration: Configuration) -> some View {
            label(configuration)
                .padding(Self.padding)
                .background {
                    Circle()
                        .fill(isFocused ? Color.white : Color(white: 0.16))
                }
                .scaleEffect(configuration.isPressed ? 0.9 : isFocused ? 1.08 : 1)
                .animation(.easeOut(duration: 0.15), value: isFocused)
                .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
                .contentShape(.circle)
        }
    }
}
