//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//
// 本文件改自 Swiftfin：Shared/Views/VideoPlayer/Container/VideoPlayer+VideoLayout.swift
// Modifications for MoviePilot-TV are also licensed under MPL-2.0.
//
// 修改：删去 `#if os(iOS)` 分支（刘海留白与 iOS 缩放视口）。
//

import SwiftUI

extension VideoPlayer {

    struct VideoLayout {

        private let aspectRatio: CGFloat?
        private let behavior: ViewState.AspectFillBehavior
        let renderSize: CGSize
        let renderScale: CGFloat
        let renderOffset: CGSize
        private let zoomFrame: CGRect?

        init(
            videoSize: CGSize,
            viewportSize: CGSize,
            behavior: ViewState.AspectFillBehavior,
            zoom: VideoZoom = VideoZoom()
        ) {
            self.aspectRatio = videoSize.aspectRatio

            if let geometry = zoom.geometry, let transform = zoom.transform {
                let frame = geometry.frame(at: transform.scale, offset: transform.offset)
                self.behavior = .fit
                self.renderSize = geometry.fitFrame.size
                self.renderScale = transform.scale

                self.renderOffset = CGSize(
                    width: frame.midX - geometry.viewportSize.width / 2,
                    height: frame.midY - geometry.viewportSize.height / 2
                )

                self.zoomFrame = frame
            } else {
                let geometry = Self.renderGeometry(aspectRatio: aspectRatio, viewportSize: viewportSize, behavior: behavior)
                self.behavior = behavior
                self.renderSize = geometry.size
                self.renderScale = geometry.scale
                self.renderOffset = .zero
                self.zoomFrame = nil
            }
        }

        private static func renderGeometry(
            aspectRatio: CGFloat?,
            viewportSize: CGSize,
            behavior: ViewState.AspectFillBehavior
        ) -> (size: CGSize, scale: CGFloat) {
            if let aspectRatio, viewportSize.aspectRatio != nil {
                let height = viewportSize.width / aspectRatio
                let heightScale = viewportSize.height / height

                if height.isFinite, height > 0, heightScale.isFinite {
                    return (
                        CGSize(width: viewportSize.width, height: height),
                        behavior == .fill ? max(1, heightScale) : min(1, heightScale)
                    )
                }
            }

            return (viewportSize, 1)
        }

        func videoFrame(in bounds: CGRect) -> CGRect {
            if let zoomFrame {
                return zoomFrame.offsetBy(dx: bounds.minX, dy: bounds.minY)
            }

            let geometry = Self.renderGeometry(aspectRatio: aspectRatio, viewportSize: bounds.size, behavior: behavior)
            let size = CGSize(width: geometry.size.width * geometry.scale, height: geometry.size.height * geometry.scale)
            guard size.width.isFinite, size.height.isFinite else { return bounds }

            return CGRect(
                x: bounds.midX - size.width / 2,
                y: bounds.midY - size.height / 2,
                width: size.width,
                height: size.height
            )
        }

    }

    struct VideoViewport<Content: View>: View {

        @Environment(ViewState.self)
        private var viewState

        let videoSize: () -> CGSize

        @ViewBuilder
        let content: (VideoLayout) -> Content

        private var viewport: some View {
            GeometryReader { viewport in
                content(VideoLayout(
                    videoSize: videoSize(),
                    viewportSize: viewport.size,
                    behavior: viewState.aspectFillBehavior,
                    zoom: viewState.zoom
                ))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transaction { transaction in
                    if viewState.zoom.isInteracting {
                        transaction.animation = nil
                        transaction.disablesAnimations = true
                    }
                }
            }
        }

        var body: some View {
            viewport
                .animation(.easeInOut(duration: 0.2), value: viewState.aspectFillBehavior)
                .ignoresSafeArea(.container)
        }
    }
}
