//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//
// 本文件改自 Swiftfin：Shared/Objects/WithDefaultValue.swift
// Modifications for MoviePilot-TV are also licensed under MPL-2.0.
//
// 修改：标为 `nonisolated`（工程默认 MainActor 隔离），可被非隔离类型遵循。
//

nonisolated protocol WithDefaultValue: Equatable {
    static var `default`: Self { get }
}
