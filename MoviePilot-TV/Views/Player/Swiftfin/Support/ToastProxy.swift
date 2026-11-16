//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//
// 本文件改自 Swiftfin：Shared/Objects/ToastProxy.swift
// Modifications for MoviePilot-TV are also licensed under MPL-2.0.
//
// 修改：
// - 析构显式标为 `nonisolated`（tvOS 18.4–26.2 上，隔离析构在主线程、Task 之外执行会崩溃）。
// - `present` 可指定显示时长，默认仍为 2 秒。
//

import Combine
import SwiftUI

@propertyWrapper
struct Toaster: DynamicProperty {

    @EnvironmentObject
    private var toastProxy: ToastProxy

    var wrappedValue: ToastProxy {
        toastProxy
    }
}

@MainActor
class ToastProxy: ObservableObject {

    // 显式非隔离析构，避开 tvOS 18 的隔离析构回部署崩溃。
    nonisolated deinit {}

    @Published
    var isPresenting: Bool = false
    @Published
    private(set) var systemName: String? = nil
    @Published
    private(set) var title: Text = Text(String.empty)

    private let pokeTimer = PokeIntervalTimer(defaultInterval: 2)
    private var pokeCancellable: AnyCancellable?

    init() {
        pokeCancellable = pokeTimer
            .sink { [weak self] in
                self?.dismiss()
            }
    }

    /// `duration` 为 nil 时显示 2 秒；句子较长、需要读完的提示可以给长一些。
    func present(_ title: String, systemName: String? = nil, duration: TimeInterval? = nil) {
        present(Text(title), systemName: systemName, duration: duration)
    }

    func present(_ title: Text, systemName: String? = nil, duration: TimeInterval? = nil) {
        self.title = title
        self.systemName = systemName

        poke(equalsPrevious: title == self.title, duration: duration)
    }

    private func poke(equalsPrevious: Bool, duration: TimeInterval?) {
        withAnimation(.easeInOut(duration: 0.2)) {
            isPresenting = true
        }

        pokeTimer.poke(interval: duration)
    }

    func dismiss() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isPresenting = false
        }
    }
}
