//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//
// 本文件改自 Swiftfin：Shared/Objects/VideoPlayerSupplementKind.swift
// Modifications for MoviePilot-TV are also licensed under MPL-2.0.
//
// 修改：去掉 Swiftfin 设置存储相关的 `Storable`、`SupportedCaseIterable` 一致性（设置项由 `VideoPlayerDefaults` 提供）。
//

enum VideoPlayerSupplementType: String, CaseIterable, Displayable, Equatable, Identifiable, SystemImageable {

    case info
    case chapters
    case queue
    case playbackInformation
    case people

    var displayTitle: String {
        switch self {
        case .info:
            L10n.info
        case .chapters:
            L10n.chapters
        case .queue:
            L10n.queue
        case .people:
            L10n.people
        case .playbackInformation:
            L10n.session
        }
    }

    var id: String {
        rawValue
    }

    var systemImage: String {
        switch self {
        case .info:
            "info.circle.fill"
        case .chapters:
            "list.bullet.rectangle.fill"
        case .queue:
            "list.triangle"
        case .people:
            "person.2.fill"
        case .playbackInformation:
            "waveform.circle.fill"
        }
    }

    static let supportedCases: [VideoPlayerSupplementType] = [.info, .chapters, .queue]
}
