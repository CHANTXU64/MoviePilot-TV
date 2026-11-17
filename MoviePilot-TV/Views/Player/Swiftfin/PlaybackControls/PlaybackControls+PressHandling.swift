//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//
// 本文件改自 Swiftfin：Swiftfin tvOS/Views/VideoPlayer/PlaybackControls/Components/PlaybackControls+PressHandling.swift
// Modifications for MoviePilot-TV are also licensed under MPL-2.0.
//
// 修改：左右键按系统播放器处理。点一下跳 10 秒；按住开始快退、快进，快退快进中再点一下换档或掉头；
// 去掉原版长按右键的 2 倍速。拖动中点一下只挪拖动位置。
//

import SwiftUI

extension VideoPlayer.PlaybackControls {

    func handlePressEvent(_ press: VideoPlayer.UIContainerViewController.PressEvent) {
        let direction = Self.scanDirection(for: press.type)

        if direction != nil, viewState.isOverlayActionFocused {
            press.resolve(.fallback)
            return
        }

        if viewState.presentation == .hidden, viewState.isPresentingOverlayActions {
            if direction != nil {
                press.resolve(.fallback)
                return
            }

            if press.phase == .began {
                viewState.showControls()
                press.resolve(.handled)
                return
            }
        }

        if press.phase == .began,
           direction != nil,
           mediaSession.canSeek,
           !viewState.isPresentingSupplement,
           viewState.presentation == .hidden || viewState.presentation == .progress || viewState.isProgressBarFocused
        {
            seekingPress = press.type
            viewState.showProgress()
        }

        // Retain ownership through ended/cancelled, even while the newly shown
        // slider is waiting for the focus engine to process our request.
        if seekingPress == press.type, let direction {
            viewState.refreshAutoDismiss()

            switch press.phase {
            case .began:
                beginSeekingPress(direction)
            case .ended:
                endSeekingPress(direction)
            case .cancelled:
                resetSeekingPress()
            default:
                break
            }

            press.resolve(.handled)
            return
        }

        if !viewState.isPresentingControls, press.phase == .began {
            viewState.showControls()
            press.resolve(.handled)
            return
        }

        viewState.refreshAutoDismiss()
        press.resolve(.fallback)
    }

    private static func scanDirection(for type: UIPress.PressType) -> ViewState.Scan.Direction? {
        switch type {
        case .leftArrow: .backward
        case .rightArrow: .forward
        default: nil
        }
    }

    /// 按下左右键：快退快进中按下的，松开时换档，不必等长按；否则开始计时，按满就开始快退快进。
    private func beginSeekingPress(_ direction: ViewState.Scan.Direction) {
        scanHoldTask?.cancel()
        didBeginScanByHolding = false

        guard viewState.scan == nil else { return }

        scanHoldTask = Task { @MainActor in
            try? await Task.sleep(for: VideoPlayerDefaults.scanHoldDelay)
            // 按住期间按了返回键收起进度条：不再开始。
            guard !Task.isCancelled, viewState.isPresentingProgress else { return }

            didBeginScanByHolding = true
            scanHoldTask = nil
            viewState.beginScan(direction)
        }
    }

    /// 松开左右键：按住开始的快退快进继续进行；快退快进中点一下换档或掉头；其余情况跳 10 秒。
    private func endSeekingPress(_ direction: ViewState.Scan.Direction) {
        let beganByHolding = didBeginScanByHolding
        resetSeekingPress()

        if beganByHolding {
            return
        }

        if viewState.scan != nil {
            viewState.stepScan(direction)
        } else {
            jump(direction)
        }
    }

    func resetSeekingPress() {
        scanHoldTask?.cancel()
        scanHoldTask = nil
        didBeginScanByHolding = false
        seekingPress = nil
    }
}
