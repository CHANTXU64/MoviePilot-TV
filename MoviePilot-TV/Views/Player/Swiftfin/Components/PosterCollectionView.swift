//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//
// 本文件改自 Swiftfin：Shared/Views/VideoPlayer/Components/PosterCollectionView.swift
// Modifications for MoviePilot-TV are also licensed under MPL-2.0.
//
// 修改：只保留 tvOS 的横排。不用 Swiftfin 的 CollectionHStack，直接用 ScrollView + LazyHStack 排 App 自己的剧照卡
// （`StillCard`），左右留白与播放界面其他控件对齐；剧照左下角的小字和下面的标题由调用方给。
// 每次打开面板都滚到正在播的那一项，焦点从上面的标签移下来时也落在它上面。
// 离标签的留白放在滚动区域外面，滚动区域只和卡片一样高（见 body 里的说明）。
//

import SwiftUI

extension VideoPlayer {

    struct PosterCollectionView<Data: RandomAccessCollection>: View
        where Data.Element: Poster, Data.Index == Int
    {

        @FocusState
        private var focusedID: Data.Element.ID?

        private let data: Data
        private let currentElementID: Data.Element.ID?
        private let badge: (Data.Element) -> String?
        private let title: (Data.Element) -> String
        private let action: (Data.Element) -> Void

        init(
            data: Data,
            currentElementID: Data.Element.ID?,
            badge: @escaping (Data.Element) -> String?,
            title: @escaping (Data.Element) -> String,
            action: @escaping (Data.Element) -> Void
        ) {
            self.data = data
            self.currentElementID = currentElementID
            self.badge = badge
            self.title = title
            self.action = action
        }

        var body: some View {
            ScrollViewReader { reader in
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: StillCardLayout.spacing) {
                        ForEach(data) { element in
                            StillCard(
                                item: element,
                                badge: badge(element),
                                title: title(element),
                                isFocused: focusedID == element.id,
                                action: { action(element) }
                            )
                            .focused($focusedID, equals: element.id)
                        }
                    }
                    .padding(.horizontal, StillCardLayout.rowInset)
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
                // 滚动区域和卡片一样高、上下不留白：SwiftUI 按纵向居中对准卡片时，有时按内容高度算，
                // 内容里卡片若不居中，整行会被纵向滚上去一截。
                .fixedSize(horizontal: false, vertical: true)
                // 与简介面板离标签同样远；剧照聚焦时向上长出约 9pt，仍和标签隔开。
                .padding(.top, PlayerPanelLayout.tabGap)
                .focusSection()
                .defaultFocus($focusedID, currentElementID, priority: .userInitiated)
                // 面板每次打开，托管它的视图都会重新出现：按此刻在播的位置滚，不沿用上次打开时的。
                .onAppear {
                    guard let currentElementID else { return }

                    reader.scrollTo(
                        currentElementID,
                        anchor: EpisodeCardLayout.leadingScrollAnchor(cardWidth: StillCardLayout.size.width)
                    )
                }
            }
        }
    }
}
