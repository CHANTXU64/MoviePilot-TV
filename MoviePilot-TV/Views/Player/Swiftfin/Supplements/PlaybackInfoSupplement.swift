//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//
// 本文件改自 Swiftfin：Shared/Objects/MediaPlayerManager/Supplements/PlaybackInfoSupplement.swift
// Modifications for MoviePilot-TV are also licensed under MPL-2.0.
//
// 修改：
// - 去掉 `Defaults`、`FactoryKit`、`JellyfinAPI`；片源与流换成 MoviePilot-TV 的同名 Emby 适配类型（来自 Emby PlaybackInfo）。
// - 原版 `PlaybackInformationProvider` 订阅 Jellyfin WebSocket 会话列表，取本设备会话的播放方式与转码信息。
//   MoviePilot-TV 只直连原文件，改为适配层提供的同名类型：播放方式固定为“直接播放”，没有转码信息（转码相关分区自然隐藏）。
//   该类移到 Views/Player/SwiftfinPlayerModels.swift。
// - 片源类型名改为 `PlaybackMediaSourceInfo`（工程里已有同名的 `MediaSourceInfo`）。
// - 删去 `#if os(iOS)` 分支。
// - Swift 6 下对 `VideoPlayerSupplement` 的一致性标为 `@MainActor`（与原版 MediaQueueView.swift 的写法相同）。
//

import SwiftUI

@MainActor
struct PlaybackInfoSupplement {

    let displayTitle: String = L10n.session
    let itemID: String
    let presentationStyle: VideoPlayerSupplementPresentationStyle = .expanded

    nonisolated var id: String {
        "PlaybackInformation-\(itemID)"
    }
}

extension PlaybackInfoSupplement: @MainActor VideoPlayerSupplement {

    var body: some View {
        OverlayView(itemID: itemID)
    }

    private struct OverlayView: PresentationView {

        @Environment(VideoPlayer.ViewState.self)
        private var viewState
        @Environment(MediaSession.self)
        private var mediaSession

        let itemID: String

        @State
        private var viewModel = PlaybackInformationProvider()

        private var mediaSource: PlaybackMediaSourceInfo? {
            mediaSession.playbackItem?.mediaSource
        }

        private var videoStream: MediaStream? {
            mediaSession.playbackItem?.videoStreams.first
        }

        private var audioStream: MediaStream? {
            guard let playbackItem = mediaSession.playbackItem else { return nil }

            if let selectedIndex = playbackItem.selectedAudioStreamIndex {
                return playbackItem.audioStreams.first { $0.index == selectedIndex }
            }

            return playbackItem.audioStreams.first
        }

        @ViewBuilder
        private var playbackInfoSection: some View {
            Text(L10n.mediaPlayback)
                .font(.subheadline)
                .fontWeight(.semibold)
                .padding(.vertical, 4)

            LabeledContent(L10n.videoPlayer, value: mediaSession.player?.displayTitle ?? .emptyDash)

            if let playbackItem = mediaSession.playbackItem {
                if let stream = playbackItem.subtitleStreams.first(property: \.index, equalTo: playbackItem.selectedSubtitleStreamIndex) {
                    LabeledContent(L10n.primarySubtitles, value: stream.displayTitle ?? L10n.unknown)
                }

                if let stream = playbackItem.subtitleStreams
                    .first(property: \.index, equalTo: playbackItem.selectedSecondarySubtitleStreamIndex)
                {
                    LabeledContent(L10n.secondarySubtitles, value: stream.displayTitle ?? L10n.unknown)
                }
            }

            if let playMethod = viewModel.currentSession?.playMethodDisplayTitle {
                LabeledContent(L10n.method, value: playMethod)
            }

            if let deliveryProtocol = mediaSource?.protocol {
                LabeledContent(L10n.source, value: deliveryProtocol.rawValue.uppercased())
            }

            if let transcodingSubProtocol = mediaSource?.transcodingSubProtocol {
                LabeledContent(L10n.protocol, value: transcodingSubProtocol.rawValue.uppercased())
            }
        }

        @ViewBuilder
        private var videoInfoSection: some View {
            if let width = videoStream?.width, let height = videoStream?.height {
                Text(L10n.video)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .padding(.vertical, 4)

                LabeledContent(L10n.videoResolution, value: height.description.multiply(by: width.description))
            }
        }

        @ViewBuilder
        private var streamingInfoSection: some View {
            if let transcodingInfo = viewModel.currentSession?.transcodingInfo {
                Text(viewModel.currentSession?.playMethodDisplayTitle.map { L10n.streamInfoWithMethod($0) } ?? L10n.streamInfo)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .padding(.vertical, 4)

                if let videoCodec = transcodingInfo.videoCodec {
                    LabeledContent(
                        L10n.videoCodec,
                        value: transcodingInfo.isVideoDirect == true
                            ? "\(videoCodec.uppercased()) (\(L10n.direct))"
                            : videoCodec.uppercased()
                    )
                }

                if let audioCodec = transcodingInfo.audioCodec {
                    LabeledContent(
                        L10n.audioCodec,
                        value: transcodingInfo.isAudioDirect == true
                            ? "\(audioCodec.uppercased()) (\(L10n.direct))"
                            : audioCodec.uppercased()
                    )
                }

                if let hwAccel = transcodingInfo.hardwareAccelerationType {
                    LabeledContent(L10n.hardwareAcceleration, value: hwAccel.rawValue)
                }

                if let completion = transcodingInfo.completionPercentage {
                    LabeledContent(L10n.transcodeProgress, value: "\(Int(completion))%")
                }
            }
        }

        @ViewBuilder
        private var originalMediaInfoSection: some View {
            if mediaSource != nil || videoStream != nil || audioStream != nil {
                Text(L10n.originalMediaInfo)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .padding(.vertical, 4)

                if let container = mediaSource?.container {
                    LabeledContent(L10n.container, value: container)
                }

                if let size = mediaSource?.size {
                    LabeledContent(L10n.size, value: Int64(size).formatted(.byteCount(style: .file)))
                }

                if let bitrate = mediaSource?.bitrate {
                    LabeledContent(L10n.bitrate, value: bitrate.formatted(.bitRate))
                }

                if let codec = videoStream?.codec {
                    let display = videoStream?.profile.map { "\(codec.uppercased()) \($0)" } ?? codec.uppercased()
                    LabeledContent(L10n.videoCodec, value: display)
                }

                if let bitRate = videoStream?.bitRate {
                    LabeledContent(L10n.videoBitRate, value: bitRate.formatted(.bitRate))
                }

                if let videoRangeType = videoStream?.videoRangeType {
                    LabeledContent(L10n.videoRangeType, value: videoRangeType.rawValue)
                }

                if let codec = audioStream?.codec {
                    LabeledContent(L10n.audioCodec, value: codec.uppercased())
                }

                if let bitRate = audioStream?.bitRate {
                    LabeledContent(L10n.audioBitrate, value: bitRate.formatted(.bitRate))
                }

                if let channels = audioStream?.channels {
                    LabeledContent(L10n.channels, value: "\(channels)")
                }

                if let sampleRate = audioStream?.sampleRate {
                    LabeledContent(L10n.audioSampleRate, value: "\(sampleRate) Hz")
                }
            }
        }

        @ViewBuilder
        private var transcodeReasonsSection: some View {
            if let transcodeReasons = viewModel.currentSession?.transcodingInfo?.transcodeReasons, transcodeReasons.isNotEmpty {
                Text(L10n.transcodeReasons)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .padding(.vertical, 4)

                ForEach(transcodeReasons, id: \.self) { reason in
                    Text(reason.displayTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }

        var standardView: some View {
            CompactOrRegularView(
                isCompact: viewState.isCompact
            ) {
                compactView
            } regularView: {
                regularView
            }
            .onFirstAppear { viewModel.observe(itemID: itemID) }
            .labeledContentStyle(.playbackInfo)
            .padding(.leading, viewState.supplementInsets.leading)
            .padding(.trailing, viewState.supplementInsets.trailing)
            .padding(.bottom, viewState.systemInsets.bottom)
        }

        private var compactView: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    playbackInfoSection
                    videoInfoSection
                    originalMediaInfoSection
                    streamingInfoSection
                    transcodeReasonsSection
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollIndicators(.hidden)
            .edgePadding()
        }

        private var regularView: some View {
            ScrollView {
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 4) {
                        playbackInfoSection
                        videoInfoSection
                        streamingInfoSection
                        transcodeReasonsSection
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                    VStack(alignment: .leading, spacing: 4) {
                        originalMediaInfoSection
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            .scrollIndicators(.hidden)
            .edgePadding()
        }

        var largeView: some View {
            regularView
                .onFirstAppear { viewModel.observe(itemID: itemID) }
                .labeledContentStyle(.playbackInfo)
                .focusSection()
        }
    }
}
