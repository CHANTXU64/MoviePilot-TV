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
// 修改：原版用 Swiftfin 的 `ImageView`（基于 Nuke，占位图用 BlurHashKit）。这里改用 App 自己的 `PageManagedImage`：
// 受保护图片（MoviePilot 图片代理等）要带会话的下载器和 Cookie、缓存按会话隔开，App 其他页面也都经它加载。
// 只取第一个有地址的来源（这里的条目最多给一个），按显示宽度和画幅缩小解码。图片默认按比例填满海报框（原版是拉伸填满），
// 原版 `transform` 的自定义图片样式只保留章节截图用的那种：`fitsPosterImage` 时在黑底上按比例完整显示。
// 没有图或加载失败时显示条目的系统图标。`@SharedPoster` 换成普通存储属性。
//

import Kingfisher
import SwiftUI

struct PosterImage<Element: Poster>: View {

    @Environment(\.self)
    private var environment

    private let contentMode: SwiftUI.ContentMode
    private var element: Element
    private let size: PosterDisplayType.Size
    private let displayType: PosterDisplayType

    /// 已经加载出来的图片地址：按比例完整显示时，图出来以后才铺黑底，盖住下面的图标。
    @State
    private var loadedURL: URL?

    init(
        item: Element,
        type: PosterDisplayType,
        size: PosterDisplayType.Size = .small,
        contentMode: SwiftUI.ContentMode = .fill
    ) {
        self.contentMode = contentMode
        self.displayType = type
        self.element = item
        self.size = size
    }

    private var imageURL: URL? {
        element.imageSources(
            for: displayType,
            size: size,
            environment: element.resolveEnvironment(environment)
        )
        .lazy
        .compactMap(\.url)
        .first
    }

    /// 解码尺寸：这个尺寸档位的显示宽度，高度按画幅（与 `posterAspectRatio` 相同）。
    private var decodeSize: CGSize {
        let width = size.width(for: displayType) ?? 500
        let aspectRatio: CGFloat =
            switch displayType {
            case .landscape: 1.77
            case .portrait: 2 / 3
            case .square: 1
            }
        return CGSize(width: width, height: (width / aspectRatio).rounded(.up))
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.complexSecondary)

            AlternateLayoutView {
                Color.clear
            } content: {
                ZStack {
                    // 图片盖在图标上面：加载出来之前、没有图或加载失败时露出图标。
                    SystemImageContentView(
                        systemName: element.systemImage
                    )

                    if let imageURL {
                        if element.fitsPosterImage, loadedURL == imageURL {
                            Color.black
                        }

                        PageManagedImage(
                            url: imageURL,
                            processor: DownsamplingImageProcessor(size: decodeSize),
                            isEnabled: true,
                            participatesInPageLifecycle: false,
                            skipsMemoryCache: false,
                            fitsWholeImage: element.fitsPosterImage,
                            onSuccess: { loadedURL = imageURL }
                        )
                    }
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
