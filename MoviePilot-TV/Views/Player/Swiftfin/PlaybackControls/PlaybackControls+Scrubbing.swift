//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//
// 本文件改自 Swiftfin：Swiftfin tvOS/Views/VideoPlayer/PlaybackControls/Components/PlaybackControls+Scrubbing.swift
// Modifications for MoviePilot-TV are also licensed under MPL-2.0.
//
// 修改：去掉长按右键的 2 倍速；左右键点一下前后跳 `VideoPlayerDefaults.jumpInterval`（10 秒，与系统播放器相同），
// 拖动中只挪拖动位置。跳转只显示进度条，不再在画面顶部弹提示。
//

import SwiftUI

extension VideoPlayer.PlaybackControls {

    func jump(_ direction: ViewState.Scan.Direction) {
        let interval = VideoPlayerDefaults.jumpInterval
        let offset = direction == .forward ? interval : .zero - interval

        if viewState.isScrubbing {
            viewState.moveScrub(by: offset)
            return
        }

        guard mediaSession.seek(by: offset) else { return }

        viewState.showProgress()
    }
}
