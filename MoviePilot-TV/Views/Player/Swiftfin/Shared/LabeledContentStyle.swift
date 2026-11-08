//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//
// 本文件改自 Swiftfin：Shared/Extensions/LabeledContentStyle.swift
// Modifications for MoviePilot-TV are also licensed under MPL-2.0.
//
// 修改：只保留播放器用到的 `playbackInfo` 样式。
//

import SwiftUI

extension LabeledContentStyle where Self == PlaybackInfoLabeledContentStyle {

    static var playbackInfo: PlaybackInfoLabeledContentStyle {
        PlaybackInfoLabeledContentStyle()
    }
}

struct PlaybackInfoLabeledContentStyle: LabeledContentStyle {

    @AdaptiveLayout
    private var viewLayout

    @FocusState
    private var isFocused: Bool

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 0) {
            configuration.label
                .foregroundStyle(.secondary)

            // swiftlint:disable:next hard_coded_display_string
            Text(":")
                .foregroundStyle(.secondary)
                .padding(.trailing, 4)

            Spacer()

            configuration.content
                .foregroundStyle(.primary)
        }
        .font(.subheadline)
        .if(viewLayout.isLarge) { label in
            label
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isFocused ? Color.white.opacity(0.15) : Color.clear)
                )
                .focusable()
                .focused($isFocused)
                .animation(.easeInOut(duration: 0.15), value: isFocused)
        }
    }
}
