//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//
// 本文件改自 Swiftfin：Shared/Components/PosterImage.swift
// Modifications for MoviePilot-TV are also licensed under MPL-2.0.
//
// 修改：原版的 `ImageView` 基于 Nuke，占位图用 BlurHashKit；MoviePilot-TV 未引入这两个依赖，
// 去掉 `pipeline` 及其修饰器，模糊占位改为与无模糊值时相同的系统图标占位；`@SharedPoster` 换成普通存储属性。
//

import SwiftUI

struct PosterImage<Element: Poster>: View {

    @Environment(\.self)
    private var environment

    private let contentMode: ContentMode
    private var element: Element
    private let size: PosterDisplayType.Size
    private let displayType: PosterDisplayType

    init(
        item: Element,
        type: PosterDisplayType,
        size: PosterDisplayType.Size = .small,
        contentMode: ContentMode = .fill
    ) {
        self.contentMode = contentMode
        self.displayType = type
        self.element = item
        self.size = size
    }

    private var imageSources: [ImageSource] {
        element.imageSources(
            for: displayType,
            size: size,
            environment: element.resolveEnvironment(environment)
        )
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.complexSecondary)

            AlternateLayoutView {
                Color.clear
            } content: {
                ImageView(imageSources)
                    .image { image in
                        element.transform(image: image, displayType: displayType)
                    }
                    .placeholder { _ in
                        SystemImageContentView(
                            systemName: element.systemImage
                        )
                    }
                    .failure {
                        SystemImageContentView(
                            systemName: element.systemImage
                        )
                    }
                    .accessibilityRemoveTraits(.isImage)
                    .accessibilityIgnoresInvertColors()
            }
        }
        .posterStyle(
            displayType,
            contentMode: contentMode
        )
    }
}
