//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//
// 本文件改自 Swiftfin：Swiftfin tvOS/Components/SliderContainer/SliderInteractionModifier.swift
// Modifications for MoviePilot-TV are also licensed under MPL-2.0.
//
// 修改：Swiftfin 的 `PlatformViewRepresentable` 来自第三方 Engine 包，换成 `UIViewRepresentable`；
// 工程里已有名为 `Context` 的模型类型，representable 的上下文写成 `UIViewRepresentableContext<Self>`。
//

import SwiftUI

struct SliderInteractionModifier<Value: BinaryFloatingPoint>: ViewModifier {

    let value: Binding<Value>
    let total: Value
    let isScrollingEnabled: Bool
    let onEditingChanged: (Bool) -> Void
    let onFocusChanged: (Bool) -> Void

    func body(content: Content) -> some View {
        SliderContainerRepresentable(
            value: value,
            total: total,
            isScrollingEnabled: isScrollingEnabled,
            onEditingChanged: onEditingChanged,
            onFocusChanged: onFocusChanged
        )
        .overlay {
            content
                .allowsHitTesting(false)
        }
    }
}

private struct SliderContainerRepresentable<Value: BinaryFloatingPoint>: UIViewRepresentable {

    let value: Binding<Value>
    let total: Value
    let isScrollingEnabled: Bool
    let onEditingChanged: (Bool) -> Void
    let onFocusChanged: (Bool) -> Void

    func makeUIView(context: UIViewRepresentableContext<Self>) -> UISliderContainer<Value> {
        UISliderContainer(
            value: value,
            total: total,
            isScrollingEnabled: isScrollingEnabled,
            onEditingChanged: onEditingChanged,
            onFocusChanged: onFocusChanged
        )
    }

    static func dismantleUIView(_ uiView: UISliderContainer<Value>, coordinator: ()) {
        uiView.stopDecelerating()
    }

    func updateUIView(_ uiView: UISliderContainer<Value>, context: UIViewRepresentableContext<Self>) {
        uiView.update(
            value: value,
            total: total,
            isScrollingEnabled: isScrollingEnabled,
            onEditingChanged: onEditingChanged,
            onFocusChanged: onFocusChanged
        )
    }
}
