//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//
// 本文件改自 Swiftfin：Shared/Objects/MediaPlayerManager/Supplements/MediaChaptersSupplement.swift
// Modifications for MoviePilot-TV are also licensed under MPL-2.0.
//
// 修改：去掉 `import JellyfinAPI`；Jellyfin 类型换成 MoviePilot-TV 的同名 Emby 适配类型（见 Views/Player/SwiftfinPlayerModels.swift）。
// Swift 6 下对 `VideoPlayerSupplement` 的一致性标为 `@MainActor`（与原版 MediaQueueView.swift 的写法相同）。
//

import SwiftUI

@MainActor
struct MediaChaptersSupplement {

    let displayTitle: String = L10n.chapters
    let id: String
    let chapters: [ChapterInfo.FullInfo]

    func chapterID(at seconds: Duration) -> ChapterInfo.FullInfo.ID? {
        let started = chapters.split(after: seconds, sortedBy: \.startSeconds).atOrBefore
        return (started.last ?? chapters.first)?.id
    }

    func nextChapterStart(after seconds: Duration) -> Duration? {
        chapters.split(after: seconds, sortedBy: \.startSeconds).after.first?.startSeconds
    }

    func previousChapterStart(before seconds: Duration) -> Duration? {
        let started = chapters.split(after: seconds, sortedBy: \.startSeconds).atOrBefore
        guard let current = started.last else { return chapters.first?.startSeconds }

        // Restart the current chapter once playback is more than three seconds into it.
        if seconds - current.startSeconds > .seconds(3) {
            return current.startSeconds
        }

        return started.dropLast().last?.startSeconds ?? current.startSeconds
    }
}

extension MediaChaptersSupplement: @MainActor VideoPlayerSupplement {

    var body: some View {
        ChapterOverlay(supplement: self)
    }

    private struct ChapterOverlay: View {

        @Environment(VideoPlayer.ViewState.self)
        private var viewState
        @Environment(MediaSession.self)
        private var mediaSession

        var supplement: MediaChaptersSupplement

        private func select(chapter: ChapterInfo.FullInfo) {
            guard let startSeconds = chapter.chapterInfo.startSeconds else { return }

            mediaSession.seek(to: startSeconds)
            mediaSession.setPlaybackRequestStatus(status: .playing)
        }

        var body: some View {
            VideoPlayer.PosterCollectionView(
                data: supplement.chapters,
                currentElementID: supplement.chapterID(at: mediaSession.seconds),
                isCompact: viewState.isCompact,
                action: select
            )
        }
    }
}
