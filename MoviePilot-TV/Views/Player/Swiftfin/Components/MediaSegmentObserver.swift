//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//
// 本文件改自 Swiftfin：Shared/Objects/MediaPlayerManager/MediaSegmentObserver.swift
// Modifications for MoviePilot-TV are also licensed under MPL-2.0.
//
// 修改：去掉 `import JellyfinAPI`；默认加载器由 Jellyfin 的 `/MediaSegments` 请求换成 `UserSession.mediaSegments(itemID:)`
// （MoviePilot-TV 的适配：取 Emby 章节里的片头/片尾标记）。
// 图标名改从 AppSymbol 取（项目统一图标来源），图标本身不变。
// 析构显式标为 `nonisolated`（tvOS 18.4–26.2 上，隔离析构在主线程、Task 之外执行会崩溃）。
// 判断能否跳过时的片长读 `MediaSession.runtime`（所播文件的片长，见 `PlaybackDuration`），原版是播放器时长优先、再用条目时长。
//

import Combine
import Foundation
import Observation

@MainActor
@Observable
final class MediaSegmentObserver: MediaSessionObserver, VideoPlayerOverlayActionProviding {

    // 显式非隔离析构，避开 tvOS 18 的隔离析构回部署崩溃。
    nonisolated deinit {}

    typealias Loader = @MainActor (String, UserSession) async throws -> [MediaSegmentDto]

    let id = "mediaSegments"
    private weak var item: MediaPlayerItem?
    private let load: Loader
    private weak var mediaSession: MediaSession?
    private(set) var segments: [MediaSegment] = []

    @ObservationIgnored
    private var request: AnyCancellable?

    init(load: @escaping Loader = { itemID, session in
        try await session.mediaSegments(itemID: itemID)
    }) {
        self.load = load
    }

    func observe(_ mediaSession: MediaSession) -> AnyCancellable {
        self.mediaSession = mediaSession
        item = mediaSession.playbackItem

        if let item, !item.baseItem.isLiveStream, item.baseItem.mediaType != .audio,
           let itemID = item.baseItem.id
        {
            let session = mediaSession.userSession

            request = Task { [weak self, weak item, load] in
                do {
                    let values = try await load(itemID, session)
                    guard !Task.isCancelled, let self, let item, self.mediaSession?.playbackItem === item else { return }

                    segments = MediaSegment.segments(from: values, itemID: itemID)
                } catch {
                    guard !Task.isCancelled else { return }

                    self?.mediaSession?.logger.debug("Media segments unavailable: \(error.localizedDescription)")
                }
            }
            .asAnyCancellable()
        }

        return AnyCancellable { [self] in
            MainActor.assumeIsolated {
                request = nil
                segments = []
                self.mediaSession = nil
                item = nil
            }
        }
    }

    var overlayActions: [VideoPlayerOverlayAction] {
        guard let mediaSession, let item, mediaSession.playbackItem === item,
              mediaSession.state == .playback, mediaSession.canSeek, !mediaSession.isSeeking else { return [] }

        let duration = mediaSession.runtime

        guard let segment = segments.first(where: { $0.skipTarget(at: mediaSession.seconds, duration: duration) != nil }) else { return [] }

        return [VideoPlayerOverlayAction(id: segment.id, title: L10n.skip, systemImage: AppSymbol.skipSegment) { [
            weak self,
            weak item
        ] in
            guard let self, let mediaSession = self.mediaSession, let item, self.item === item,
                  mediaSession.playbackItem === item, mediaSession.state == .playback, mediaSession.canSeek, !mediaSession.isSeeking,
                  let target = segment.skipTarget(
                      at: mediaSession.seconds,
                      duration: mediaSession.runtime
                  ) else { return }

            mediaSession.seek(to: target)
        }]
    }
}
