//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//
// 本文件改自 Swiftfin：Shared/Objects/EventPublisher.swift
// Modifications for MoviePilot-TV are also licensed under MPL-2.0.
//
// 修改：Swiftfin 播放器用的 `EventPublisher` 来自第三方 Engine 包，这里沿用 Swiftfin 自带的
// `LegacyEventPublisher` 实现并改名为 `EventPublisher`，补上 `init()`。
//

import Combine

struct EventPublisher<T>: Publisher {
    typealias Output = T
    typealias Failure = Never

    private let subject = PassthroughSubject<T, Never>()

    init() {}

    func receive<S: Subscriber>(subscriber: S) where Never == S.Failure, T == S.Input {
        subject.receive(subscriber: subscriber)
    }

    func send(_ value: T) {
        subject.send(value)
    }
}
