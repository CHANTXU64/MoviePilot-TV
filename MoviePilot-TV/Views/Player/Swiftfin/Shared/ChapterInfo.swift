//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//
// 本文件改自 Swiftfin：Shared/Extensions/JellyfinAPI/ChapterInfo.swift
// Modifications for MoviePilot-TV are also licensed under MPL-2.0.
//
// 修改：去掉 `import JellyfinAPI`，`ChapterInfo` 为 MoviePilot-TV 的同名 Emby 适配类型（见 SwiftfinPlayerModels.swift）；
// 选中描边 `PosterSelectionOverlay`（原定义于 Shared/Components/PosterIndicators/PosterIndicatorsOverlay.swift）一并移入本文件，
// 其主题色（Swiftfin 设置项 `accentColor`）取默认值 `jellyfinPurple`。
// `FullInfo` 与扩展标为 `nonisolated`（工程默认 MainActor 隔离，海报协议的视图成员仍在主线程）；
// 章节缺图占位由调用方按条目类型给出（电影、剧集图标）。章节图原版用 `transform` 在黑底上按比例完整显示，改为 `fitsPosterImage`
// （见 PosterImage.swift）。
//

import Foundation
import SwiftUI

nonisolated extension ChapterInfo: Displayable {

    var displayTitle: String {
        name ?? .emptyDash
    }
}

nonisolated extension ChapterInfo {

    var startSeconds: Duration? {
        guard let startPositionTicks else { return nil }

        return Duration.ticks(startPositionTicks)
    }
}

extension ChapterInfo {

    // TODO: possibly remove
    //       - have ChapterInfo: Poster
    //       - build info, ImageSource pairs where required
    nonisolated struct FullInfo: Poster {

        let chapterInfo: ChapterInfo
        let displayTitle: String
        let id: Int
        let imageSource: ImageSource?
        let preferredPosterDisplayType: PosterDisplayType = .landscape
        let systemImage: String
        let fitsPosterImage = true

        var startSeconds: Duration {
            chapterInfo.startSeconds ?? .zero
        }

        var subtitle: String?

        init(
            chapterInfo: ChapterInfo,
            imageSource: ImageSource? = nil,
            systemImage: String
        ) {
            self.chapterInfo = chapterInfo
            self.displayTitle = chapterInfo.displayTitle
            self.id = chapterInfo.hashValue
            self.imageSource = imageSource
            self.systemImage = systemImage
        }

        func imageSources(
            for displayType: PosterDisplayType,
            environment: Empty
        ) -> [ImageSource] {
            if displayType == .landscape {
                imageSource
            }
        }

        var posterLabel: some View {
            ChapterPosterLabel(chapter: self)
        }

        func posterAccessibility(configuration: PosterConfiguration) -> PosterAccessibility {
            let startTime = PosterAccessibility.duration(startSeconds)

            return PosterAccessibility(
                label: displayTitle,
                value: L10n.posterAccessibilityStartTime(startTime)
            )
        }

        func posterOverlay(for displayType: PosterDisplayType) -> some View {
            PosterSelectionOverlay()
        }
    }
}

// TODO: have label match what BaseItemDto does in PosterCollectionView
//       - different height, causes clipping

private struct ChapterPosterLabel: View {

    @AdaptiveLayout
    private var viewLayout

    let chapter: ChapterInfo.FullInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(chapter.chapterInfo.displayTitle)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text(chapter.startSeconds, format: .runtime)
                .font(viewLayout.value(standard: .subheadline.weight(.semibold), large: .caption))
                .foregroundStyle(Color(UIColor.systemBlue))
                .padding(.horizontal, 4)
                .background {
                    Color(.darkGray)
                        .opacity(0.2)
                        .cornerRadius(4)
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PosterSelectionOverlay: View {

    @AdaptiveLayout
    private var viewLayout

    private let accentColor = Color.jellyfinPurple

    @Environment(\.isSelected)
    private var isSelected

    var body: some View {
        if isSelected {
            ContainerRelativeShape()
                .stroke(accentColor, lineWidth: viewLayout.selectionBorderWidth)
                .clipped()
                .accessibilityHidden(true)
        }
    }
}
