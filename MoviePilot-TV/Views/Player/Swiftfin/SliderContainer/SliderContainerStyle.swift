//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//
// 本文件改自 Swiftfin：Shared/Components/SliderContainer/SliderContainerStyle.swift
// Modifications for MoviePilot-TV are also licensed under MPL-2.0.
//
// 修改：Swiftfin 的 `ViewStyle` / `ViewStyledView` / `styledViewStyle` 来自第三方 Engine 包，
// 这里用环境值保存类型擦除后的样式，行为相同：未设置样式时用 `defaultStyle`。
//

import SwiftUI

protocol SliderContainerStyle {

    associatedtype Body: View

    @ViewBuilder
    @MainActor
    func makeBody(configuration: SliderContainerStyleConfiguration) -> Body
}

/// A snapshot of the slider's interaction state.
///
/// - Note: Styles use `Double` regardless of the binding's numeric type.
struct SliderContainerStyleConfiguration {

    let isEditing: Bool
    let isFocused: Bool
    let isScrollingEnabled: Bool
    let value: Double
    let originValue: Double?
    let total: Double

    var progress: Double {
        progress(for: value)
    }

    var originProgress: Double? {
        originValue.map(progress(for:))
    }

    private func progress(for value: Double) -> Double {
        guard total.isFinite, total > 0, value.isFinite else { return 0 }

        return clamp(value / total, min: 0, max: 1)
    }
}

struct SliderContainerBody: View {

    @Environment(\.sliderContainerStyle)
    private var style

    let configuration: SliderContainerStyleConfiguration

    static var defaultStyle: CapsuleSliderStyle {
        CapsuleSliderStyle()
    }

    var body: some View {
        if let style {
            style.makeBody(configuration)
        } else {
            Self.defaultStyle.makeBody(configuration: configuration)
        }
    }
}

struct AnySliderContainerStyle {

    let makeBody: @MainActor (SliderContainerStyleConfiguration) -> AnyView

    init(_ style: some SliderContainerStyle) {
        makeBody = { AnyView(style.makeBody(configuration: $0)) }
    }
}

private struct SliderContainerStyleKey: EnvironmentKey {

    static let defaultValue: AnySliderContainerStyle? = nil
}

extension EnvironmentValues {

    var sliderContainerStyle: AnySliderContainerStyle? {
        get { self[SliderContainerStyleKey.self] }
        set { self[SliderContainerStyleKey.self] = newValue }
    }
}

extension View {

    func sliderContainerStyle(_ style: some SliderContainerStyle) -> some View {
        environment(\.sliderContainerStyle, AnySliderContainerStyle(style))
    }
}
