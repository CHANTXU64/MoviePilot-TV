//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//
// 本文件改自 Swiftfin：Shared/Components/ChevronButton.swift
// Modifications for MoviePilot-TV are also licensed under MPL-2.0.
//
// 修改：只保留播放器用到的 `init(_:external:action:)`；去掉列表编辑状态（`isEditing` / `ListRowCheckbox`）分支；图标名改从 `AppSymbol` 取。
//

import SwiftUI

// TODO: possibly consolidate with ListRow

struct ChevronButton<Label: View>: View {

    private let action: () -> Void
    private let isExternal: Bool
    private let label: Label

    var body: some View {
        Button(action: action) {
            HStack {

                label
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: isExternal ? AppSymbol.openExternal : AppSymbol.disclosure)
                    .font(.body)
                    .fontWeight(.regular)
                    .foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(.primary, .secondary)
    }
}

extension ChevronButton {

    init(
        external: Bool = false,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) {
        self.action = action
        self.isExternal = external
        self.label = label()
    }
}

extension ChevronButton where Label == Text {

    init(
        _ title: String,
        external: Bool = false,
        action: @escaping () -> Void
    ) {
        self.init(
            external: external,
            action: action
        ) {
            Text(title)
        }
    }
}
