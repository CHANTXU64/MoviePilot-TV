//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//
// 本文件改自 Swiftfin：Shared/Objects/PokeIntervalTimer.swift
// Modifications for MoviePilot-TV are also licensed under MPL-2.0.
//
// 修改：工程默认 MainActor 隔离且开启完整并发检查，延时任务在主队列执行，用 `MainActor.assumeIsolated` 访问状态。
// 补显式非隔离析构 `nonisolated deinit`，避开 tvOS 18 的隔离析构回部署崩溃。
//

import Combine
import Foundation

class PokeIntervalTimer: ObservableObject, Publisher {

    // 显式非隔离析构，避开 tvOS 18 的隔离析构回部署崩溃。
    nonisolated deinit {}

    typealias Output = Void
    typealias Failure = Never

    private let defaultInterval: TimeInterval
    private var delaySubject: PassthroughSubject<Void, Never> = .init()
    private var delayedWorkItem: DispatchWorkItem?

    init(defaultInterval: TimeInterval = 5) {
        self.defaultInterval = defaultInterval
    }

    func receive<S: Subscriber>(subscriber: S) where S.Failure == Never, S.Input == Void {
        delaySubject.receive(subscriber: subscriber)
    }

    func poke(interval: TimeInterval? = nil) {

        let interval = interval ?? defaultInterval

        delayedWorkItem?.cancel()

        let newPollItem = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.delaySubject.send(())
            }
        }

        delayedWorkItem = newPollItem

        DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: newPollItem)
    }

    func stop() {
        delayedWorkItem?.cancel()
        delayedWorkItem = nil
    }
}
