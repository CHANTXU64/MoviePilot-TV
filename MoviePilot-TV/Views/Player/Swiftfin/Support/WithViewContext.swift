//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//
// 本文件改自 Swiftfin：Shared/Objects/WithViewContext.swift
// Modifications for MoviePilot-TV are also licensed under MPL-2.0.
//
// 修改：Swiftfin 用 `@OptionSet` 宏生成 `ViewContext`，这里手写等价的 OptionSet，选项与原版相同；
// 环境值改用显式 `EnvironmentKey`（与工程其他环境值写法一致）。
//

import SwiftUI

nonisolated struct ViewContext: OptionSet, Sendable {

    let rawValue: Int

    static let isListRowSeparatorVisible = ViewContext(rawValue: 1 << 0)
    static let isInMenu = ViewContext(rawValue: 1 << 1)
    static let isThumb = ViewContext(rawValue: 1 << 2)
    static let isOverComplexContent = ViewContext(rawValue: 1 << 3)
    static let isInParent = ViewContext(rawValue: 1 << 4)
    static let isInResume = ViewContext(rawValue: 1 << 5)
    static let isBackdrop = ViewContext(rawValue: 1 << 6)
}

private nonisolated struct ViewContextKey: EnvironmentKey {

    static let defaultValue: ViewContext = .init()
}

extension EnvironmentValues {

    nonisolated var viewContext: ViewContext {
        get { self[ViewContextKey.self] }
        set { self[ViewContextKey.self] = newValue }
    }
}

@propertyWrapper
struct ViewContextContains: DynamicProperty {

    @Environment(\.viewContext)
    private var oldValue: ViewContext

    private let viewContext: ViewContext

    init(_ viewContext: ViewContext) {
        self.viewContext = viewContext
    }

    var wrappedValue: Bool {
        oldValue.contains(viewContext)
    }
}

extension View {

    func withViewContext(_ context: ViewContext) -> some View {
        modifier(InsertingViewContextModifier(insertingContext: context))
    }
}

private struct InsertingViewContextModifier: ViewModifier {

    @Environment(\.viewContext)
    private var environmentContext

    let insertingContext: ViewContext

    func body(content: Content) -> some View {
        content.environment(\.viewContext, environmentContext.union(insertingContext))
    }
}
