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
//

import SwiftUI

@MainActor
struct QueueErrorView: View {

    @AdaptiveLayout
    private var viewLayout

    @Environment(VideoPlayer.ViewState.self)
    private var viewState

    let retry: () -> Void

    private var retryButton: some View {
        AlternateLayoutView {
            Label(L10n.retry, systemImage: AppSymbol.retry)
                .font(.subheadline)
                .fontWeight(.semibold)
                .padding()
                .edgePadding(.horizontal)
                .frame(height: viewLayout.isLarge ? 80 : 40)
        } content: {
            Button(action: retry) {
                Label(L10n.retry, systemImage: AppSymbol.retry)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .padding()
                    .edgePadding(.horizontal)
            }
            .buttonStyle(.supplementAction)
            .frame(height: viewLayout.isLarge ? 80 : 50)
        }
    }

    private var errorCard: some View {
        VStack(alignment: .leading, spacing: viewLayout.edgePadding / 2) {
            Text(L10n.unknownError)
                .font(.callout)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .frame(maxHeight: .infinity, alignment: .topLeading)

            retryButton
        }
        .edgePadding(.horizontal)
        .padding(.vertical, viewLayout.edgePadding / 2)
        .background {
            RoundedRectangle(cornerRadius: 32)
                .fill(Material.thin)
        }
        .clipShape(RoundedRectangle(cornerRadius: 32))
        .edgePadding()
        .focusSection()
    }

    var body: some View {
        errorCard
    }
}
