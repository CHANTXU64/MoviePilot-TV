//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//
// 本文件改自 Swiftfin：Shared/Objects/ImageSource.swift
// Modifications for MoviePilot-TV are also licensed under MPL-2.0.
//
// 修改：标为 `nonisolated`（工程默认 MainActor 隔离），可在非隔离上下文中使用。
//

import Foundation

/// Represents an image source along with a blur hash
/// to be used as a placeholder.
nonisolated struct ImageSource: Hashable {

    let url: URL?
    let blurHash: String?

    init(
        url: URL? = nil,
        blurHash: String? = nil
    ) {
        self.url = url
        self.blurHash = blurHash
    }
}
