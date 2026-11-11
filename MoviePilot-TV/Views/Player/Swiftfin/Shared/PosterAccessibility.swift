//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//
// 本文件改自 Swiftfin：Shared/Objects/Poster/PosterAccessibility.swift
// Modifications for MoviePilot-TV are also licensed under MPL-2.0.
//
// 修改：补上原版定义在 Shared/Extensions/EnvironmentValues.swift 的 `isSelected`、`posterConfiguration`、`posterDisplayType` 环境值，
// 以及 Shared/Objects/PosterConfiguration.swift 的 `PosterConfiguration`（播放器只用默认值，去掉其设置项字段与存储宏）。
//

import Foundation
import SwiftUI

nonisolated struct PosterAccessibility {

    let label: String
    let value: String

    init(label: String, value: String = "") {
        let label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        self.label = label.isEmpty ? L10n.unknown : label
        self.value = value
    }

    static func joined(_ components: [String?]) -> String {
        var values: [String] = []
        for component in components {
            guard let component = component?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !component.isEmpty,
                  !values.contains(component)
            else { continue }

            values.append(component)
        }
        return values.joined(separator: ", ")
    }

    static func duration(_ duration: Duration) -> String {
        duration.formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
    }
}

private struct PosterAccessibilityModifier<Item: Poster>: ViewModifier {

    @Environment(\.posterConfiguration)
    private var posterConfiguration

    @Environment(\.isSelected)
    private var isSelected

    let item: Item

    func body(content: Content) -> some View {
        let description = item.posterAccessibility(configuration: posterConfiguration)

        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(description.label)
            .accessibilityValue(description.value)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

extension View {

    /// For buttons, apply to the label to preserve native button actions and traits.
    func posterAccessibility(for item: some Poster) -> some View {
        modifier(PosterAccessibilityModifier(item: item))
    }
}

// MARK: - 原 Shared/Objects/PosterConfiguration.swift

nonisolated struct PosterConfiguration: Hashable, WithDefaultValue {

    nonisolated enum PosterSubtitleField: Hashable {
        case none
    }

    var isTitlePresented: Bool = true
    var subtitleField: PosterSubtitleField = .none

    static let `default` = PosterConfiguration()
}

// MARK: - 原 Shared/Extensions/EnvironmentValues.swift

private nonisolated struct IsSelectedKey: EnvironmentKey {

    static let defaultValue = false
}

private nonisolated struct PosterConfigurationKey: EnvironmentKey {

    static let defaultValue: PosterConfiguration = .default
}

private nonisolated struct PosterDisplayTypeKey: EnvironmentKey {

    static let defaultValue: PosterDisplayType = .portrait
}

extension EnvironmentValues {

    nonisolated var isSelected: Bool {
        get { self[IsSelectedKey.self] }
        set { self[IsSelectedKey.self] = newValue }
    }

    nonisolated var posterConfiguration: PosterConfiguration {
        get { self[PosterConfigurationKey.self] }
        set { self[PosterConfigurationKey.self] = newValue }
    }

    nonisolated var posterDisplayType: PosterDisplayType {
        get { self[PosterDisplayTypeKey.self] }
        set { self[PosterDisplayTypeKey.self] = newValue }
    }
}
