//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//
// 本文件改自 Swiftfin：Shared/Views/VideoPlayer/Components/TextSubtitleReporting.swift
// Modifications for MoviePilot-TV are also licensed under MPL-2.0.
//
// 修改：字幕来自 AetherEngine（`SubtitleSnapshot`），没有第二字幕，按显示顺序上报文字字幕；图片字幕没有文字，不上报。
// 析构显式标为 `nonisolated`（tvOS 18.4–26.2 上，隔离析构在主线程、Task 之外执行会崩溃）。
//

import MediaAccessibilityKit
import SwiftUI

struct TextSubtitleReporting: ViewModifier {

    // Class to prevent view evaluations
    @MainActor
    private final class CaptionReportState {

        // 显式非隔离析构，避开 tvOS 18 的隔离析构回部署崩溃。
        nonisolated deinit {}

        var isPresented = false
        var lastCaptions: [String]?
    }

    @State
    private var report = CaptionReportState()

    let snapshot: SubtitleSnapshot?
    let isVisible: Bool
    var reportCaptions: (@MainActor ([String]) -> Void)? = reportToSystem

    static func reportToSystem(_ captions: [String]) {
        if captions.isEmpty {
            CaptionDisplayReporter.clear()
        } else {
            CaptionDisplayReporter.report(captions)
        }
    }

    private var captionTexts: [String] {
        (snapshot?.texts ?? [])
            .map(\.text)
            .compacted(using: \.nilIfBlank)
    }

    private func reportVisibleCaptions() {
        guard let reportCaptions else { return }

        let captions = report.isPresented && isVisible ? captionTexts : []
        guard captions != report.lastCaptions else { return }

        reportCaptions(captions)
        report.lastCaptions = captions
    }

    func body(content: Content) -> some View {
        content
            .onAppear {
                report.isPresented = true
                reportVisibleCaptions()
            }
            .onChange(of: captionTexts) {
                reportVisibleCaptions()
            }
            .onChange(of: isVisible) {
                reportVisibleCaptions()
            }
            .onDisappear {
                report.isPresented = false
                reportVisibleCaptions()
            }
    }
}
