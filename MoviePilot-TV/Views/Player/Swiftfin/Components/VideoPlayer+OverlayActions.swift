//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//
// 本文件改自 Swiftfin：Shared/Views/VideoPlayer/Components/VideoPlayer+OverlayActions.swift
// Modifications for MoviePilot-TV are also licensed under MPL-2.0.
//
// 修改：按钮用播放界面统一的玻璃胶囊按钮（`PlayerGlassCapsuleButtonStyle`），未聚焦时不再常亮白底。
//

import SwiftUI

extension VideoPlayer {

    struct OverlayActions: View {

        @AdaptiveLayout
        private var viewLayout

        @Environment(ViewState.self)
        private var viewState

        @FocusState
        private var focusedAction: String?

        private var actions: [ViewState.OverlayAction] {
            viewState.visibleElements.contains(.overlayActions) ? viewState.overlayActions : []
        }

        var body: some View {
            ViewThatFits(in: .horizontal) {
                buttons(axis: .horizontal)
                ScrollView(.horizontal) {
                    buttons(axis: .horizontal)
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .focusSection()
            .onMoveCommand { direction in
                if viewState.presentation == .hidden, direction == .up || direction == .down {
                    viewState.showControls()
                }
            }
            .onChange(of: actions.map(\.id), initial: true) { oldIDs, _ in
                viewState.updateOverlayActionFocus(previousIDs: oldIDs)
            }
            .onChange(of: viewState.presentation) {
                viewState.updateOverlayActionFocus()
            }
            .onChange(of: viewState.isPresentingCloseConfirmation) {
                if !viewState.isPresentingCloseConfirmation {
                    viewState.updateOverlayActionFocus()
                }
            }
        }

        private func buttons(axis: Axis) -> some View {
            let layout = axis == .horizontal
                ? AnyLayout(HStackLayout(spacing: viewLayout.isLarge ? 24 : 12))
                : AnyLayout(VStackLayout(alignment: .trailing, spacing: 12))

            return layout {
                ForEach(actions) { action in
                    Button {
                        viewState.performOverlayAction(action.id)
                    } label: {
                        if let systemImage = action.button.systemImage {
                            Label(action.button.title, systemImage: systemImage)
                        } else {
                            Text(action.button.title)
                        }
                    }
                    .buttonStyle(.playerGlass)
                    .coordinatedFocus(action.id.focusID, selection: $focusedAction)
                }
            }
        }
    }
}
