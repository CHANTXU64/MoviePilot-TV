//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//
// 本文件改自 Swiftfin：Shared/Views/VideoPlayer/Components/Toolbar/ActionButtons/VideoPlayer+ActionButtons.swift
// Modifications for MoviePilot-TV are also licensed under MPL-2.0.
//
// 修改：删去 iOS 分支（投屏）；按钮列表的 Swiftfin 设置项 `barActionButtons` / `menuActionButtons` 换成
// `VideoPlayerDefaults` 里的同名常量（取值即 Swiftfin 默认值），过滤规则不变。
//

import SwiftUI

// TODO: ensure changes on playback item change

extension VideoPlayer.PlaybackControls.Toolbar {

    struct ActionButtons: View {

        typealias ViewState = VideoPlayer.ViewState

        @AdaptiveLayout
        private var viewLayout

        private let rawBarActionButtons = VideoPlayerDefaults.barActionButtons
        private let rawMenuActionButtons = VideoPlayerDefaults.menuActionButtons

        @Environment(ViewState.self)
        private var viewState
        @Environment(MediaSession.self)
        private var mediaSession


        @FocusState
        private var focusedButton: String?

        private func resolvedActionButtons(_ rawButtons: [VideoPlayerActionButton]) -> [VideoPlayerActionButton] {
            var filteredButtons = rawButtons

            filteredButtons.removeAll(equalTo: .pictureInPicture)
            if mediaSession.isRemotePlayback {
                filteredButtons.removeAll { $0 == .aspectFill || $0 == .pictureInPicture }
            }

            if mediaSession.playbackItem?.audioStreams.isEmpty == true {
                filteredButtons.removeAll { $0 == .audio || $0 == .audioOffset }
            }

            if mediaSession.playbackItem?.subtitleStreams.isEmpty == true {
                filteredButtons.removeAll { $0 == .subtitles || $0 == .subtitleOffset }
            }

            if mediaSession.playbackItem == nil || !(mediaSession.player is MediaPlayerOffsetProviding) {
                filteredButtons.removeAll { $0 == .audioOffset || $0 == .subtitleOffset }
            }

            if !PlaybackSettings.isAvailable(for: mediaSession.playbackItem) {
                filteredButtons.removeAll(equalTo: .playbackSettings)
            }

            if mediaSession.queue == nil {
                filteredButtons.removeAll { $0 == .autoPlay }
                filteredButtons.removeAll { $0 == .playNextItem }
                filteredButtons.removeAll { $0 == .playPreviousItem }
            }

            let chapterCount = viewState.supplements
                .compactMap { $0 as? MediaChaptersSupplement }
                .first?
                .chapters
                .count ?? 0

            if chapterCount < 2 {
                filteredButtons.removeAll { $0 == .nextChapter }
                filteredButtons.removeAll { $0 == .previousChapter }
            }

            if mediaSession.item.isLiveStream {
                filteredButtons.removeAll { $0 == .autoPlay }
                filteredButtons.removeAll { $0 == .playbackSpeed }
                filteredButtons.removeAll { $0 == .playbackSettings }
            }

            return filteredButtons
        }

        private var barActionButtons: [VideoPlayerActionButton] {
            resolvedActionButtons(rawBarActionButtons)
        }

        private var menuActionButtons: [VideoPlayerActionButton] {
            resolvedActionButtons(rawMenuActionButtons)
        }

        private var menuSystemImage: String {
            if viewLayout.isLarge || UIDevice.supportsLiquidGlass {
                "ellipsis"
            } else {
                "ellipsis.circle"
            }
        }

        private var menuLabel: some View {
            Label(L10n.menu, systemImage: menuSystemImage)
        }

        @ViewBuilder
        private func view(for button: VideoPlayerActionButton) -> some View {
            switch button {
            case .aspectFill:
                AspectFill()
            case .audio:
                Audio()
            case .audioOffset:
                AudioOffset()
            case .autoPlay:
                AutoPlay()
            case .pictureInPicture:
                PictureInPicture()
            case .playbackSpeed:
                PlaybackRateMenu()
            case .playbackSettings:
                PlaybackSettings()
            case .playNextItem:
                PlayNextItem()
            case .playPreviousItem:
                PlayPreviousItem()
            case .nextChapter:
                NextChapter()
            case .previousChapter:
                PreviousChapter()
            case .subtitles:
                Subtitles()
            case .subtitleOffset:
                SubtitleOffset()
            }
        }

        @ViewBuilder
        private var compactView: some View {
            let barButtons = barActionButtons
            let menuButtons = menuActionButtons.subtracting(barActionButtons)

            Menu {
                ForEach(
                    barButtons,
                    content: view(for:)
                )

                if barButtons.isNotEmpty, menuButtons.isNotEmpty {
                    Divider()
                }

                ForEach(
                    menuButtons,
                    content: view(for:)
                )
            } label: {
                menuLabel
            }
            .frame(width: viewLayout.toolbarButtonSize, height: viewLayout.toolbarButtonSize)
            .withViewContext(.isInMenu)
        }

        private var regularView: some View {
            HStack(spacing: viewLayout.toolbarButtonSpacing) {
                ForEach(barActionButtons) { button in
                    view(for: button)
                        .frame(width: viewLayout.toolbarButtonSize, height: viewLayout.toolbarButtonSize)
                        .coordinatedFocus(ViewState.Focus.action(button.rawValue), selection: $focusedButton)
                }

                if menuActionButtons.isNotEmpty {
                    Menu {
                        ForEach(
                            menuActionButtons,
                            content: view(for:)
                        )
                        .withViewContext(.isInMenu)
                    } label: {
                        menuLabel
                    }
                    .frame(width: viewLayout.toolbarButtonSize, height: viewLayout.toolbarButtonSize)
                    .coordinatedFocus(ViewState.Focus.action("menu"), selection: $focusedButton)
                }
            }
            .defaultFocus(
                $focusedButton,
                ViewState.Focus.action(barActionButtons.first?.rawValue ?? "menu"),
                priority: .userInitiated
            )
            .focusSection()
        }

        var body: some View {
            Group {
                if viewState.isCompact {
                    compactView
                } else {
                    regularView
                }
            }
            .modifier(VideoPlayer.PlaybackControls.OverlayBarButtonStyleModifier())
        }
    }
}
