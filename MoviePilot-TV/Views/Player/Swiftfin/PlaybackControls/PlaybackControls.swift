//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//
// 本文件改自 Swiftfin：Swiftfin tvOS/Views/VideoPlayer/PlaybackControls/PlaybackControls.swift
// Modifications for MoviePilot-TV are also licensed under MPL-2.0.
//
// 修改：补 `import Combine`（MemberImportVisibility）；左右键按系统播放器处理：点一下跳 10 秒，按住快退、快进
// （见 PlaybackControls+PressHandling.swift），跳转不再弹顶部提示。
//

import Combine
import SwiftUI

extension VideoPlayer {

    struct PlaybackControls: View {

        typealias ViewState = VideoPlayer.ViewState

        @Environment(ViewState.self)
        var viewState
        @Environment(MediaSession.self)
        var mediaSession

        @EnvironmentObject
        private var focusCoordinator: FocusCoordinator

        /// 正在处理的左右键（按下到松开之间）。
        @State
        var seekingPress: UIPress.PressType?
        /// 等待长按的计时；按满 `VideoPlayerDefaults.scanHoldDelay` 开始快退、快进。
        @State
        var scanHoldTask: Task<Void, Never>?
        /// 这次按键已经靠按住开始了快退快进：松开时不再当成点一下。
        @State
        var didBeginScanByHolding = false

        var body: some View {
            @Bindable
            var viewState = viewState

            VStack(spacing: 0) {

                Toolbar()
                    .isVisible(viewState.visibleElements.contains(.toolbar))
                    .enabled(viewState.visibleElements.contains(.toolbar))
                    .padding(.bottom, 30)

                PlaybackProgress()
                    .fixedSize(horizontal: false, vertical: true)
                    .isVisible(viewState.isPresentingProgress)
                    .enabled(viewState.isPresentingProgress)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .edgePadding(.horizontal)
            .focusSection()
            .coordinatedFocus(ViewState.Focus.controls)
            .animation(.easeInOut(duration: 0.25), value: viewState.isPresentingSupplement)
            .animation(.easeInOut(duration: 0.25), value: viewState.presentation)
            .animation(.linear(duration: 0.1), value: viewState.isScrubbing)
            .alert(L10n.closePlayer, isPresented: $viewState.isPresentingCloseConfirmation) {
                Button(L10n.cancel, role: .cancel) {}

                Button(L10n.ok, role: .destructive) {
                    mediaSession.stop()
                }
            } message: {
                Text(L10n.closePlayerWarning)
            }
            .onReceive(viewState.containerView?.onPressEvent ?? .init()) { press in
                handlePressEvent(press)
            }
            .onDisappear {
                resetSeekingPress()
                viewState.discardScrub()
            }
            .onChange(of: mediaSession.playbackItem.map(ObjectIdentifier.init), initial: true) { _, _ in
                resetSeekingPress()
            }
            .onReceive(
                focusCoordinator.$focusedIDs
                    .map { $0.contains(ViewState.Focus.progress) }
                    .removeDuplicates()
                    .dropFirst()
            ) { isFocused in
                guard !isFocused else { return }

                viewState.cancelScrub()
                resetSeekingPress()
            }
        }
    }
}
