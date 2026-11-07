//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//
// 本文件改自 Swiftfin：Shared/Views/VideoPlayer/Components/Toolbar/ActionButtons/PlaybackRateActionButton.swift
// Modifications for MoviePilot-TV are also licensed under MPL-2.0.
//
// 修改：可选速率的 Swiftfin 设置项换成常量 `VideoPlayerDefaults.playbackRates`（取 Swiftfin 默认值）。
//

import SwiftUI

extension VideoPlayer.PlaybackControls.Toolbar.ActionButtons {

    struct PlaybackRateMenu: View {

        private let rates: [Double] = VideoPlayerDefaults.playbackRates

        @Environment(ViewState.self)
        private var viewState
        @Environment(MediaSession.self)
        private var mediaSession

        var body: some View {
            @Bindable
            var mediaSession = mediaSession
            let supportedRates = mediaSession.player?.supportedRates ?? 0.1 ... 5
            let selection = Binding(get: { mediaSession.effectiveRate }, set: { mediaSession.rate = $0 })

            Menu(
                L10n.playbackSpeed,
                systemImage: VideoPlayerActionButton.playbackSpeed.systemImage
            ) {
                Picker(L10n.playbackSpeed, selection: selection) {
                    ForEach(rates.filter { supportedRates.contains($0) }, id: \.self) { rate in
                        Text(rate, format: .playbackRate)
                            .tag(rate)
                    }

                    if !rates.contains(mediaSession.effectiveRate) {
                        Divider()

                        Text(mediaSession.effectiveRate, format: .playbackRate)
                            .tag(mediaSession.effectiveRate)
                    }
                }

                Divider()

                Button(L10n.custom) {
                    viewState.presentGuestSupplement(PlaybackAdjustmentSupplement.playbackSpeed(range: supportedRates))
                }
            }
        }
    }
}
