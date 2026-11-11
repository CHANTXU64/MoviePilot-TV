//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//
// 本文件改自 Swiftfin：Shared/Views/VideoPlayer/Components/PlaybackProgress/SplitTimestamp.swift
// Modifications for MoviePilot-TV are also licensed under MPL-2.0.
//
// 修改：tvOS 的 `PresentationView` 恒走 `largeView`，这里只保留 `largeView` 作为 `body`，去掉 iOS 用的 `standardView`
// 及其“剩余/总时长”切换设置项；无障碍文案换成中文（取自 Swiftfin 的简体中文翻译）。
// 图标名改从 AppSymbol 取（项目统一图标来源），图标本身不变。
//

import SwiftUI

extension VideoPlayer.PlaybackControls {

    struct SplitTimeStamp: View {

        @AdaptiveLayout
        private var viewLayout

        @Environment(ViewState.self)
        private var viewState
        @Environment(MediaSession.self)
        private var mediaSession

        @State
        private var contentSize: CGSize = .zero
        @State
        private var leadingTimestampSize: CGSize = .zero
        @State
        private var trailingTimestampSize: CGSize = .zero

        private let statusIndicatorSize: CGFloat = 22

        private var scrubbedProgress: Double {
            guard let runtime = mediaSession.item.runtime, runtime > .zero else { return 0 }

            return scrubbedSeconds / runtime
        }

        private var previewXOffset: CGFloat {
            let p = contentSize.width * scrubbedProgress - (leadingTimestampSize.width / 2)

            return clamp(p, min: 0, max: contentSize.width - leadingTimestampSize.width)
        }

        private var shouldHideTrailingTimestamp: Bool {
            let leadingTimestampMaxX = previewXOffset + leadingTimestampSize.width
            let trailingTimestampMinX = contentSize.width - trailingTimestampSize.width

            return leadingTimestampMaxX >= trailingTimestampMinX
        }

        private var isScrubbing: Bool {
            viewState.isScrubbing
        }

        private var scrubbedSeconds: Duration {
            viewState.scrubbedSeconds
        }

        @ViewBuilder
        private var playbackStatusIndicator: some View {
            if mediaSession.activity == .loading || mediaSession.playbackState.isBuffering {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.primary)
                    .visualEffect { content, geometry in
                        content.scaleEffect(statusIndicatorSize / max(geometry.size.width, 1))
                    }
                    .frame(width: statusIndicatorSize, height: statusIndicatorSize)
                    .accessibilityLabel(mediaSession.activity == .loading ? "加载中" : "缓冲中")
            } else if mediaSession.playbackRequestStatus == .paused {
                Image(systemName: AppSymbol.playbackPaused)
                    .resizable()
                    .scaledToFit()
                    .frame(width: statusIndicatorSize, height: statusIndicatorSize)
                    .accessibilityLabel("暂停")
            }
        }

        var body: some View {
            ZStack {
                if let runtime = mediaSession.item.runtime {
                    Text(.zero - (runtime - scrubbedSeconds), format: .runtime)
                        .accessibilityIdentifier("playbackRemainingTime")
                } else {
                    Text(verbatim: .emptyRuntime)
                }
            }
            .opacity(shouldHideTrailingTimestamp ? 0 : 1)
            .animation(.linear(duration: 0.1), value: shouldHideTrailingTimestamp)
            .trackingSize($trailingTimestampSize)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .overlay(alignment: .leading) {
                HStack(spacing: 8) {
                    playbackStatusIndicator
                    Text(scrubbedSeconds, format: .runtime)
                        .accessibilityIdentifier("playbackElapsedTime")
                }
                .trackingSize($leadingTimestampSize)
                .offset(x: previewXOffset)
            }
            .font(.caption)
            .fontWeight(viewLayout.value(standard: nil, large: .medium))
            .monospacedDigit()
            .trackingSize($contentSize)
            .foregroundStyle(viewState.isProgressBarFocused ? .primary : .secondary)
            .opacity(viewState.isProgressBarFocused ? 1 : 0.7)
        }
    }
}
