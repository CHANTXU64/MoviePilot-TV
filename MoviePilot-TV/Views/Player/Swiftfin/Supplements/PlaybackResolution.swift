//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//
// 本文件改自 Swiftfin：Shared/Objects/PlaybackResolution.swift
// Modifications for MoviePilot-TV are also licensed under MPL-2.0.
//
// 修改：去掉 `Storable` 一致性和生成 Jellyfin 转码配置的 `codecProfile(for:)`（MoviePilot-TV 只直连原文件，不转码）。
//

import Foundation

enum PlaybackResolution: Int, CaseIterable, Displayable {

    case max = 0
    case p2160 = 2160
    case p1440 = 1440
    case p1080 = 1080
    case p720 = 720
    case p480 = 480
    case p360 = 360
    case p240 = 240

    // swiftlint:disable:next hard_coded_display_string
    var displayTitle: String {
        switch self {
        case .max:
            return L10n.maximum
        default:
            guard rawValue > 0 else { return L10n.unknown }

            return "\(rawValue.description)p"
        }
    }
}
