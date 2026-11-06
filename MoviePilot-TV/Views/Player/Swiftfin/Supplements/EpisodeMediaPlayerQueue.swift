//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//
// 本文件改自 Swiftfin：Shared/Objects/MediaPlayerManager/Supplements/EpisodeMediaPlayerQueue.swift
// Modifications for MoviePilot-TV are also licensed under MPL-2.0.
//
// 修改：
// - 去掉 `Defaults`、`JellyfinAPI`；条目换成 MoviePilot-TV 的同名 Emby 适配类型。
// - 同季分集列表不用 Swiftfin 的分页库（`PagingLibraryViewModel<EpisodeLibrary>`），由接入点
//   `UserSession.seasonEpisodes(seriesID:seasonID:)` 一次取完，状态映射与原版相同；相邻集由接入点
//   `UserSession.adjacentEpisodes(seriesID:itemID:)` 提供（原版为 Jellyfin `getEpisodes(adjacentTo:limit: 3)`），
//   之后的“四种情况”判断与原版相同。两个接入点尚未接数据（返回空），条目也不带 `seriesID` / `seasonID`，
//   所以目前队列为空、没有上一集/下一集，自动播放不会接着播。
// - 码率设置 `appMaximumBitrate` 换成 `VideoPlayerDefaults.appMaximumBitrate`。
// - 析构显式标为 `nonisolated`（tvOS 18.4–26.2 上，隔离析构在主线程、Task 之外执行会崩溃）。
//

import Combine
import Foundation
import Observation

@MainActor
@Observable
final class EpisodeMediaPlayerQueue: MediaPlayerQueue {

    // 显式非隔离析构，避开 tvOS 18 的隔离析构回部署崩溃。
    nonisolated deinit {}

    private weak var mediaSession: MediaSession?
    private(set) var state: MediaPlayerQueueState = .initial
    private(set) var items: [ItemEntry] = []
    var nextItem: PlaybackIntent?
    var previousItem: PlaybackIntent?

    var currentEntryID: ItemEntry.ID? {
        mediaSession?.item.id.map { ItemEntry.ID(itemID: $0, occurrence: nil) }
    }

    @ObservationIgnored
    private var currentAdjacentEpisodesTask: AnyCancellable?

    @ObservationIgnored
    private var seasonID: String?
    @ObservationIgnored
    private var seasonSeriesID: String?
    @ObservationIgnored
    private var seasonTask: AnyCancellable?

    func observe(_ mediaSession: MediaSession) -> AnyCancellable {
        self.mediaSession = mediaSession

        let observation = ObservationToken { [weak mediaSession] in
            mediaSession?.playbackItem
        } onChange: { [weak self] item in
            self?.didReceive(newItem: item)
        }

        return AnyCancellable { [self, observation] in
            MainActor.assumeIsolated {
                observation.cancel()
                didReceive(newItem: nil)
                resetSeason()
                self.mediaSession = nil
            }
        }
    }

    private func didReceive(newItem: MediaPlayerItem?) {
        currentAdjacentEpisodesTask = nil
        nextItem = nil
        previousItem = nil

        guard let newItem else { return }

        updateSeason(for: newItem.baseItem)

        currentAdjacentEpisodesTask = Task { [weak self] in
            try await self?.getAdjacentEpisodes(for: newItem.baseItem)
        }
        .asAnyCancellable()
    }

    func refresh() {
        guard let seasonID, let seasonSeriesID, let session = mediaSession?.userSession else { return }

        state = .loading

        seasonTask = Task { [weak self] in
            do {
                let episodes = try await session.seasonEpisodes(seriesID: seasonSeriesID, seasonID: seasonID)
                guard !Task.isCancelled, let self, self.seasonID == seasonID else { return }

                items = episodes.map { ItemEntry(item: $0) }
                state = .content
            } catch {
                guard !Task.isCancelled, let self, self.seasonID == seasonID else { return }

                state = .error
            }
        }
        .asAnyCancellable()
    }

    func select(_ entry: ItemEntry) {
        guard let mediaSession else { return }

        let configuration = with(MediaPlaybackConfiguration()) {
            $0.requestedBitrate = mediaSession.playbackBitrate
        }
        mediaSession.playNewItem(intent: PlaybackIntent(item: entry.snapshot, configuration: configuration))
    }

    private func updateSeason(for item: BaseItemDto) {
        guard item.type == .episode, let seasonID = item.seasonID?.nilIfBlank, mediaSession != nil else {
            resetSeason()
            return
        }

        // Keep the list and its loading work when playback moves within the same season.
        guard self.seasonID != seasonID else { return }

        resetSeason()

        self.seasonID = seasonID
        self.seasonSeriesID = item.seriesID

        refresh()
    }

    private func resetSeason() {
        seasonTask = nil
        seasonID = nil
        seasonSeriesID = nil
        items = []
        state = .initial
    }

    private func getAdjacentEpisodes(for item: BaseItemDto?) async throws {
        guard let item, let seriesID = item.seriesID, item.type == .episode else { return }
        guard let session = mediaSession?.userSession else {
            throw UserSessionError.missingCurrentSession
        }

        let response = try await session.adjacentEpisodes(seriesID: seriesID, itemID: item.id!)

        // 4 possible states:
        //  1 - only current episode
        //  2 - two episodes with next episode
        //  3 - two episodes with previous episode
        //  4 - three episodes with current in middle

        // 1
        let items = response
        guard items.count > 1 else { return }

        var previousItem: BaseItemDto?
        var nextItem: BaseItemDto?

        if items.count == 2 {
            if items[0].id == item.id {
                // 2
                nextItem = items[1]

            } else {
                // 3
                previousItem = items[0]
            }
        } else {
            nextItem = items[2]
            previousItem = items[0]
        }

        let bitrate = mediaSession?.playbackBitrate ?? VideoPlayerDefaults.appMaximumBitrate

        let configuration = with(MediaPlaybackConfiguration()) {
            $0.requestedBitrate = bitrate
            $0.startSeconds = .zero
        }
        let nextIntent = nextItem.map { PlaybackIntent(item: $0, configuration: configuration) }
        let previousIntent = previousItem.map { PlaybackIntent(item: $0, configuration: configuration) }

        guard !Task.isCancelled else { return }

        self.nextItem = nextIntent
        self.previousItem = previousIntent
    }
}
