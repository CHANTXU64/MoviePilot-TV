//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//
// 本文件改自 Swiftfin：Shared/Extensions/ViewExtensions/ViewExtensions.swift、
// Shared/Extensions/ViewExtensions/Modifiers/OnSizeChangedModifier.swift、
// Shared/Extensions/ViewExtensions/Modifiers/TrackingFrameModifier.swift、Shared/Extensions/Binding.swift、
// Shared/Objects/RectangleCorner.swift、Shared/Objects/Direction.swift（只保留播放器用到的成员）。
// 工程已有同名的 `if(_:transform:)` 扩展（Extensions/Formatters.swift），原版的 `if` 不再重复定义，`cornerRadius` 的 `container` 参数改用 `if let`。
// Modifications for MoviePilot-TV are also licensed under MPL-2.0.
//
// 修改：只保留播放器用到的成员；`RectangleCorner`、`Direction` 原用 `@OptionSet` 宏生成，这里手写等价的 OptionSet。
//

import SwiftUI

extension View {

    var backport: Backport<Self> {
        Backport(content: self)
    }

    func copy<Value>(modifying keyPath: WritableKeyPath<Self, Value>, with newValue: Value) -> Self {
        var copy = self
        copy[keyPath: keyPath] = newValue

        return copy
    }

    @ViewBuilder
    func cornerRadius(
        _ radius: CGFloat,
        corners: RectangleCorner = .all,
        style: RoundedCornerStyle = .circular,
        container: Bool = false
    ) -> some View {
        // Note: UnevenRoundedRectangle with all equal radii has
        // been found to perform worse than RoundedRectangle
        if corners == .all {
            let shape = RoundedRectangle(cornerRadius: radius, style: style)

            clipShape(shape)
                .if(container) { $0.containerShape(shape) }
        } else {
            let shape = UnevenRoundedRectangle(
                topLeadingRadius: corners.contains(.topLeft) ? radius : 0,
                bottomLeadingRadius: corners.contains(.bottomLeft) ? radius : 0,
                bottomTrailingRadius: corners.contains(.bottomRight) ? radius : 0,
                topTrailingRadius: corners.contains(.topRight) ? radius : 0,
                style: style
            )

            clipShape(shape)
                .if(container) { $0.containerShape(shape) }
        }
    }

    /// Apply a corner radius as a ratio of a view's side
    func cornerRadius(
        ratio: CGFloat,
        of side: KeyPath<CGSize, CGFloat>,
        corners: RectangleCorner = .all,
        style: RoundedCornerStyle = .circular
    ) -> some View {
        modifier(
            OnSizeChangedModifier { size in
                let radius = size[keyPath: side] * ratio
                self.cornerRadius(radius, corners: corners, style: style, container: true)
            }
        )
    }

    /// - Important: Do *not* use this modifier for dynamically showing/hiding views.
    ///              Instead, use a native `if let/else` statement.
    @ViewBuilder
    func ifLet<Value>(
        _ value: Value?,
        @ViewBuilder transform: (Self, Value) -> some View
    ) -> some View {
        if let value {
            transform(self, value)
        } else {
            self
        }
    }

    // TODO: rename `invertedMask`?
    func inverseMask(alignment: Alignment = .center, @ViewBuilder _ content: @escaping () -> some View) -> some View {
        mask(alignment: alignment) {
            content()
                .foregroundStyle(.black)
                .background(.white)
                .compositingGroup()
                .luminanceToAlpha()
        }
    }

    func isSelected(_ isSelected: Bool) -> some View {
        environment(\.isSelected, isSelected)
    }

    func onFirstAppear(perform action: @escaping () -> Void) -> some View {
        modifier(OnFirstAppearModifier(action: action))
    }

    @ViewBuilder
    func posterAspectRatio(
        _ type: PosterDisplayType,
        contentMode: ContentMode = .fill
    ) -> some View {
        switch type {
        case .landscape:
            aspectRatio(1.77, contentMode: contentMode)
        case .portrait:
            aspectRatio(2 / 3, contentMode: contentMode)
        case .square:
            aspectRatio(1.0, contentMode: contentMode)
        }
    }

    func posterBorder() -> some View {
        overlay {
            ContainerRelativeShape()
                .stroke(
                    .white.opacity(0.1),
                    lineWidth: 1
                )
                .clipped()
        }
    }

    @ViewBuilder
    func posterCornerRadius(
        _ type: PosterDisplayType
    ) -> some View {
        switch type {
        case .landscape:
            cornerRadius(ratio: 1 / 30, of: \.width)
        case .portrait, .square:
            cornerRadius(ratio: 0.0375, of: \.width)
        }
    }

    func posterStyle(
        _ type: PosterDisplayType,
        contentMode: ContentMode = .fill
    ) -> some View {
        modifier(PosterStyleModifier(type: type, contentMode: contentMode))
    }

    func scrollIfLargerThanContainer(axes: Axis.Set = .vertical, padding: CGFloat = 0, alignment: Alignment = .center) -> some View {
        modifier(ScrollIfLargerThanContainerModifier(axes: axes, padding: padding, alignment: alignment))
    }

    func edgePadding(_ edges: Edge.Set = .all) -> some View {
        modifier(EdgePaddingModifier(edges: edges))
    }

    /// Error Message Alert
    func errorMessage(
        _ error: Binding<Error?>,
        dismissAction: @escaping () -> Void = {}
    ) -> some View {
        alert(
            Text(L10n.error),
            isPresented: .constant(error.wrappedValue != nil),
            presenting: error.wrappedValue
        ) { _ in
            Button(L10n.dismiss, role: .cancel) {
                error.wrappedValue = nil
                dismissAction()
            }
        } message: { error in
            Text(error.localizedDescription)
        }
        .onChange(of: error.wrappedValue != nil) {
            guard error.wrappedValue != nil else { return }

            UIDevice.feedback(.error)
        }
    }

    @inlinable
    func enabled(_ enabled: Bool) -> some View {
        disabled(!enabled)
    }

    @inlinable
    func eraseToAnyView() -> AnyView {
        AnyView(self)
    }

    func isVisible(_ isVisible: Bool) -> some View {
        opacity(isVisible ? 1 : 0)
    }

    func subtleShadow() -> some View {
        shadow(radius: 4, y: 2)
    }
}

// MARK: - OnSizeChangedModifier / TrackingFrameModifier

struct OnSizeChangedModifier<Wrapped: View>: ViewModifier {

    @State
    private var size: CGSize = .zero

    @ViewBuilder
    var wrapped: (CGSize) -> Wrapped

    func body(content: Content) -> some View {
        wrapped(size)
            .onSizeChanged { newSize, _ in
                size = newSize
            }
    }
}

private nonisolated struct SizeAndSafeAreaInsets: Equatable {

    let size: CGSize
    let safeAreaInsets: EdgeInsets
}

extension View {

    func onSizeChanged(
        perform action: @escaping (CGSize, EdgeInsets) -> Void
    ) -> some View {
        onGeometryChange(for: SizeAndSafeAreaInsets.self) { proxy in
            .init(
                size: proxy.size,
                safeAreaInsets: proxy.safeAreaInsets
            )
        } action: { newValue in
            action(newValue.size, newValue.safeAreaInsets)
        }
    }

    func trackingSize(
        _ sizeBinding: Binding<CGSize>,
        _ safeAreaInsetBinding: Binding<EdgeInsets> = .constant(.zero)
    ) -> some View {
        onSizeChanged {
            sizeBinding.wrappedValue = $0
            safeAreaInsetBinding.wrappedValue = $1
        }
    }
}

// MARK: - Binding

extension Binding {

    func map<V>(getter: @escaping (Value) -> V, setter: @escaping (V) -> Value) -> Binding<V> {
        Binding<V>(
            get: { getter(wrappedValue) },
            set: { wrappedValue = setter($0) }
        )
    }
}

// MARK: - RectangleCorner

// Swiftfin 用 `@OptionSet` 宏生成这些成员，这里手写等价的 OptionSet。
nonisolated struct RectangleCorner: OptionSet {

    let rawValue: Int

    static let topLeft = RectangleCorner(rawValue: 1 << 0)
    static let topRight = RectangleCorner(rawValue: 1 << 1)
    static let bottomLeft = RectangleCorner(rawValue: 1 << 2)
    static let bottomRight = RectangleCorner(rawValue: 1 << 3)

    static var all: Self {
        [.topLeft, .topRight, .bottomLeft, .bottomRight]
    }
}

// MARK: - Direction

// Swiftfin 用 `@OptionSet` 宏生成这些成员，这里手写等价的 OptionSet。
nonisolated struct Direction: OptionSet {

    let rawValue: Int

    static let up = Direction(rawValue: 1 << 0)
    static let down = Direction(rawValue: 1 << 1)
    static let left = Direction(rawValue: 1 << 2)
    static let right = Direction(rawValue: 1 << 3)

    static var vertical: Self {
        [.up, .down]
    }

    static var horizontal: Self {
        [.left, .right]
    }

    static var all: Self {
        [.up, .down, .left, .right]
    }

    static var allButDown: Self {
        [.up, .left, .right]
    }

    var isHorizontal: Bool {
        contains(.left) || contains(.right)
    }

    var isVertical: Bool {
        contains(.up) || contains(.down)
    }
}
