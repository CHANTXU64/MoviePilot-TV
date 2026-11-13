//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//
// 本文件改自 Swiftfin：Shared/Views/VideoPlayer/VideoPlayerSupplement.swift
// Modifications for MoviePilot-TV are also licensed under MPL-2.0.
//
// 修改：去掉 `import JellyfinAPI`；条目、章节、演职员来自 MoviePilot-TV 的 Emby 适配类型（同名）。
// 章节不在条目上，由调用方传入 `MediaSession.chapters`；mpv 还在读文件时也显示「章节」（转圈）。
//

import SwiftUI

enum VideoPlayerSupplementPresentationStyle: Equatable {

    case regular
    case expanded
}

@MainActor
protocol VideoPlayerSupplement: Displayable, Identifiable, View {

    var id: String { get }

    var presentationStyle: VideoPlayerSupplementPresentationStyle { get }
    var preferredFocusID: String { get }
}

extension VideoPlayerSupplement {

    var presentationStyle: VideoPlayerSupplementPresentationStyle {
        .regular
    }

    var preferredFocusID: String {
        VideoPlayer.ViewState.Focus.supplementContent(id)
    }
}

@MainActor
extension VideoPlayerSupplementType {

    func makeSupplement(
        for item: MediaPlayerItem,
        queue: any MediaPlayerQueue?,
        chapters: PlaybackChapterList
    ) -> (any VideoPlayerSupplement)? {
        switch self {
        case .info:
            return MediaInfoSupplement(item: item.baseItem)

        case .chapters:
            guard chapters.isShown else { return nil }

            return MediaChaptersSupplement(
                id: "Chapters-\(item.baseItem.id ?? "any")",
                chapters: chapters.loaded,
                isLoading: chapters.isLoading
            )

        case .queue:
            guard let queue else { return nil }

            return MediaQueueView(queue: queue)

        case .people:
            guard let people = item.baseItem.mergedPeople?.filter({ $0.type?.isSupported == true }), people.isNotEmpty else { return nil }

            return MediaPeopleSupplement(people: people)

        case .playbackInformation:
            return item.baseItem.id.map { PlaybackInfoSupplement(itemID: $0) }
        }
    }
}
