//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//
// 本文件改自 Swiftfin：Shared/Views/VideoPlayer/Queue/MediaQueueView.swift
// Modifications for MoviePilot-TV are also licensed under MPL-2.0.
//
// 修改：卡片上的片长经 `MediaSession.runTimeLabel(for:)` 取，正在播的那一集与进度条同一个值（所播文件的片长）。
//

import SwiftUI

@MainActor
struct MediaQueueView: @MainActor VideoPlayerSupplement {

    @Environment(VideoPlayer.ViewState.self)
    private var viewState
    @Environment(MediaSession.self)
    private var mediaSession

    let queue: any MediaPlayerQueue
    var displayType: PosterDisplayType = .landscape

    var id: String {
        "Queue-\(ObjectIdentifier(queue))"
    }

    var displayTitle: String {
        L10n.queue
    }

    @ViewBuilder
    private var itemsView: some View {
        if queue.items.isNotEmpty {
            VideoPlayer.PosterCollectionView(
                data: queue.items,
                currentElementID: queue.currentEntryID,
                isCompact: viewState.isCompact,
                displayType: displayType,
                action: queue.select
            ) { item in
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.displayTitle)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    DotHStack {
                        if let subtitle = item.subtitle {
                            Text(subtitle)
                        }

                        if let runtime = mediaSession.runTimeLabel(for: item) {
                            Text(runtime)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    var body: some View {
        switch queue.state {
        case .content:
            itemsView

        case .initial, .loading:
            EmptyView()

        case .error:
            QueueErrorView(retry: queue.refresh)
        }
    }
}
