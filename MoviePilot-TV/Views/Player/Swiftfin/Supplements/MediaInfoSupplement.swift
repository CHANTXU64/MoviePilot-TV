//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//
// 本文件改自 Swiftfin：Shared/Objects/MediaPlayerManager/Supplements/MediaInfoSupplement.swift
// Modifications for MoviePilot-TV are also licensed under MPL-2.0.
//
// 修改：
// - 条目改用 MoviePilot-TV 的 Emby 适配类型 `BaseItemDto`（同名，见 SwiftfinPlayerModels.swift），`@SharedBaseItem` 换成普通存储属性。
// - 去掉直播录制按钮（`RecordingTimerViewModel`，属于 Jellyfin 直播电视模块，未移植）及其刷新任务；
//   原版只在直播或可录制条目上显示，Emby 直连播放的条目不会走到这些分支。
// - Swift 6 下对 `VideoPlayerSupplement` 的一致性标为 `@MainActor`（与原版 MediaQueueView.swift 的写法相同）。
// - 图标名改从 AppSymbol 取（项目统一图标来源），图标本身不变。
// - 信息行加上评分（MoviePilot 的 TMDB/豆瓣评分，没有时用媒体服务器的）：MoviePilot 没有分级，原版只显示分级。
//

import SwiftUI

// TODO: scroll if description too long

@MainActor
struct MediaInfoSupplement {

    let displayTitle: String = L10n.info
    var item: BaseItemDto

    nonisolated let id: String

    init(item: BaseItemDto) {
        self.item = item
        self.id = "MediaInfo-\(item.id ?? "any")"
    }
}

extension MediaInfoSupplement: @MainActor VideoPlayerSupplement {

    var body: some View {
        InfoOverlay(item: item)
    }

    private struct InfoOverlay: PresentationView {

        @AdaptiveLayout
        private var viewLayout

        @Environment(VideoPlayer.ViewState.self)
        private var viewState
        @Environment(MediaSession.self)
        private var mediaSession

        private var item: BaseItemDto

        @State
        private var endsAtLabel: String?

        init(item: BaseItemDto) {
            self.item = item
        }

        private var accessoryView: some View {
            VStack(alignment: .leading) {
                DotHStack {
                    if item.type == .episode {
                        if let premiereDateLabel = item.premiereDateLabel {
                            Text(premiereDateLabel)
                        }

                        if let seasonEpisodeLocator = item.seasonEpisodeLabel {
                            Text(seasonEpisodeLocator)
                        }
                    } else if let premiereYear = item.premiereDateYear {
                        Text(premiereYear)
                    }

                    if let runtime = item.runTimeLabel {
                        Text(runtime)
                    }

                    if let officialRating = item.officialRating {
                        Text(officialRating)
                    }

                    if let communityRating = item.communityRating {
                        Label(communityRating.formatted(.number.precision(.fractionLength(1))), systemImage: AppSymbol.rating)
                    }

                    if let endsAtLabel {
                        Text(endsAtLabel)
                    }
                }
            }
            .onChange(of: mediaSession.seconds, initial: true) { _, seconds in
                let newLabel = makeEndsAtLabel(seconds: seconds)

                if newLabel != endsAtLabel {
                    endsAtLabel = newLabel
                }
            }
        }

        private var fromBeginningButton: some View {
            Button {
                mediaSession.seek(to: .zero)
                mediaSession.setPlaybackRequestStatus(status: .playing)
                viewState.selectedSupplementID = nil
            } label: {
                Label(L10n.fromBeginning, systemImage: AppSymbol.play)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            .buttonStyle(.supplementAction)
            .frame(height: viewLayout.supplementLogoHeight)
        }

        // TODO: may need to be a layout for correct overview frame
        //       with scrolling if too long
        var standardView: some View {
            CompactOrRegularView(
                isCompact: viewState.isCompact
            ) {
                compactView
            } regularView: {
                regularContent
                    .edgePadding()
            }
            .padding(.leading, viewState.supplementInsets.leading)
            .padding(.trailing, viewState.supplementInsets.trailing)
        }

        private var compactView: some View {
            VStack(alignment: .leading) {
                Text(item.displayTitle)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let currentProgram = item.currentProgram {
                    Text(currentProgram.displayTitle)
                        .fontWeight(.semibold)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(.secondary)
                }

                if let overview = item.overview ?? item.currentProgram?.overview {
                    Text(overview)
                        .font(.subheadline)
                        .fontWeight(.regular)
                }

                accessoryView
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !item.isLiveStream {
                    fromBeginningButton
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .padding(.vertical)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .edgePadding()
        }

        private var regularContent: some View {
            HStack(alignment: .bottom, spacing: viewLayout.edgePadding) {
                // TODO: determine what to do with non-portrait (channel, home video) images
                //       - use aspect ratio?
                PosterImage(
                    item: item,
                    type: item.preferredPosterDisplayType,
                    contentMode: .fit
                )
                .posterCornerRadius(item.preferredPosterDisplayType)
                .withViewContext(.isOverComplexContent)

                VStack(alignment: .leading, spacing: 5) {
                    Text(item.displayTitle)
                        .font(.callout)
                        .fontWeight(.semibold)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    if let currentProgram = item.currentProgram {
                        Text(currentProgram.displayTitle)
                            .font(.callout)
                            .fontWeight(.semibold)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .foregroundStyle(.secondary)
                    }

                    if let overview = item.overview ?? item.currentProgram?.overview {
                        Text(overview)
                            .font(.subheadline)
                            .fontWeight(.regular)
                            .lineLimit(4)
                    }

                    accessoryView
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if !item.isLiveStream {
                    AlternateLayoutView {
                        Label(L10n.fromBeginning, systemImage: AppSymbol.play)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .padding()
                            .edgePadding(.horizontal)
                            .frame(height: viewLayout.supplementRowHeight)
                    } content: {
                        fromBeginningButton
                    }
                }
            }
        }

        var largeView: some View {
            regularContent
                .edgePadding(.horizontal)
                .padding(.vertical, viewLayout.edgePadding / 2)
                .background {
                    RoundedRectangle(cornerRadius: 32)
                        .fill(Material.thin)
                }
                .clipShape(RoundedRectangle(cornerRadius: 32))
                .edgePadding()
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .focusSection()
        }

        private func makeEndsAtLabel(seconds: Duration) -> String? {
            guard !item.isLiveStream,
                  item.type != .recording,
                  let runtime = item.runtime,
                  runtime > .zero,
                  mediaSession.rate > 0
            else { return nil }

            let remaining = max(runtime - seconds, .zero)
            let endDate = Date.now.addingTimeInterval(remaining.seconds / mediaSession.rate)

            return L10n.endsAt(endDate.formatted(date: .omitted, time: .shortened))
        }
    }
}
