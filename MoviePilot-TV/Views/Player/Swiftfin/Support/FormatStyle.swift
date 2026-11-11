//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//
// 本文件改自 Swiftfin：Shared/Extensions/FormatStyle.swift（只保留播放器用到的格式）
// Modifications for MoviePilot-TV are also licensed under MPL-2.0.
//
// 修改：只保留播放器用到的格式；格式类型标为 `nonisolated`（工程默认 MainActor 隔离）。
//

import Foundation

extension FormatStyle where Self == Duration.UnitsFormatStyle {

    nonisolated static var playbackOffset: Duration.UnitsFormatStyle {
        Duration.UnitsFormatStyle(
            allowedUnits: [.seconds],
            width: .abbreviated,
            fractionalPart: .show(length: 2)
        )
    }

    nonisolated static var minuteSecondsAbbreviated: Duration.UnitsFormatStyle {
        Duration.UnitsFormatStyle(
            allowedUnits: [.minutes, .seconds],
            width: .abbreviated
        )
    }
}

nonisolated struct RuntimeFormatStyle: FormatStyle {

    func format(_ value: Duration) -> String {

        let formatStyle: Duration.TimeFormatStyle = if value.components.seconds.magnitude >= 3600 {
            Duration.TimeFormatStyle(pattern: .hourMinuteSecond)
        } else {
            Duration.TimeFormatStyle(pattern: .minuteSecond)
        }

        return formatStyle.format(value)
    }
}

extension FormatStyle where Self == RuntimeFormatStyle {

    nonisolated static var runtime: RuntimeFormatStyle {
        RuntimeFormatStyle()
    }
}

extension FormatStyle where Self == PlaybackRateStyle {

    nonisolated static var playbackRate: PlaybackRateStyle {
        PlaybackRateStyle()
    }

    nonisolated static func playbackRate(precision: Int) -> PlaybackRateStyle {
        PlaybackRateStyle(precision: precision)
    }
}

nonisolated struct PlaybackRateStyle: FormatStyle {

    private let precision: Int

    init(precision: Int = 2) {
        self.precision = precision
    }

    func format(_ value: Double) -> String {
        FloatingPointFormatStyle<Double>()
            .precision(.fractionLength(0 ... precision))
            .format(value)
            .appending(String.multiply)
    }
}

nonisolated struct IntBitRateFormatStyle: FormatStyle {

    func format(_ value: Int) -> String {
        let units = [
            L10n.bitsPerSecond,
            L10n.kilobitsPerSecond,
            L10n.megabitsPerSecond,
            L10n.gigabitsPerSecond,
            L10n.terabitsPerSecond,
        ]

        var adjustedValue = Double(value)
        var unitIndex = 0

        while adjustedValue >= 1000, unitIndex < units.count - 1 {
            adjustedValue /= 1000
            unitIndex += 1
        }

        let formattedValue = String(format: "%.1f", adjustedValue)

        return "\(formattedValue) \(units[unitIndex])"
    }
}

extension FormatStyle where Self == IntBitRateFormatStyle {

    nonisolated static var bitRate: IntBitRateFormatStyle {
        IntBitRateFormatStyle()
    }
}
