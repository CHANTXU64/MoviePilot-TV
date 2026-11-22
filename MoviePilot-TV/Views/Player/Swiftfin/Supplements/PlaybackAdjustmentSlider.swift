//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//
// 本文件改自 Swiftfin：Shared/Objects/MediaPlayerManager/Supplements/Components/PlaybackAdjustmentSlider.swift
// Modifications for MoviePilot-TV are also licensed under MPL-2.0.
//
// 修改：删去 iOS 分支（系统 Slider）。
// 图标名改从 AppSymbol 取（项目统一图标来源），图标本身不变。
// 按钮和数值底换成播放界面统一的玻璃样式（`PlayerGlass.swift`）。
//

import SwiftUI

struct PlaybackAdjustmentSlider: View {

    @AdaptiveLayout
    private var viewLayout

    @Binding
    var value: Double

    let title: String
    let range: ClosedRange<Double>
    let step: Double
    let presets: [Double]
    let resetValue: Double
    let formatValue: (Double) -> String
    var focusID: String?

    private var sliderValue: Binding<Double> {
        Binding(
            get: { clamp(value, min: range.lowerBound, max: range.upperBound) },
            set: { value = clamp(round($0, toNearest: step), min: range.lowerBound, max: range.upperBound) }
        )
    }

    private var slider: some View {
        SliderContainer(
            value: Binding(
                get: { sliderValue.wrappedValue - range.lowerBound },
                set: { sliderValue.wrappedValue = $0 + range.lowerBound }
            ),
            total: range.upperBound - range.lowerBound
        )
        .sliderContainerStyle(.capsule(neutralProgress: (resetValue - range.lowerBound) / (range.upperBound - range.lowerBound)))
        .frame(height: 24)
        .ifLet(focusID) { view, id in
            view.coordinatedFocus(id)
        }
    }

    private var presetButtons: some View {
        ForEach(presets, id: \.self) { preset in
            Button {
                sliderValue.wrappedValue = preset
            } label: {
                Text(preset == resetValue ? L10n.reset : formatValue(preset))
                    .monospacedDigit()
                    .frame(minWidth: viewLayout.isLarge ? 80 : nil)
            }
            .fixedSize()
        }
    }

    var body: some View {
        VStack(spacing: viewLayout.isLarge ? 24 : 12) {
            Text(formatValue(value))
                .font(viewLayout.isLarge ? .title3.weight(.semibold) : .subheadline.weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText(value: value))
                .animation(.easeInOut(duration: 0.15), value: value)
                .padding(.horizontal, viewLayout.isLarge ? 24 : 16)
                .padding(.vertical, viewLayout.isLarge ? 12 : 8)
                .background { PlayerGlassBackground(shape: Capsule()) }

            HStack(spacing: viewLayout.isLarge ? 32 : 12) {
                Button { sliderValue.wrappedValue = value - step } label: {
                    Label(L10n.decrease, systemImage: AppSymbol.decrease)
                }
                .disabled(value <= range.lowerBound)

                VStack(spacing: viewLayout.isLarge ? 8 : 0) {
                    slider
                        .accessibilityLabel(title)
                        .accessibilityValue(formatValue(value))
                        .accessibilityAdjustableAction { direction in
                            switch direction {
                            case .increment:
                                sliderValue.wrappedValue = value + step
                            case .decrement:
                                sliderValue.wrappedValue = value - step
                            @unknown default:
                                break
                            }
                        }

                    HStack {
                        Text(formatValue(range.lowerBound))
                        Spacer(minLength: 8)
                        Text(formatValue(range.upperBound))
                    }
                    .font(viewLayout.isLarge ? .caption : .caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .accessibilityHidden(true)
                }

                Button { sliderValue.wrappedValue = value + step } label: {
                    Label(L10n.increase, systemImage: AppSymbol.increase)
                }
                .disabled(value >= range.upperBound)
            }
            .buttonStyle(.playerGlassCircle)

            FlowLayout(
                alignment: .center,
                direction: .down,
                spacing: viewLayout.isLarge ? 20 : 8,
                lineSpacing: viewLayout.isLarge ? 20 : 8
            ) {
                presetButtons
            }
            .frame(maxWidth: .infinity)
            .focusSection()
            .buttonStyle(.playerGlass)
            .padding(.top, viewLayout.isLarge ? 8 : 4)
        }
        .accessibilityElement(children: .contain)
    }
}
