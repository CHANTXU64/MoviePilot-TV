//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//
// 本文件改自 Swiftfin：Shared/Components/Layouts/AdaptiveLayout.swift
// Modifications for MoviePilot-TV are also licensed under MPL-2.0.
//
// 修改：只保留播放器用到的成员。tvOS 上 `presentation` 恒为 `.large`，播放器用到的尺寸都只取决于它，
// 因此 `AdaptiveLayout` 不再读取 `frameForParentView` 容器尺寸，直接给出平台默认布局。
// 左右边距单独取 81（`horizontalSafeInset`），进度条、标题、按钮、面板标签和卡片行都对齐这条线；上下仍是 60。
// 工具栏按钮按 HIG 的 tvOS 默认控件尺寸取 66，图标 26。
//

import SwiftUI

nonisolated struct ViewLayout: Equatable {

    enum Presentation {

        case standard
        case large

        static var current: Self {
            #if os(tvOS)
            .large
            #else
            .standard
            #endif
        }
    }

    var size: CGSize = .zero
    var isRegularWidth: Bool = false
    var contentSizeCategory: UIContentSizeCategory = .large
    var presentation: Presentation = .current

    static let platformDefault = ViewLayout()

    var isLarge: Bool {
        presentation == .large
    }

    var isAccessibilitySize: Bool {
        contentSizeCategory.isAccessibilityCategory
    }

    var isCompact: Bool {
        isAccessibilitySize || (size.width > 0 ? size.width < 600 : !isRegularWidth)
    }

    var usesCompactPlayer: Bool {
        !isLarge && size.width < 600 && size.height >= 500
    }

    func value<Value>(compact: Value, regular: Value) -> Value {
        isCompact ? compact : regular
    }

    func value<Value>(standard: Value, large: Value) -> Value {
        isLarge ? large : standard
    }

    /// 播放界面左右两边的留白，与 App 里详情页选集行等卡片行相同（HIG 的 tvOS 左右安全区是 80）。
    /// 进度条、标题、按钮、面板标签和剧照卡都对齐这条线，焦点在它们之间移动时画面不会左右挪。
    static let horizontalSafeInset: CGFloat = 81

    /// 上下留白（tvOS 安全区）。左右见 `horizontalEdgePadding`。
    var edgePadding: CGFloat {
        value(standard: value(compact: 16, regular: 24), large: 60)
    }

    var horizontalEdgePadding: CGFloat {
        value(standard: edgePadding, large: Self.horizontalSafeInset)
    }

    var edgeInsets: EdgeInsets {
        EdgeInsets(edgePadding)
    }

    var itemSpacing: CGFloat {
        value(standard: 10, large: 40)
    }

    var toolbarButtonSize: CGFloat {
        value(standard: 44, large: 66)
    }

    var toolbarIconSize: CGFloat {
        value(standard: 18, large: 26)
    }

    /// HIG 给 tvOS 的最小控件尺寸。
    var controlMinimumSize: CGFloat {
        value(standard: 44, large: 56)
    }

    var supplementButtonSpacing: CGFloat {
        value(standard: 10, large: 20)
    }

    var toolbarButtonSpacing: CGFloat {
        value(standard: 4, large: 24)
    }

    init(
        size: CGSize = .zero,
        isRegularWidth: Bool = false,
        contentSizeCategory: UIContentSizeCategory = .large,
        presentation: Presentation = .current
    ) {
        self.size = size
        self.isRegularWidth = isRegularWidth
        self.contentSizeCategory = contentSizeCategory
        self.presentation = presentation
    }

    init(size: CGSize, traits: UITraitCollection) {
        self.init(
            size: size,
            isRegularWidth: traits.horizontalSizeClass == .regular,
            contentSizeCategory: traits.preferredContentSizeCategory
        )
    }
}

@propertyWrapper
struct AdaptiveLayout: DynamicProperty {

    var wrappedValue: ViewLayout {
        .platformDefault
    }
}

struct EdgePaddingModifier: ViewModifier {

    @AdaptiveLayout
    private var viewLayout

    let edges: Edge.Set

    func body(content: Content) -> some View {
        content
            .padding(edges.intersection(.horizontal), viewLayout.horizontalEdgePadding)
            .padding(edges.intersection(.vertical), viewLayout.edgePadding)
    }
}

extension View {

    /// 原版把容器尺寸写进 `frameForParentView` 环境供 `AdaptiveLayout` 读取；tvOS 上播放器用到的布局值与容器尺寸无关，这里不再写入。
    func layoutContainer(size: CGSize) -> some View {
        self
    }
}
