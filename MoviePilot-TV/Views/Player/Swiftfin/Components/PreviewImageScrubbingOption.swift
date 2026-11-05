//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//
// 本文件改自 Swiftfin：Shared/Objects/PreviewImageScrubbingOption.swift
// Modifications for MoviePilot-TV are also licensed under MPL-2.0.
//
// 修改：去掉 Swiftfin 设置存储用的 `Storable` 一致性。
//

enum PreviewImageScrubbingOption: CaseIterable, Displayable, Hashable {

    case trickplay(fallbackToChapters: Bool = true)
    case chapters
    case disabled

    var displayTitle: String {
        switch self {
        case .trickplay:
            L10n.trickplays
        case .disabled:
            L10n.disabled
        case .chapters:
            L10n.chapters
        }
    }

    static var allCases: [PreviewImageScrubbingOption] {
        [.trickplay(), .chapters, .disabled]
    }
}
