//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//
// 本文件改自 Swiftfin：Shared/Views/VideoPlayer/Queue/QueueErrorView.swift
// Modifications for MoviePilot-TV are also licensed under MPL-2.0.
//
// 修改：tvOS 的 `PresentationView` 恒走 `largeView`；去掉 iOS 用的 `standardView`（依赖 Swiftfin 的 `ErrorView` 及主题色设置），
// 以 `largeView` 作为 `body`。
// 图标名改从 AppSymbol 取（项目统一图标来源），图标本身不变。
// 「重试」用播放界面统一的玻璃胶囊按钮；提示放在与简介面板相同的玻璃面板里（`PlayerGlassPanel`），文字在左、按钮在右。
//

import SwiftUI

@MainActor
struct QueueErrorView: View {

    let retry: () -> Void

    private var retryButton: some View {
        Button(action: retry) {
            Label(L10n.retry, systemImage: AppSymbol.retry)
        }
        .buttonStyle(.playerGlass)
        .fixedSize()
    }

    private var errorCard: some View {
        PlayerGlassPanel {
            HStack(spacing: 40) {
                Text(L10n.unknownError)
                    .font(.callout)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                retryButton
            }
            .padding(.horizontal, 20)
        }
        .padding(.top, PlayerPanelLayout.tabGap)
        .edgePadding(.horizontal)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .focusSection()
    }

    var body: some View {
        errorCard
    }
}
