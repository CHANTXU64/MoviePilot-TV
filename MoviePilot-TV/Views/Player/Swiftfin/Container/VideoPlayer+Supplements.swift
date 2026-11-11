//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//
// 本文件改自 Swiftfin：Shared/Views/VideoPlayer/Container/VideoPlayer+Supplements.swift
// Modifications for MoviePilot-TV are also licensed under MPL-2.0.
//
// 修改：删去 `#if os(iOS)` 分支（iOS 的关闭按钮与手势）。
// 焦点离开回调写成 `@MainActor` 闭包（Swift 6 并发检查）。
//

import SwiftUI

extension VideoPlayer.UIContainerViewController {

    struct SupplementContainerView: View {

        @Environment(ViewState.self)
        private var viewState
        @Environment(MediaSession.self)
        private var mediaSession

        @AdaptiveLayout
        private var viewLayout

        @FocusState
        private var focusedElement: String?


        private var defaultTabFocus: String? {
            viewState.selectedSupplementID ?? viewState.supplements.first?.id
        }

        private var focusedSupplementID: String? {
            guard viewState.visibleElements.contains(.supplements) else { return nil }

            return viewState.supplements
                .first {
                    $0.id == focusedElement
                }?.id
        }

        private func supplementContainer(for supplement: some VideoPlayerSupplement) -> some View {
            AlternateLayoutView(alignment: .topLeading) {
                Color.clear
            } content: {
                supplement
                    .coordinatedFocus(ViewState.Focus.supplementContent(supplement.id))
            }
            .environment(viewState)
            .environmentObject(viewState.focusCoordinator)
            .environment(mediaSession)
        }

        private var tabButtons: some View {
            AlternateLayoutView {
                // swiftlint:disable:next hard_coded_display_string
                Button("Hidden") {}
                    .frame(maxWidth: .infinity)
                    .disabled(true)
            } content: { (size: CGSize) in
                HStack(spacing: viewLayout.supplementButtonSpacing) {

                    SelectionTrack(
                        viewState.supplements,
                        id: \.id,
                        title: \.displayTitle,
                        selection: viewState.selectedSupplementID,
                        focus: $focusedElement,
                        spacing: viewLayout.supplementButtonSpacing
                    ) { supplement in
                        if viewLayout.isLarge {
                            viewState.selectedSupplementID = supplement.id
                        } else {
                            viewState.selectedSupplementID = viewState.selectedSupplementID == supplement.id ? nil : supplement.id
                            UIDevice.impact(.light)
                        }
                    }
                    .coordinatedFocus(ViewState.Focus.supplementTabs)
                }
                .scrollIfLargerThanContainer(axes: .horizontal, alignment: .leading)
            }
            .edgePadding(.horizontal)
                // Menu dismissal can restore a tab before the content finishes appearing.
                // Keep tabs out of the focus engine until the requested control receives focus.
                .disabled(viewState.isSupplementFocusPending)
                .defaultFocus(
                    $focusedElement,
                    defaultTabFocus,
                    priority: .userInitiated
                )
                .focusSection()
                .onMoveCommand { direction in
                    if direction == .up, viewState.isPresentingSupplement {
                        viewState.selectedSupplementID = nil
                    }
                }
            .padding(.bottom, viewLayout.isLarge ? 0 : 8)
            .buttonStyle(.capsule)
            .controlSize(.large)
            .foregroundStyle(.white)
        }

        var body: some View {
            ZStack {

                VStack(alignment: .leading, spacing: 0) {

                    tabButtons

                    SupplementTabView(
                        data: viewState.supplements,
                        selection: Binding(
                            get: { viewState.selectedSupplementID },
                            set: { viewState.selectedSupplementID = $0 }
                        )
                    ) { supplement in
                        supplementContainer(for: supplement)
                            .eraseToAnyView()
                    }
                    .onSelectionPresented { id in
                            viewState.focusSupplementIfNeeded(id)
                        }
                        .onFocusExit(.up, perform: viewState.singleSupplement == nil ? nil : { @MainActor in
                            viewState.selectedSupplementID = nil
                        })
                    .isVisible(viewState.isPresentingSupplement)
                    .enabled(viewState.isPresentingSupplement)
                    .animation(.linear(duration: 0.25), value: viewState.selectedSupplementID)
                }
                .isVisible(viewState.visibleElements.contains(.supplements))
                .enabled(viewState.visibleElements.contains(.supplements))
                .padding(.top, viewLayout.edgeInsets.bottom / (viewLayout.isLarge ? 2 : 1))
                .animation(.linear(duration: 0.25), value: viewState.presentation)
                .animation(.linear(duration: 0.1), value: viewState.isScrubbing)
                .animation(.bouncy(duration: 0.25, extraBounce: 0.1), value: viewState.supplements.map(\.id))
            }
            .withViewContext(.isOverComplexContent)
            .task(id: focusedSupplementID) {
                let previousSelection = viewState.selectedSupplementID
                guard !viewState.isSupplementFocusPending,
                      let id = focusedSupplementID, id != previousSelection
                else { return }

                if previousSelection != nil {
                    do {
                        try await Task.sleep(for: .milliseconds(500))
                    } catch {
                        return
                    }
                }

                guard !Task.isCancelled,
                      !viewState.isSupplementFocusPending,
                      focusedSupplementID == id,
                      viewState.selectedSupplementID == previousSelection
                else { return }

                viewState.selectedSupplementID = id
            }
        }
    }
}
