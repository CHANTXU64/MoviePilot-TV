//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//
// 本文件改自 Swiftfin：Shared/Objects/VideoPlayerActionButton.swift
// Modifications for MoviePilot-TV are also licensed under MPL-2.0.
//
// 修改：删去 iOS 分支；去掉 Swiftfin 设置存储用的 `Storable` 一致性。
//

enum VideoPlayerActionButton: String, CaseIterable, Displayable, Equatable, Identifiable, SystemImageable {

    case aspectFill
    case audio
    case audioOffset
    case autoPlay
    case pictureInPicture
    case playbackSpeed
    case playbackSettings
    case playNextItem
    case playPreviousItem
    case nextChapter
    case previousChapter
    case subtitles
    case subtitleOffset

    var displayTitle: String {
        switch self {
        case .aspectFill:
            L10n.aspectFill
        case .audio:
            L10n.audio
        case .audioOffset:
            L10n.audioOffset
        case .autoPlay:
            L10n.autoPlay
        case .pictureInPicture:
            L10n.pictureInPicture
        case .playbackSpeed:
            L10n.playbackSpeed
        case .playbackSettings:
            L10n.playback
        case .playNextItem:
            L10n.playNextItem
        case .playPreviousItem:
            L10n.playPreviousItem
        case .nextChapter:
            L10n.nextChapter
        case .previousChapter:
            L10n.previousChapter
        case .subtitles:
            L10n.subtitles
        case .subtitleOffset:
            L10n.subtitleOffset
        }
    }

    var id: String {
        rawValue
    }

    var systemImage: String {
        switch self {
        case .aspectFill: "arrow.up.left.and.arrow.down.right"
        case .audio: "speaker.wave.2"
        case .audioOffset: "waveform.path"
        case .autoPlay: "play.fill"
        case .pictureInPicture: "pip.enter"
        case .playbackSpeed: "speedometer"
        case .playbackSettings: "tv"
        case .playNextItem: "forward.end.fill"
        case .playPreviousItem: "backward.end.fill"
        case .nextChapter: "forward.frame.fill"
        case .previousChapter: "backward.frame.fill"
        case .subtitles: "captions.bubble.fill"
        case .subtitleOffset: "textformat.abc"
        }
    }

    var secondarySystemImage: String {
        switch self {
        case .aspectFill: "arrow.down.right.and.arrow.up.left"
        case .audio: "speaker.wave.2"
        case .autoPlay: "stop.fill"
        case .pictureInPicture: "pip.exit"
        case .subtitles: "captions.bubble"
        default:
            systemImage
        }
    }

    static var supportedCases: [Self] {
        allCases
    }

    static let defaultBarActionButtons: [VideoPlayerActionButton] = {
        var buttons: [VideoPlayerActionButton] = [
            .aspectFill,
            .autoPlay,
            .playPreviousItem,
            .playNextItem,
        ]
        return buttons
    }()

    static let defaultMenuActionButtons: [VideoPlayerActionButton] = [
        .audio,
        .audioOffset,
        .subtitles,
        .subtitleOffset,
        .playbackSpeed,
        .pictureInPicture,
        .playbackSettings,
    ].filter { supportedCases.contains($0) }
}
