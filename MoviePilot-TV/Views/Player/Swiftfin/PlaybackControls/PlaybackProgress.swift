//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//
// 本文件改自 Swiftfin：Swiftfin tvOS/Views/VideoPlayer/PlaybackControls/Components/PlaybackProgress.swift
// Modifications for MoviePilot-TV are also licensed under MPL-2.0.
//
// 修改：
// - 去掉 `Defaults`、`JellyfinAPI`；章节刻度开关（Swiftfin 设置项 `chapterSlider`，默认开）换成 `VideoPlayerDefaults.chapterSlider`。
// - 原版用 Swiftfin 的 `if(_:transform:)`（带 `@ViewBuilder`）套章节遮罩；工程已有同名但不带 `@ViewBuilder` 的扩展，
//   改为本文件私有的 `ChapterSliderMask` 修饰器，效果相同。
// - 章节刻度读 `mediaSession.chapters`（条目上不带章节）；片长未知时不画刻度。
// - 视频宽高比原版取自 `(player as? VideoMediaPlayer)?.videoState.videoSize`，这里取 `mediaSession.videoSize`。
//

import SwiftUI

// TODO: enabled/disabled state
// TODO: scrubbing snapping behaviors
//       - chapter boundaries
//       - current running time
// TODO: show chapter title under preview image
//       - have max width, on separate offset track

extension VideoPlayer.PlaybackControls {

    struct PlaybackProgress: View {

        private let chapterSlider = VideoPlayerDefaults.chapterSlider

        @Environment(ViewState.self)
        private var viewState
        @Environment(MediaSession.self)
        private var mediaSession
        @State
        private var sliderSize: CGSize = .zero

        @Toaster
        private var toaster: ToastProxy

        private let previewImageHeight: CGFloat = 200

        private var sliderHeight: CGFloat {
            isScrubbing ? 20 : 14
        }

        private var isScrubbing: Bool {
            viewState.isScrubbing
        }

        private var scrubbedProgress: Double {
            guard let runtime = mediaSession.item.runtime, runtime > .zero else { return 0 }

            let progress = viewState.scrubbedSeconds / runtime
            guard progress.isFinite else { return 0 }

            return clamp(progress, min: 0, max: 1)
        }

        private var currentProgress: Double? {
            guard isScrubbing,
                  let runtime = mediaSession.item.runtime,
                  runtime > .zero
            else {
                return nil
            }

            let currentSeconds = viewState.scrubOriginSeconds ?? viewState.playbackSeconds
            let progress = (currentSeconds / runtime) * 100
            guard progress.isFinite else { return nil }

            return clamp(progress, min: 0, max: 100)
        }

        private var videoSizeAspectRatio: CGFloat {
            guard let aspectRatio = mediaSession.videoSize.aspectRatio else {
                return 1.77
            }

            return clamp(aspectRatio, min: 0.25, max: 4)
        }

        private var previewXOffset: CGFloat {
            guard sliderSize.width.isFinite, sliderSize.width > 0 else { return 0 }

            let videoWidth = previewImageHeight * videoSizeAspectRatio
            let p = (sliderSize.width * scrubbedProgress) - (videoWidth / 2)

            return clamp(p, min: 0, max: max(0, sliderSize.width - videoWidth))
        }

        private var liveIndicator: some View {
            Text(L10n.live)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                .background {
                    Capsule()
                        .fill(Color.gray)
                }
        }

        private var videoPlayerSlider: some View {
            SliderContainer(
                value: Bindable(viewState).scrubbedSeconds.map(
                    getter: {
                        guard let runtime = mediaSession.item.runtime, runtime > .zero else { return 0 }

                        let seconds = $0.seconds
                        let runtimeSeconds = runtime.seconds
                        guard seconds.isFinite, runtimeSeconds.isFinite, runtimeSeconds > 0 else { return 0 }

                        return clamp((seconds / runtimeSeconds) * 100, min: 0, max: 100)
                    },
                    setter: {
                        guard $0.isFinite else { return .zero }

                        return (mediaSession.item.runtime ?? .zero) * (clamp($0, min: 0, max: 100) / 100)
                    }
                ),
                total: 100,
                isScrollingEnabled: mediaSession.playbackRequestStatus == .paused && mediaSession.canSeek,
                originProgress: currentProgress
            )
            .onEditingChanged { isEditing in
                if isEditing {
                    viewState.beginScrub()
                }
            }
            .sliderContainerStyle(.capsule(showsProgressWhenUnfocused: false))
            .modifier(ChapterSliderMask(
                isEnabled: chapterSlider,
                chapters: mediaSession.chapters.loaded.map(\.chapterInfo),
                runtime: mediaSession.item.runtime ?? .zero
            ))
            .frame(height: sliderHeight)
            .trackingSize($sliderSize)
            .foregroundStyle(mediaSession.canSeek ? Color.primary : Color.gray)
            .disabled(!mediaSession.canSeek)
        }

        @ViewBuilder
        private var previewImage: some View {
            if isScrubbing, let previewImageProvider = mediaSession.playbackItem?.previewImageProvider {
                PreviewImageView(previewImageProvider: previewImageProvider)
                    .aspectRatio(videoSizeAspectRatio, contentMode: .fit)
                    .frame(height: previewImageHeight)
                    .posterBorder()
                    .cornerRadius(ratio: 1 / 30, of: \.width)
                    .offset(x: previewXOffset, y: -(previewImageHeight + 10))
                    .shadow(color: Color.black.opacity(0.5), radius: 10, x: 0, y: 4)
            }
        }

        var body: some View {
            VStack(spacing: 10) {
                if mediaSession.item.isLiveStream {
                    liveIndicator
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    videoPlayerSlider

                    SplitTimeStamp()
                        .foregroundStyle(.white, Color.lightGray)
                }
            }
            .coordinatedFocus(ViewState.Focus.progress)
            .foregroundStyle(Color.white.opacity(0.75))
            .overlay(alignment: .topLeading) {
                previewImage
            }
        }
    }
}

private struct ChapterSliderMask: ViewModifier {

    let isEnabled: Bool
    let chapters: [ChapterInfo]
    let runtime: Duration

    func body(content: Content) -> some View {
        // 片长未知时刻度全落在 0，画不出来，还会让 `ChapterTrackMask` 的 ID 重复。
        if isEnabled, chapters.isNotEmpty, runtime > .zero {
            content.inverseMask { VideoPlayer.PlaybackControls.PlaybackProgress.ChapterTrackMask(chapters: chapters, runtime: runtime) }
        } else {
            content
        }
    }
}
