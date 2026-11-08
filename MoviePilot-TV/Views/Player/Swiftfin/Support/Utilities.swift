//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//
// 本文件改自 Swiftfin：Shared/Objects/Utilities.swift、Shared/Extensions/Comparable.swift、
// Shared/Extensions/Collection.swift、Shared/Extensions/Task.swift、Shared/Extensions/String.swift、
// Shared/Extensions/Color.swift、Shared/Extensions/UIColor.swift、Shared/Extensions/UIDevice.swift、Shared/Extensions/EdgeInsets.swift、
// Shared/Extensions/Duration.swift、Shared/Extensions/CGSize.swift、Shared/Extensions/Sequence.swift、Shared/Extensions/Array.swift、Shared/Extensions/UIImage.swift
// （只保留播放器用到的成员）。`split(after:sortedBy:)` 原版用 swift-algorithms 的 `partitioningIndex`，这里写成等价的二分查找。
// Modifications for MoviePilot-TV are also licensed under MPL-2.0.
//
// 修改：只保留播放器用到的成员，并标为 `nonisolated`；tvOS 专用的触感反馈占位类型一并放在这里。
//

import Combine
import SwiftUI
import UIKit

@inlinable
nonisolated func clamp<T: Comparable>(_ x: T, min y: T, max z: T) -> T {
    min(max(x, y), z)
}

@inlinable
nonisolated func copy<P, Value>(_ p: P, modifying keyPath: WritableKeyPath<P, Value>, to newValue: Value) -> P {
    var copy = p
    copy[keyPath: keyPath] = newValue

    return copy
}

@inlinable
nonisolated func round<T: BinaryFloatingPoint>(_ value: T, toNearest: T) -> T {
    round(value / toNearest) * toNearest
}

@inlinable
nonisolated func with<V>(_ value: V, modify: @escaping (inout V) throws -> Void) rethrows -> V {
    var value = value
    try modify(&value)

    return value
}

extension Comparable {

    nonisolated func clamped(to range: ClosedRange<Self>) -> Self {
        clamp(self, min: range.lowerBound, max: range.upperBound)
    }
}

extension Collection {

    nonisolated var isNotEmpty: Bool {
        !isEmpty
    }

    nonisolated subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }

    /// Splits a collection sorted by ascending key into elements at or before the value and those after it.
    nonisolated func split<Value: Comparable>(
        after value: Value,
        sortedBy key: (Element) -> Value
    ) -> (atOrBefore: SubSequence, after: SubSequence) {
        var low = startIndex
        var count = distance(from: startIndex, to: endIndex)

        while count > 0 {
            let half = count / 2
            let middle = index(low, offsetBy: half)

            if key(self[middle]) > value {
                count = half
            } else {
                low = index(after: middle)
                count -= half + 1
            }
        }

        return (self[..<low], self[low...])
    }
}

extension Sequence {

    nonisolated func compacted(using keyPath: KeyPath<Element, some Any?>) -> [Element] {
        filter { $0[keyPath: keyPath] != nil }
    }

    nonisolated func first<V: Equatable>(property: (Element) -> V, equalTo value: V) -> Element? {
        first { property($0) == value }
    }
}

extension Array {

    @discardableResult
    nonisolated mutating func removeFirstSafe() -> Element? {
        guard count > 0 else { return nil }

        return removeFirst()
    }
}

extension Array where Element: Equatable {

    nonisolated mutating func removeAll(equalTo element: Element) {
        removeAll { $0 == element }
    }
}

extension Sequence where Element: Equatable {

    nonisolated func subtracting(_ other: some Sequence<Element>) -> [Element] {
        filter { !other.contains($0) }
    }
}

extension UIImage {

    func getTileImage(index: Int, columns: Int, tileSize: CGSize) -> UIImage? {
        guard index >= 0, columns > 0, let cgImage else { return nil }

        // CGImage crops in pixels, while UIImage.size is measured in points.
        let rect = CGRect(
            x: CGFloat(index % columns) * tileSize.width,
            y: CGFloat(index / columns) * tileSize.height,
            width: tileSize.width,
            height: tileSize.height
        )

        guard !rect.isEmpty,
              CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height).contains(rect),
              let tile = cgImage.cropping(to: rect)
        else { return nil }

        return UIImage(cgImage: tile, scale: scale, orientation: imageOrientation)
    }
}

extension Task {

    nonisolated func asAnyCancellable() -> AnyCancellable {
        AnyCancellable(cancel)
    }
}

extension String {

    /// "--:--"
    nonisolated static let emptyRuntime = "--:--"
    /// ""
    nonisolated static let empty = ""
    /// "×"
    nonisolated static let multiply = "\u{00D7}"
    /// "--"
    nonisolated static let emptyDash = "--"
    /// " "
    nonisolated static let space = " "
    /// "-"
    nonisolated static let hyphen = "\u{002D}"

    nonisolated func multiply(by value: String) -> String {
        "\(self) \(Self.multiply) \(value)"
    }

    nonisolated var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension Duration {

    /// Represent Jellyfin ticks as a Duration
    nonisolated static func ticks(_ ticks: Int) -> Duration {
        Duration.microseconds(Int64(ticks) / 10)
    }

    nonisolated var microseconds: Int64 {
        (components.attoseconds / 1_000_000_000_000) + components.seconds * 1_000_000
    }

    nonisolated var seconds: Double {
        Double(components.seconds) + Double(components.attoseconds) * 1e-18
    }
}

extension CGSize {

    nonisolated var aspectRatio: CGFloat? {
        guard width > 0, height > 0,
              width.isFinite, height.isFinite
        else { return nil }

        let ratio = width / height
        return ratio > 0 && ratio.isFinite ? ratio : nil
    }
}

extension EdgeInsets {

    nonisolated init(_ constant: CGFloat) {
        self.init(top: constant, leading: constant, bottom: constant, trailing: constant)
    }

    nonisolated init(vertical: CGFloat = 0, horizontal: CGFloat = 0) {
        self.init(top: vertical, leading: horizontal, bottom: vertical, trailing: horizontal)
    }

    nonisolated static let zero: EdgeInsets = .init()

    nonisolated func max(_ value: CGFloat) -> EdgeInsets {
        EdgeInsets(
            top: Swift.max(top, value),
            leading: Swift.max(leading, value),
            bottom: Swift.max(bottom, value),
            trailing: Swift.max(trailing, value)
        )
    }
}

extension Color {

    nonisolated static let jellyfinPurple = Color(red: 172 / 255, green: 92 / 255, blue: 195 / 255, opacity: 1)

    var uiColor: UIColor {
        UIColor(self)
    }

    var overlayColor: Color {
        Color(uiColor: uiColor.overlayColor)
    }

    nonisolated static let systemFill = Color.white
    nonisolated static let secondarySystemFill = Color.gray
    nonisolated static let tertiarySystemFill = Color.black
    nonisolated static let lightGray = Color(UIColor.lightGray)
}

extension UIColor {

    var overlayColor: UIColor {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        let brightness = ((red * 299) + (green * 587) + (blue * 114)) / 1000

        return brightness < 0.5 ? .white : .black
    }
}

extension UIDevice {

    static func feedback(_ type: UINotificationFeedbackGenerator.FeedbackType) {}

    static func impact(_ type: UIImpactFeedbackGenerator.FeedbackStyle) {}

    nonisolated static let supportsLiquidGlass: Bool = {
        // MoviePilot-TV 部署到 tvOS 18：tvOS 26 之前没有 Liquid Glass。
        guard #available(tvOS 26.0, *) else { return false }

        var systemInfo = utsname()
        uname(&systemInfo)
        let model = withUnsafeBytes(of: systemInfo.machine) { buffer in
            String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
        }
        /// Apple TV HD and Apple TV 4K (1st gen) run tvOS 26 without Liquid Glass
        /// - https://support.apple.com/en-us/106336
        /// - See tvOS 26, footnote 2
        return !["AppleTV5,3", "AppleTV6,2"].contains(model)
    }()
}

enum UIImpactFeedbackGenerator {
    enum FeedbackStyle {
        case light
        case medium
        case heavy
    }
}

enum UINotificationFeedbackGenerator {
    enum FeedbackType {
        case success
        case warning
        case error
    }
}
