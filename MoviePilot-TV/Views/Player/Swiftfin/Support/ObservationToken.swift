//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//
// 本文件改自 Swiftfin：Shared/Objects/ObservationToken.swift
// Modifications for MoviePilot-TV are also licensed under MPL-2.0.
//
// 修改：析构显式标为 `nonisolated`（tvOS 18.4–26.2 上，隔离析构在主线程、Task 之外执行会崩溃）。
//

import Combine
import Observation

/// Tracks observable values outside views.
/// Only reads establish dependencies. Changes are delivered after mutation.
@MainActor
final class ObservationToken: @preconcurrency Cancellable {

    // 显式非隔离析构，避开 tvOS 18 的隔离析构回部署崩溃。
    nonisolated deinit {}

    private var update: (() -> Void)?

    init<Value>(
        _ read: @escaping () -> Value,
        onChange: @escaping (Value) -> Void
    ) {
        update = { [weak self] in
            let value = withObservationTracking(read) { [weak self] in
                Task { @MainActor [weak self] in
                    self?.update?()
                }
            }

            onChange(value)
        }

        update?()
    }

    func cancel() {
        update = nil
    }
}
