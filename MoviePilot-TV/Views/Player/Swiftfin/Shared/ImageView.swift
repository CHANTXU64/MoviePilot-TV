//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//
// 本文件改自 Swiftfin：Shared/Components/ImageView.swift
// Modifications for MoviePilot-TV are also licensed under MPL-2.0.
//
// 修改：原版用第三方 Nuke/NukeUI 的 `LazyImage` 加载、BlurHashKit 绘制模糊占位、SVGKit 绘制 SVG。
// MoviePilot-TV 未引入这些依赖（添加依赖未获授权），加载改用工程已有的 Kingfisher（`KingfisherManager`），
// 去掉模糊占位与 SVG 分支，`pipeline` 修饰器随之去掉。加载状态与失败后换下一个来源的逻辑与原版相同。
//

import Kingfisher
import SwiftUI

// TODO: currently SVGs are only supported for logos, which are only used in a few places.
//       make it so when displaying an SVG there is a unified `image` caller modifier
// TODO: look at replacing view phase resolution with `FadeContentTransitionView`
// TODO: Allow failure to reserve previous state, keeping placeholder if image fails
struct ImageView<_Image: View, Placeholder: View, Failure: View>: View {

    private enum Phase: Equatable {

        case loading
        case success(UIImage)
        case failure
    }

    @State
    private var sources: [ImageSource]
    @State
    private var phase: Phase = .loading

    private var image: (UIImage) -> _Image
    private var placeholder: (ImageSource) -> Placeholder
    private var failure: Failure

    fileprivate init(
        sources: [ImageSource],
        image: @escaping (UIImage) -> _Image,
        placeholder: @escaping (ImageSource) -> Placeholder,
        failure: Failure
    ) {
        self._sources = State(initialValue: sources)
        self.image = image
        self.placeholder = placeholder
        self.failure = failure
    }

    var body: some View {
        if let currentSource = sources.first {
            Group {
                switch phase {
                case .loading:
                    placeholder(currentSource)
                case let .success(uiImage):
                    image(uiImage)
                case .failure:
                    failure
                        .onAppear {
                            sources.removeFirstSafe()
                        }
                }
            }
            .animation(.linear, value: phase)
            .task(id: currentSource) {
                phase = .loading

                guard let url = currentSource.url else {
                    phase = .failure
                    return
                }

                do {
                    let result = try await KingfisherManager.shared.retrieveImage(with: url)
                    guard !Task.isCancelled else { return }

                    phase = .success(result.image)
                } catch {
                    guard !Task.isCancelled else { return }

                    phase = .failure
                }
            }
        } else {
            failure
        }
    }
}

extension ImageView where _Image == Image, Placeholder == DefaultPlaceholderView, Failure == EmptyView {

    init(_ source: ImageSource?) {
        self.init([source].compactMap(\.self))
    }

    init(_ sources: [ImageSource]) {
        self.init(
            sources: sources.compacted(using: \.url),
            image: { Image(uiImage: $0).resizable() },
            placeholder: { DefaultPlaceholderView(blurHash: $0.blurHash) },
            failure: EmptyView()
        )
    }

    init(_ source: URL?) {
        self.init([ImageSource(url: source)])
    }

    init(_ sources: [URL?]) {
        let imageSources = sources
            .compactMap(\.self)
            .map { ImageSource(url: $0) }

        self.init(imageSources)
    }
}

// MARK: Modifiers

extension ImageView {

    func image<NewImage: View>(
        @ViewBuilder _ content: @escaping (UIImage) -> NewImage
    ) -> ImageView<NewImage, Placeholder, Failure> {
        ImageView<NewImage, Placeholder, Failure>(
            sources: sources,
            image: content,
            placeholder: placeholder,
            failure: failure
        )
    }

    func image<NewImage: View>(
        @ViewBuilder _ content: @escaping (Image) -> NewImage
    ) -> ImageView<NewImage, Placeholder, Failure> {
        ImageView<NewImage, Placeholder, Failure>(
            sources: sources,
            image: { content(Image(uiImage: $0).resizable()) },
            placeholder: placeholder,
            failure: failure
        )
    }

    func placeholder<NewPlaceholder: View>(
        @ViewBuilder _ content: @escaping (ImageSource) -> NewPlaceholder
    ) -> ImageView<_Image, NewPlaceholder, Failure> {
        ImageView<_Image, NewPlaceholder, Failure>(
            sources: sources,
            image: image,
            placeholder: content,
            failure: failure
        )
    }

    func failure<NewFailure: View>(
        @ViewBuilder _ content: @escaping () -> NewFailure
    ) -> ImageView<_Image, Placeholder, NewFailure> {
        ImageView<_Image, Placeholder, NewFailure>(
            sources: sources,
            image: image,
            placeholder: placeholder,
            failure: content()
        )
    }
}

// MARK: Defaults

/// 原版用 BlurHashKit 把 `blurHash` 画成模糊占位；未引入该依赖，这里不绘制。
struct DefaultPlaceholderView: View {

    let blurHash: String?

    var body: some View {
        EmptyView()
    }
}
