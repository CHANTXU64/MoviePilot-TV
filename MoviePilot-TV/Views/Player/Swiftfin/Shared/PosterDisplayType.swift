//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//
// 本文件改自 Swiftfin：Shared/Objects/PosterDisplayType.swift
// Modifications for MoviePilot-TV are also licensed under MPL-2.0.
//
// 修改：去掉 Swiftfin 设置存储用的 `Storable` 一致性；标为 `nonisolated`，可在环境值默认值中使用。
//

import Foundation

nonisolated enum PosterDisplayType: String, CaseIterable, Displayable, SystemImageable {

    enum Size: Equatable, Hashable {

        case extraSmall
        case small
        case medium
        case custom(width: CGFloat)

        var quality: Int? {
            90
        }

        func width(
            for displayType: PosterDisplayType,
            presentation: ViewLayout.Presentation = .current
        ) -> CGFloat? {
            switch self {
            case .extraSmall:
                switch displayType {
                case .landscape:
                    110
                case .portrait, .square:
                    60
                }

            case .small:
                if presentation == .large {
                    500
                } else {
                    displayType == .landscape ? 300 : 200
                }

            case .medium:
                500

            case let .custom(width):
                width
            }
        }
    }

    case landscape
    case portrait
    case square

    var displayTitle: String {
        switch self {
        case .landscape:
            L10n.landscape
        case .portrait:
            L10n.portrait
        case .square:
            L10n.square
        }
    }

    var systemImage: String {
        switch self {
        case .landscape:
            "rectangle.fill"
        case .portrait:
            "rectangle.portrait.fill"
        case .square:
            "square.fill"
        }
    }
}
