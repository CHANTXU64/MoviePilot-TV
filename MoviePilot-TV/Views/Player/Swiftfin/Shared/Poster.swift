//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//
// 本文件改自 Swiftfin：Shared/Objects/Poster/Poster.swift
//
// 修改：去掉 `ImageBody` 与 `transform(image:displayType:)`：海报图改由 `PageManagedImage` 显示，不再支持各类型自定义
// 图片样式，只保留原版用到的一种：`fitsPosterImage` 为 true 时在黑底上按比例完整显示（见 PosterImage.swift）。
//

import Foundation
import SwiftUI

typealias ImageSourceBuilder = ArrayBuilder<ImageSource>

/// A type that is displayed as a poster
protocol Poster: Displayable, Hashable, Identifiable, SystemImageable {

    associatedtype Environment: WithDefaultValue = Empty
    associatedtype LabelBody: View = EmptyView
    associatedtype ContextMenuBody: View = EmptyView
    associatedtype OverlayBody: View = EmptyView

    var preferredPosterDisplayType: PosterDisplayType { get }

    /// 图片在海报框里按比例完整显示、空出来的地方是黑底（章节截图）；默认按比例填满。
    var fitsPosterImage: Bool { get }

    /// Optional subtitle when used as a poster
    var subtitle: String? { get }

    func posterAccessibility(configuration: PosterConfiguration) -> PosterAccessibility

    func resolveEnvironment(_ environment: EnvironmentValues) -> Environment

    @ImageSourceBuilder
    func imageSources(
        for displayType: PosterDisplayType,
        environment: Environment
    ) -> [ImageSource]

    @MainActor
    @ViewBuilder
    var posterLabel: LabelBody { get }

    @MainActor
    @ViewBuilder
    var posterContextMenu: ContextMenuBody { get }

    @MainActor
    @ViewBuilder
    func posterOverlay(for displayType: PosterDisplayType) -> OverlayBody
}

extension Poster {

    var fitsPosterImage: Bool { false }
}

@MainActor
extension Poster where LabelBody == EmptyView {

    var posterLabel: LabelBody {
        EmptyView()
    }
}

@MainActor
extension Poster where ContextMenuBody == EmptyView {

    var posterContextMenu: ContextMenuBody {
        EmptyView()
    }
}

@MainActor
extension Poster where OverlayBody == EmptyView {

    func posterOverlay(for displayType: PosterDisplayType) -> OverlayBody {
        EmptyView()
    }
}

extension Poster {

    func posterAccessibility(configuration: PosterConfiguration) -> PosterAccessibility {
        PosterAccessibility(label: PosterAccessibility.joined([displayTitle, subtitle]))
    }

    func posterDisplayType(for style: UserInterfaceSizeClass) -> PosterDisplayType {
        switch style {
        case .compact:
            preferredPosterDisplayType == .square ? .square : .portrait
        default:
            preferredPosterDisplayType
        }
    }

    var subtitle: String? {
        nil
    }

    func resolveEnvironment(_: EnvironmentValues) -> Environment {
        .default
    }

    func imageSources(
        for displayType: PosterDisplayType,
        size: PosterDisplayType.Size,
        environment: Environment = .default
    ) -> [ImageSource] {
        var environment = environment

        if var imageSourceEnvironment = environment as? WithImageSourceOptions {
            imageSourceEnvironment.maxWidth = size.width(for: displayType)
            imageSourceEnvironment.quality = size.quality
            environment = imageSourceEnvironment as! Environment
        }

        return imageSources(for: displayType, environment: environment)
    }
}

@MainActor
extension View {

    @ViewBuilder
    func posterContextMenu<Item: Poster>(
        for item: Item,
        @ViewBuilder preview: @escaping (CGSize) -> some View
    ) -> some View {
        if Item.ContextMenuBody.self == EmptyView.self {
            self
        } else {
            modifier(SizedPosterContextMenuModifier(item: item, preview: preview))
        }
    }

    @ViewBuilder
    func posterContextMenu<Item: Poster>(
        for item: Item,
        @ViewBuilder preview: @escaping () -> some View
    ) -> some View {
        if Item.ContextMenuBody.self == EmptyView.self {
            self
        } else {
            contextMenu {
                item.posterContextMenu
            } preview: {
                preview()
            }
        }
    }
}

private struct SizedPosterContextMenuModifier<Item: Poster, Preview: View>: ViewModifier {

    @State
    private var size: CGSize = .zero

    let item: Item
    let preview: (CGSize) -> Preview

    func body(content: Content) -> some View {
        content
            .trackingSize($size)
            .posterContextMenu(for: item) {
                preview(size)
            }
    }
}
