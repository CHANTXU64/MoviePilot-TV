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
// 修改：选集卡用 App 的剧照卡（`StillCard`）：第几季第几集写在剧照左下角，下面是集名；不显示片长。
//

import SwiftUI

@MainActor
struct MediaQueueView: @MainActor VideoPlayerSupplement {

    let queue: any MediaPlayerQueue

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
                badge: \.subtitle,
                title: \.displayTitle,
                action: queue.select
            )
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
