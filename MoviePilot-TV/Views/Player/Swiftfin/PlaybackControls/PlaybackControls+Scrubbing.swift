//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//
// 本文件改自 Swiftfin：Swiftfin tvOS/Views/VideoPlayer/PlaybackControls/Components/PlaybackControls+Scrubbing.swift
// Modifications for MoviePilot-TV are also licensed under MPL-2.0.
//
// 修改：长按加速倍率由 Swiftfin 设置项换成常量（保持 Swiftfin 默认 2 倍）；快进快退间隔是 `Duration` 常量，去掉 `.rawValue`。
// 图标名改从 AppSymbol 取（项目统一图标来源），图标本身不变。
//

import Foundation
import SwiftUI

extension VideoPlayer.PlaybackControls {

    func startSpeedBoost() {
        guard mediaSession.canControlPlayback, !isSpeedBoosting, speedBoostTimer == nil else { return }

        viewState.setInteraction(.speedBoost, active: true)

        speedBoostTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [self] _ in
            // This timer is scheduled on the main actor's run loop.
            MainActor.assumeIsolated {
                isSpeedBoosting = true
                viewState.originalPlaybackRate = mediaSession.rate

                let multiplier = VideoPlayerDefaults.longPressSpeedMultiplier
                mediaSession.rate = multiplier

                toaster.present(
                    Text(multiplier, format: .playbackRate),
                    systemName: AppSymbol.speedBoost
                )
            }
        }
    }

    func stopSpeedBoost(performJump: Bool = false) {
        speedBoostTimer?.invalidate()
        speedBoostTimer = nil
        viewState.setInteraction(.speedBoost, active: false)

        if isSpeedBoosting {
            if let originalRate = viewState.originalPlaybackRate {
                mediaSession.rate = originalRate

                toaster.present(
                    Text(originalRate, format: .playbackRate),
                    systemName: AppSymbol.speedBoost
                )
            }

            viewState.originalPlaybackRate = nil
            isSpeedBoosting = false
            return
        }

        if performJump {
            jumpForward()
        }
    }

    func jumpForward() {
        guard mediaSession.seek(by: jumpForwardInterval) else { return }

        viewState.showProgress()
        viewState.jumpProgressObserver.jumpForward()

        toaster.present(
            Text(
                jumpForwardInterval * viewState.jumpProgressObserver.jumps,
                format: .minuteSecondsAbbreviated
            ),
            systemName: AppSymbol.jumpForward
        )
    }

    func jumpBackward() {
        guard mediaSession.seek(by: .zero - jumpBackwardInterval) else { return }

        viewState.showProgress()
        viewState.jumpProgressObserver.jumpBackward()

        toaster.present(
            Text(
                jumpBackwardInterval * viewState.jumpProgressObserver.jumps,
                format: .minuteSecondsAbbreviated
            ),
            systemName: AppSymbol.jumpBackward
        )
    }
}
