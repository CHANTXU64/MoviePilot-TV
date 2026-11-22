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
//   带 `\pos` 的长句在画面内换行，会越出画面时整块挪回画面里。排版拆成 `TextSubtitleLayer`，样式和字号由外面给。
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

    var body: some View {
        TextSubtitleLayer(
            snapshot: snapshot,
            videoLayout: videoLayout,
            style: selectedCaptionStyle,
            basePointSize: basePointSize
        )
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
}

/// 字幕在画面上的排版。字幕样式和基准字号由调用方给（播放界面用系统字幕样式）。
struct TextSubtitleLayer: View {

    let snapshot: SubtitleSnapshot
    let videoLayout: VideoPlayer.VideoLayout
    let style: CaptionStyle
    let basePointSize: CGFloat

    /// 没有锚点的文字字幕按对齐分组，同组的叠在一起。
    private var anchoredGroups: [(alignment: Int, cues: [SubtitleSnapshot.TextCue])] {
        let unplaced = snapshot.texts.filter { $0.position == nil }
        let alignments = unplaced.map { SubtitleAnchor.alignment($0.alignment) }
        return Array(Set(alignments)).sorted().map { alignment in
            (alignment, unplaced.filter { SubtitleAnchor.alignment($0.alignment) == alignment })
        }
    }

    var body: some View {
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
                            caption(cue, pointSize: pointSize)
                        }
                    }
                    .frame(maxWidth: frame.width * SubtitleAnchor.maximumWidthFraction)
                    .padding(.vertical, frame.height * 0.05)
                    .frame(width: frame.width, height: frame.height, alignment: SubtitleAnchor.frameAlignment(group.alignment))
                    .position(x: frame.midX, y: frame.midY)
                }

                ForEach(snapshot.texts.filter { $0.position != nil }) { cue in
                    if let position = cue.position {
                        PositionedCaptionLayout(
                            anchor: CGPoint(x: frame.minX + position.x * frame.width, y: frame.minY + position.y * frame.height),
                            alignment: cue.alignment,
                            videoFrame: frame
                        ) {
                            caption(cue, pointSize: pointSize)
                        }
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
    }

    private func caption(_ cue: SubtitleSnapshot.TextCue, pointSize: CGFloat) -> some View {
        CaptionText(SubtitleAnchor.text(cue.spans), baseSize: basePointSize, style: style)
            .lineSpacing(pointSize * 0.12)
            .multilineTextAlignment(SubtitleAnchor.textAlignment(cue.alignment))
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// 带 `\pos` 的一句字幕：占满整个字幕层，按 `SubtitleAnchor.positionedWidth` 排版宽度换行，
/// 再按 `SubtitleAnchor.positionedOrigin` 放到锚点处。
private struct PositionedCaptionLayout: Layout {

    let anchor: CGPoint
    let alignment: Int?
    let videoFrame: CGRect

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let caption = ProposedViewSize(
            width: SubtitleAnchor.positionedWidth(alignment: alignment, anchorX: anchor.x, in: videoFrame),
            height: nil
        )
        for subview in subviews {
            let origin = SubtitleAnchor.positionedOrigin(
                size: subview.sizeThatFits(caption),
                anchor: anchor,
                alignment: alignment,
                in: videoFrame
            )
            subview.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), anchor: .topLeading, proposal: caption)
        }
    }
}

/// ASS 小键盘对齐（1 左下 … 9 右上）换成 SwiftUI 的对齐方式；没给对齐时按 2（底部居中）。
nonisolated enum SubtitleAnchor {
    /// 字幕最宽占画面宽度的比例。
    static let maximumWidthFraction: CGFloat = 0.9
    /// 带 `\pos` 的字幕锚点贴近画面边缘时，至少按这个比例的画面宽度换行。
    static let minimumPositionedWidthFraction: CGFloat = 1.0 / 3

    static func alignment(_ value: Int?) -> Int {
        guard let value, (1 ... 9).contains(value) else { return 2 }
        return value
    }

    /// 带 `\pos` 的字幕换行宽度。不超过画面宽度的 90%（与普通字幕相同）。
    /// 也不超过锚点到画面边缘的距离：左对齐量到右边缘，右对齐量到左边缘，居中按离得近的一边算两倍。
    /// 锚点贴着边缘时至少留画面宽度的 1/3，否则一句话会被挤成一列。
    static func positionedWidth(alignment value: Int?, anchorX: CGFloat, in frame: CGRect) -> CGFloat {
        let room: CGFloat
        switch alignment(value) % 3 {
        case 1: room = frame.maxX - anchorX
        case 0: room = anchorX - frame.minX
        default: room = 2 * min(anchorX - frame.minX, frame.maxX - anchorX)
        }
        return max(min(frame.width * maximumWidthFraction, room), frame.width * minimumPositionedWidthFraction)
    }

    /// 排好的字幕块的左上角：锚点按 ASS 对齐落在块上（`\an2` 是底边中点，`\an7` 是左上角）。
    /// 会越出画面时整块挪回画面里，整句都看得见；块比画面还大时贴画面左上角。
    static func positionedOrigin(size: CGSize, anchor: CGPoint, alignment value: Int?, in frame: CGRect) -> CGPoint {
        let value = alignment(value)
        let x: CGFloat
        switch value % 3 {
        case 1: x = anchor.x
        case 0: x = anchor.x - size.width
        default: x = anchor.x - size.width / 2
        }
        let y: CGFloat = value >= 7 ? anchor.y : value >= 4 ? anchor.y - size.height / 2 : anchor.y - size.height
        return CGPoint(
            x: max(frame.minX, min(x, frame.maxX - size.width)),
            y: max(frame.minY, min(y, frame.maxY - size.height))
        )
    }

    /// 字幕块在画面里的位置。
    static func frameAlignment(_ value: Int?) -> Alignment {
        let value = alignment(value)
        let vertical: VerticalAlignment = value >= 7 ? .top : value >= 4 ? .center : .bottom
        let horizontal: HorizontalAlignment = value % 3 == 1 ? .leading : value % 3 == 0 ? .trailing : .center
        return Alignment(horizontal: horizontal, vertical: vertical)
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
