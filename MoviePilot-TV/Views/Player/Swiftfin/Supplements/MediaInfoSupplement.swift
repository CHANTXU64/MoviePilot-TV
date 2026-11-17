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
// - 片长和结束时间读 `MediaSession.runtime`（所播文件的片长，起播后以播放器读到的为准），与进度条同一个值；原版读条目的片长。
//   结束时间在播放位置、片长、倍速任一变化时重算（原版只跟播放位置），暂停时播放器读出片长或改了倍速也会更新。
// - 「从头播放」用播放界面统一的玻璃胶囊按钮，未聚焦时不再常亮白底。
// - 大屏布局照 Apple TV App 播放界面的简介面板：整块圆角玻璃（`PlayerGlassPanel`），海报贴着面板左边、四周留 20，
//   文字在中间，按钮在右边；海报定高（`PlayerPanelLayout.infoPosterHeight`，横版 402×226），横版、竖版按各自比例定宽，
//   圆角与面板同心。原版是海报离面板左边 60 的薄材质底。
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

                    if let runtime = mediaSession.runtime.flatMap({ BaseItemDto.runTimeLabel(seconds: $0.seconds) }) {
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
            .onChange(of: mediaSession.seconds, initial: true) { updateEndsAtLabel() }
            .onChange(of: mediaSession.runtime) { updateEndsAtLabel() }
            .onChange(of: mediaSession.rate) { updateEndsAtLabel() }
        }

        private var fromBeginningButton: some View {
            Button {
                mediaSession.seek(to: .zero)
                mediaSession.setPlaybackRequestStatus(status: .playing)
                viewState.selectedSupplementID = nil
            } label: {
                Label(L10n.fromBeginning, systemImage: AppSymbol.play)
            }
            .buttonStyle(.playerGlass)
            .fixedSize()
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
                        .padding(.vertical)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .edgePadding()
        }

        /// 按钮离面板右边比海报离左边多出的距离（面板内边距另算）。
        private static let buttonTrailingInset: CGFloat = 32

        private var posterSize: CGSize {
            let height = PlayerPanelLayout.infoPosterHeight
            return switch item.preferredPosterDisplayType {
            case .landscape: CGSize(width: (height * 16 / 9).rounded(), height: height)
            case .portrait: CGSize(width: (height * 2 / 3).rounded(), height: height)
            case .square: CGSize(width: height, height: height)
            }
        }

        private var regularContent: some View {
            HStack(alignment: .center, spacing: 40) {
                PosterImage(
                    item: item,
                    type: item.preferredPosterDisplayType,
                    contentMode: .fit
                )
                .frame(width: posterSize.width, height: posterSize.height)
                .clipShape(RoundedRectangle(cornerRadius: PlayerPanelLayout.contentCornerRadius, style: .continuous))
                .withViewContext(.isOverComplexContent)

                VStack(alignment: .leading, spacing: 6) {
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
                            // 标题两行、简介三行加信息行正好放进海报的高度，面板不被撑高。
                            .lineLimit(3)
                    }

                    accessoryView
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if !item.isLiveStream {
                    fromBeginningButton
                        .padding(.trailing, Self.buttonTrailingInset)
                }
            }
        }

        var largeView: some View {
            PlayerGlassPanel {
                regularContent
            }
            .padding(.top, PlayerPanelLayout.tabGap)
            .edgePadding(.horizontal)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .focusSection()
        }

        private func updateEndsAtLabel() {
            let newLabel = makeEndsAtLabel(seconds: mediaSession.seconds)

            if newLabel != endsAtLabel {
                endsAtLabel = newLabel
            }
        }

        private func makeEndsAtLabel(seconds: Duration) -> String? {
            guard !item.isLiveStream,
                  item.type != .recording,
                  let runtime = mediaSession.runtime,
                  runtime > .zero,
                  mediaSession.rate > 0
            else { return nil }

            let remaining = max(runtime - seconds, .zero)
            let endDate = Date.now.addingTimeInterval(remaining.seconds / mediaSession.rate)

            return L10n.endsAt(endDate.formatted(date: .omitted, time: .shortened))
        }
    }
}
