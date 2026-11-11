//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//
// 本文件改自 Swiftfin：Shared/Objects/Empty.swift
// Modifications for MoviePilot-TV are also licensed under MPL-2.0.
//
// 修改：去掉播放器用不到的 `WithRefresh`、`EvaluatedLocalUserAccessPolicy` 一致性。
// 标为 `nonisolated`（工程默认 MainActor 隔离）。
//

nonisolated struct Empty: Equatable {}

nonisolated extension Empty: WithDefaultValue {
    static let `default`: Empty = .init()
}
