//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//
// 本文件改自 Swiftfin：Shared/Views/VideoPlayer/Components/PlaybackProgress/ChapterTrackMask.swift
// Modifications for MoviePilot-TV are also licensed under MPL-2.0.
//
// 修改：去掉 `import JellyfinAPI`；Jellyfin 类型换成 MoviePilot-TV 的同名 Emby 适配类型（见 Views/Player/SwiftfinPlayerModels.swift）。
//

import SwiftUI

extension VideoPlayer.PlaybackControls.PlaybackProgress {

    struct ChapterTrackMask: View {

        @AdaptiveLayout
        private var viewLayout

        let chapters: [ChapterInfo]
        let runtime: Duration

        private var unitPoints: [Double] {
            chapters.map { chapter in
                guard let startSeconds = chapter.startSeconds,
                      runtime > .zero,
                      startSeconds >= .zero,
                      startSeconds < runtime
                else {
                    return 0
                }

                let unitPoint = startSeconds / runtime
                guard unitPoint.isFinite else { return 0 }

                return clamp(unitPoint, min: 0, max: 1)
            }
        }

        var body: some View {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    ForEach(unitPoints, id: \.self) { unitPoint in
                        if unitPoint > 0 {
                            Color.black
                                .frame(width: viewLayout.value(standard: 1.5, large: 3))
                                .offset(x: proxy.size.width * unitPoint - viewLayout.value(standard: 0.75, large: 1.5))
                        }
                    }
                }
            }
        }
    }
}
