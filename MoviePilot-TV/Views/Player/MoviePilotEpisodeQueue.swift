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
// 取代 Swiftfin 的 `EpisodeMediaPlayerQueue`，所以放在 Swiftfin/ 目录外、改了类型名。
// 同步 Swiftfin 时不要把上游的 EpisodeMediaPlayerQueue.swift 加回 Swiftfin/，上游改动按需合进本文件。
// 播放界面仍通过 Swiftfin 的 `MediaPlayerQueue` 协议读同季列表和上一集/下一集。
//
// 修改：
// - 去掉 `Defaults`、`JellyfinAPI`；条目换成 MoviePilot-TV 的同名适配类型。
// - 不直接读 `MediaSession`，改读 `EpisodeQueueHost` / `EpisodeQueueSource`（生产里是 `MediaSession`、`UserSession`），
//   测试可以换成替身来控制查询时序。
// - 同季分集列表不用 Swiftfin 的分页库（`PagingLibraryViewModel<EpisodeLibrary>`），由
//   `UserSession.seasonEpisodes(seriesID:seasonID:)` 一次取完，状态映射与原版相同。
// - 相邻集由 `UserSession.adjacentEpisode(_:itemID:refresh:)` 分别给出上一集、下一集（原版为 Jellyfin
//   `getEpisodes(adjacentTo:limit: 3)` 一次取三集再按“四种情况”拆分），按 MoviePilot 集列表的顺序、只在当前服务器上找。
//   两个方向各自查询、各自先到先用，跨季查上一集慢时不耽误下一集。下一集是跳过还没入库的集找到的，记下来
//   （`nextNeedsRecheck`），播完时重新确认。
// - 新增 `lookUpNext()`：播完时重新读服务器再查一次下一集（播放期间刚入库的集也能接上），只返回结果、不改队列，
//   由 `MediaSession` 决定接着播还是退出并说明原因。
//   只有从详情页按集播放的条目带 `seriesID` / `seasonID`，其他入口的队列为空。
// - 码率设置 `appMaximumBitrate` 换成 `VideoPlayerDefaults.appMaximumBitrate`。
// - 析构显式标为 `nonisolated`（tvOS 18.4–26.2 上，隔离析构在主线程、Task 之外执行会崩溃）。
//

import Combine
import Foundation
import Observation

/// 队列跟随的播放界面：当前条目、码率和换集。生产里是 `MediaSession`。
@MainActor
protocol EpisodeQueueHost: AnyObject {
    /// 正在播的条目；变化时队列重新查相邻集。
    var currentItem: BaseItemDto? { get }
    var playbackBitrate: PlaybackBitrate { get }
    var episodeSource: any EpisodeQueueSource { get }
    func playNewItem(intent: PlaybackIntent)
}

/// 队列查集用的数据来源。生产里是 `UserSession`。
@MainActor
protocol EpisodeQueueSource: AnyObject {
    func seasonEpisodes(seriesID: String, seasonID: String) async throws -> [BaseItemDto]
    func adjacentEpisode(
        _ direction: EpisodeNavigator.Direction, itemID: String, refresh: Bool
    ) async throws -> AdjacentEpisode
}

@MainActor
@Observable
final class MoviePilotEpisodeQueue: MediaPlayerQueue {

    // 显式非隔离析构，避开 tvOS 18 的隔离析构回部署崩溃。
    nonisolated deinit {}

    /// 播完时重新查下一集的结果。
    enum NextLookup {
        case play(PlaybackIntent)
        /// 不接着播；有原因时退出后告诉用户（已经是最后一集时没有原因）。
        case unavailable(String?)
    }

    @ObservationIgnored
    private weak var host: (any EpisodeQueueHost)?
    private(set) var state: MediaPlayerQueueState = .initial
    private(set) var items: [ItemEntry] = []
    var nextItem: PlaybackIntent?
    var previousItem: PlaybackIntent?
    /// `nextItem` 是跳过还不在服务器上的集找到的：播完时要重新确认，那几集可能已经入库。
    private(set) var nextNeedsRecheck = false

    var currentEntryID: ItemEntry.ID? {
        host?.currentItem?.id.map { ItemEntry.ID(itemID: $0, occurrence: nil) }
    }

    /// 当前条目来自详情页按集播放，能按集列表找下一集。
    var canLookUpNext: Bool {
        guard let item = host?.currentItem else { return false }
        return item.type == .episode && item.seriesID != nil && item.id != nil
    }

    @ObservationIgnored
    private var currentNextTask: AnyCancellable?
    @ObservationIgnored
    private var currentPreviousTask: AnyCancellable?

    @ObservationIgnored
    private var seasonID: String?
    @ObservationIgnored
    private var seasonSeriesID: String?
    @ObservationIgnored
    private var seasonTask: AnyCancellable?

    func observe(_ mediaSession: MediaSession) -> AnyCancellable {
        follow(mediaSession)
    }

    /// 跟随 `host` 正在播的条目，直到返回的令牌被取消；取消时清空队列。
    func follow<Host: EpisodeQueueHost>(_ host: Host) -> AnyCancellable {
        self.host = host

        let observation = ObservationToken { [weak host] in
            host?.currentItem
        } onChange: { [weak self] item in
            self?.didReceive(newItem: item)
        }

        return AnyCancellable { [self, observation] in
            MainActor.assumeIsolated {
                observation.cancel()
                didReceive(newItem: nil)
                resetSeason()
                self.host = nil
            }
        }
    }

    private func didReceive(newItem item: BaseItemDto?) {
        currentNextTask = nil
        currentPreviousTask = nil
        nextItem = nil
        previousItem = nil
        nextNeedsRecheck = false

        guard let item else { return }

        updateSeason(for: item)

        currentNextTask = Task { [weak self] in
            try await self?.loadAdjacentEpisode(.next, for: item)
        }
        .asAnyCancellable()
        currentPreviousTask = Task { [weak self] in
            try await self?.loadAdjacentEpisode(.previous, for: item)
        }
        .asAnyCancellable()
    }

    func refresh() {
        guard let seasonID, let seasonSeriesID, let source = host?.episodeSource else { return }

        state = .loading

        seasonTask = Task { [weak self] in
            do {
                let episodes = try await source.seasonEpisodes(seriesID: seasonSeriesID, seasonID: seasonID)
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
        guard let host else { return }

        let configuration = with(MediaPlaybackConfiguration()) {
            $0.requestedBitrate = host.playbackBitrate
        }
        host.playNewItem(intent: PlaybackIntent(item: entry.snapshot, configuration: configuration))
    }

    /// 播完时重新读服务器查下一集。只返回结果，不改 `nextItem`：查询期间用户可能已经换了集或退出，
    /// 结果属于播完的那一集，由 `MediaSession` 确认还在那一集后再接着播。
    func lookUpNext() async -> NextLookup {
        guard canLookUpNext, let itemID = host?.currentItem?.id, let source = host?.episodeSource else {
            return .unavailable(nil)
        }
        do {
            switch try await source.adjacentEpisode(.next, itemID: itemID, refresh: true) {
            case .episode(let next, _):
                return .play(makeIntent(next))
            case .unavailable(let reason):
                return .unavailable(reason)
            case .none:
                return .unavailable(nil)
            }
        } catch is CancellationError {
            return .unavailable(nil)
        } catch {
            return .unavailable("无法确认下一集：\(error.localizedDescription)")
        }
    }

    private func updateSeason(for item: BaseItemDto) {
        guard item.type == .episode, let seasonID = item.seasonID?.nilIfBlank, host != nil else {
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

    private func loadAdjacentEpisode(_ direction: EpisodeNavigator.Direction, for item: BaseItemDto) async throws {
        guard let itemID = item.id, item.seriesID != nil, item.type == .episode else { return }
        guard let source = host?.episodeSource else {
            throw UserSessionError.missingCurrentSession
        }

        let response = try await source.adjacentEpisode(direction, itemID: itemID, refresh: false)
        guard !Task.isCancelled else { return }

        let intent: PlaybackIntent?
        var skippedMissing = false
        if case .episode(let episode, let skipped) = response {
            intent = makeIntent(episode)
            skippedMissing = skipped
        } else {
            intent = nil
        }
        switch direction {
        case .next:
            nextItem = intent
            nextNeedsRecheck = skippedMissing
        case .previous:
            previousItem = intent
        }
    }

    private func makeIntent(_ item: BaseItemDto) -> PlaybackIntent {
        let bitrate = host?.playbackBitrate ?? VideoPlayerDefaults.appMaximumBitrate

        let configuration = with(MediaPlaybackConfiguration()) {
            $0.requestedBitrate = bitrate
            $0.startSeconds = .zero
        }
        return PlaybackIntent(item: item, configuration: configuration)
    }
}
