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
// 大屏工具栏按钮直径由 56 改为 66，配合缩小的图标，留白接近系统播放器按钮。
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

    var edgePadding: CGFloat {
        value(standard: value(compact: 16, regular: 24), large: 60)
    }

    var edgeInsets: EdgeInsets {
        EdgeInsets(edgePadding)
    }

    var itemSpacing: CGFloat {
        value(standard: 10, large: 40)
    }

    var controlHeight: CGFloat {
        value(standard: 44, large: 75)
    }

    var selectionBorderWidth: CGFloat {
        value(standard: 8, large: 12)
    }

    var indicatorSize: CGFloat {
        value(standard: 25, large: 45)
    }

    var supplementLogoHeight: CGFloat {
        value(standard: 40, large: 80)
    }

    var supplementRowHeight: CGFloat {
        value(standard: 50, large: 80)
    }

    var toolbarButtonSize: CGFloat {
        value(standard: 44, large: 66)
    }

    var supplementButtonSpacing: CGFloat {
        value(standard: 10, large: 20)
    }

    var toolbarButtonSpacing: CGFloat {
        UIDevice.supportsLiquidGlass ? value(standard: 4, large: 20) : value(standard: 0, large: 16)
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
        content.padding(edges, viewLayout.edgePadding)
    }
}

extension View {

    /// 原版把容器尺寸写进 `frameForParentView` 环境供 `AdaptiveLayout` 读取；tvOS 上播放器用到的布局值与容器尺寸无关，这里不再写入。
    func layoutContainer(size: CGSize) -> some View {
        self
    }
}
