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
// - 去掉 `Defaults`、`JellyfinAPI`；进度条不画章节刻度（Swiftfin 的设置项 `chapterSlider` 与章节遮罩一并去掉）。
// - 去掉拖动进度时的预览图（`PreviewImageView` / `PreviewImageProvider`），只保留时间与进度。
// - 快退快进中不接手指滑动（见 `ViewState.scan`）。
//

import SwiftUI

// TODO: enabled/disabled state
// TODO: scrubbing snapping behaviors
//       - chapter boundaries
//       - current running time

extension VideoPlayer.PlaybackControls {

    struct PlaybackProgress: View {

        @Environment(ViewState.self)
        private var viewState
        @Environment(MediaSession.self)
        private var mediaSession

        @Toaster
        private var toaster: ToastProxy

        private var sliderHeight: CGFloat {
            isScrubbing ? 20 : 14
        }

        private var isScrubbing: Bool {
            viewState.isScrubbing
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
                // 快退快进中不接手指滑动：两边同时改位置会来回跳，点按换档时手指一动也会误滑。
                isScrollingEnabled: mediaSession.playbackRequestStatus == .paused && mediaSession.canSeek
                    && viewState.scan == nil,
                originProgress: currentProgress
            )
            .onEditingChanged { isEditing in
                if isEditing {
                    viewState.beginScrub()
                }
            }
            .sliderContainerStyle(.capsule(showsProgressWhenUnfocused: false))
            .frame(height: sliderHeight)
            .foregroundStyle(mediaSession.canSeek ? Color.primary : Color.gray)
            .disabled(!mediaSession.canSeek)
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
        }
    }
}
