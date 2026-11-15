//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//
// 本文件改自 Swiftfin：Shared/Views/VideoPlayer/Components/TextSubtitleOverlay.swift
// Modifications for MoviePilot-TV are also licensed under MPL-2.0.
//
// 修改：
// - Swiftfin 设置项 `captionProfileID` 换成 `@AppStorage`（键 `swiftfin.captionProfileID`，默认空字符串，与原默认值相同）。
// - 字幕来自 AetherEngine（`SubtitleSnapshot`），布局不再交给 MPVUI 的 `MPVTextSubtitleOverlay`：
//   文字字幕默认放在画面底部居中，ASS 给了对齐或 `\pos` 锚点时按它放；PGS 等图片字幕按引擎给的位置画在画面上。
//   文字的颜色、粗斜体、下划线和删除线照片源，字体和大小跟系统字幕样式；ASS 的特效（移动、渐变、卡拉 OK）不绘制。
//

import MediaAccessibilityKit
import SwiftUI

struct TextSubtitleOverlay: View {

    @Environment(\.scenePhase)
    private var scenePhase

    let snapshot: SubtitleSnapshot
    let videoLayout: VideoPlayer.VideoLayout
    var reportCaptions: (@MainActor ([String]) -> Void)? = TextSubtitleReporting.reportToSystem

    var body: some View {
        TextSubtitleOverlayContent(snapshot: snapshot, videoLayout: videoLayout)
            .modifier(
                TextSubtitleReporting(
                    snapshot: snapshot,
                    isVisible: scenePhase == .active,
                    reportCaptions: reportCaptions
                )
            )
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(snapshot.text)
            .accessibilityHidden(snapshot.texts.isEmpty)
    }
}

private struct TextSubtitleOverlayContent: View {

    @AppStorage("swiftfin.captionProfileID")
    private var profileID: String = ""

    @Environment(\.scenePhase)
    private var scenePhase

    @AdaptiveLayout
    private var viewLayout

    @State
    private var captionStyle = CaptionStyle.current
    @State
    private var profiles = CaptionProfile.availableForCurrentPlatform

    let snapshot: SubtitleSnapshot
    let videoLayout: VideoPlayer.VideoLayout

    private var basePointSize: CGFloat {
        viewLayout.value(standard: 21, large: 36)
    }

    private var selectedCaptionStyle: CaptionStyle {
        profiles.first(property: \.id, equalTo: profileID)?.style ?? captionStyle
    }

    /// 没有锚点的文字字幕按对齐分组，同组的叠在一起。
    private var anchoredGroups: [(alignment: Int, cues: [SubtitleSnapshot.TextCue])] {
        let unplaced = snapshot.texts.filter { $0.position == nil }
        let alignments = unplaced.map { SubtitleAnchor.alignment($0.alignment) }
        return Array(Set(alignments)).sorted().map { alignment in
            (alignment, unplaced.filter { SubtitleAnchor.alignment($0.alignment) == alignment })
        }
    }

    var body: some View {
        let style = selectedCaptionStyle
        let pointSize = basePointSize * style.text.sizeScale.resolved(contentValue: nil)

        GeometryReader { geometry in
            let frame = videoLayout.videoFrame(in: CGRect(origin: .zero, size: geometry.size))

            ZStack(alignment: .topLeading) {
                ForEach(snapshot.images) { cue in
                    Image(decorative: cue.image, scale: 1)
                        .resizable()
                        .frame(width: cue.frame.width * frame.width, height: cue.frame.height * frame.height)
                        .position(
                            x: frame.minX + cue.frame.midX * frame.width,
                            y: frame.minY + cue.frame.midY * frame.height
                        )
                }

                ForEach(anchoredGroups, id: \.alignment) { group in
                    VStack(spacing: pointSize * 0.25) {
                        ForEach(group.cues) { cue in
                            caption(cue, style: style, pointSize: pointSize)
                        }
                    }
                    .frame(maxWidth: frame.width * 0.9)
                    .padding(.vertical, frame.height * 0.05)
                    .frame(width: frame.width, height: frame.height, alignment: SubtitleAnchor.frameAlignment(group.alignment))
                    .position(x: frame.midX, y: frame.midY)
                }

                ForEach(snapshot.texts.filter { $0.position != nil }) { cue in
                    if let position = cue.position {
                        Color.clear
                            .frame(width: 0, height: 0)
                            .overlay(alignment: SubtitleAnchor.pointAlignment(cue.alignment)) {
                                caption(cue, style: style, pointSize: pointSize)
                                    .fixedSize()
                            }
                            .position(x: frame.minX + position.x * frame.width, y: frame.minY + position.y * frame.height)
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else {
                return
            }

            for await _ in CaptionPreferences.updates {
                captionStyle = .current
                profiles = CaptionProfile.availableForCurrentPlatform
            }
        }
    }

    private func caption(_ cue: SubtitleSnapshot.TextCue, style: CaptionStyle, pointSize: CGFloat) -> some View {
        CaptionText(SubtitleAnchor.text(cue.spans), baseSize: basePointSize, style: style)
            .lineSpacing(pointSize * 0.12)
            .multilineTextAlignment(SubtitleAnchor.textAlignment(cue.alignment))
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// ASS 小键盘对齐（1 左下 … 9 右上）换成 SwiftUI 的对齐方式；没给对齐时按 2（底部居中）。
enum SubtitleAnchor {
    static func alignment(_ value: Int?) -> Int {
        guard let value, (1 ... 9).contains(value) else { return 2 }
        return value
    }

    /// 字幕块在画面里的位置。
    static func frameAlignment(_ value: Int?) -> Alignment {
        let value = alignment(value)
        let vertical: VerticalAlignment = value >= 7 ? .top : value >= 4 ? .center : .bottom
        let horizontal: HorizontalAlignment = value % 3 == 1 ? .leading : value % 3 == 0 ? .trailing : .center
        return Alignment(horizontal: horizontal, vertical: vertical)
    }

    /// 有锚点时，锚点落在字幕块的哪个位置：`\an2` 是底边中点，`\an7` 是左上角。
    static func pointAlignment(_ value: Int?) -> Alignment {
        frameAlignment(value)
    }

    static func textAlignment(_ value: Int?) -> TextAlignment {
        switch alignment(value) % 3 {
        case 1: .leading
        case 0: .trailing
        default: .center
        }
    }

    /// 片源给的颜色、粗斜体、下划线和删除线。
    static func text(_ spans: [SubtitleSpan]) -> Text {
        spans.reduce(Text(verbatim: "")) { result, span in
            var text = Text(verbatim: span.text)
            if span.isBold { text = text.bold() }
            if span.isItalic { text = text.italic() }
            if span.isUnderlined { text = text.underline() }
            if span.isStruckThrough { text = text.strikethrough() }
            if let color = span.color {
                text = text.foregroundStyle(
                    Color(red: Double(color.red) / 255, green: Double(color.green) / 255, blue: Double(color.blue) / 255))
            }
            return result + text
        }
    }
}
