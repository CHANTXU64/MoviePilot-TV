import SwiftUI
import XCTest

@testable import MoviePilot_TV

/// 海报卡、人物卡、剧照卡共用的标题聚焦布局（`posterCardTitleLayout`）：把两列放进同一个窗口按实际排版量，
/// 标题 frame 减去所在列原点，逐帧比对。一列用共享修饰符、另一列用抽取前各卡手写的那条链，确认抽取没改外观；
/// 也用共享修饰符自己比聚焦前后，确认居中、加宽和下移这三条契约。
@MainActor
final class PosterCardTitleLayoutTests: XCTestCase {
  fileprivate final class FrameBox {
    var frame: CGRect = .null
  }

  /// 三种卡片各自的图片尺寸与图片—标题间距。
  private var cardLayouts: [(name: String, size: CGSize, spacing: CGFloat)] {
    [
      ("海报卡", MediaCard.defaultPosterSize, 10),
      ("人物卡", PersonCard.imageSize, 10),
      ("剧照卡", ContinueWatchingCard.stillSize, ContinueWatchingCard.titleSpacing),
    ]
  }

  func testSharedTitleLayoutMatchesTheHandWrittenChain() async throws {
    for card in cardLayouts {
      for isFocused in [false, true] {
        for title in ["短标题", String(repeating: "很长的标题", count: 12)] {
          let frames = try await measurePair(
            imageSize: card.size, stackSpacing: card.spacing, title: title,
            left: (shared: true, focused: isFocused), right: (shared: false, focused: isFocused))
          XCTAssertEqual(
            frames.left.origin.x, frames.right.origin.x, accuracy: 0.5,
            "\(card.name) focused=\(isFocused) title=\(title.count)字：标题横向位置变了")
          XCTAssertEqual(
            frames.left.origin.y, frames.right.origin.y, accuracy: 0.5,
            "\(card.name) focused=\(isFocused) title=\(title.count)字：标题纵向位置变了")
          XCTAssertEqual(
            frames.left.size.width, frames.right.size.width, accuracy: 0.5,
            "\(card.name) focused=\(isFocused) title=\(title.count)字：标题可用宽度变了")
          XCTAssertEqual(
            frames.left.size.height, frames.right.size.height, accuracy: 0.5,
            "\(card.name) focused=\(isFocused) title=\(title.count)字：标题高度变了")
        }
      }
    }
  }

  /// 聚焦时标题仍居中、可用宽度跟图片一起向左右各多出 `focusedGrowth`、并跟着放大后的图片底边下移。
  /// 内容用填满提议宽度的色块而不是文本：截断文本量到的是实际绘制宽度（按整字符量化，比可用宽度少几 pt），
  /// 量不出「可用宽度」这条契约。真实标题的外观由上面那条等价用例覆盖。
  func testFocusedTitleStaysCenteredWidensAndMovesDown() async throws {
    for card in cardLayouts {
      let frames = try await measurePair(
        imageSize: card.size, stackSpacing: card.spacing, stretchy: true,
        left: (shared: true, focused: true), right: (shared: true, focused: false))
      let expectedOffset = PosterCardFocus.focusedTextOffset(
        forImageSize: card.size, stackSpacing: card.spacing)

      XCTAssertEqual(
        frames.right.width, card.size.width, accuracy: 0.5, "\(card.name)：未聚焦时可用宽度就是卡片宽度")
      XCTAssertEqual(
        frames.left.midX, card.size.width / 2, accuracy: 0.5, "\(card.name)：聚焦时标题要居中")
      XCTAssertEqual(
        frames.right.midX, card.size.width / 2, accuracy: 0.5, "\(card.name)：未聚焦时标题要居中")
      XCTAssertEqual(
        frames.left.width - frames.right.width, PosterCardFocus.focusedTextExtraWidth, accuracy: 0.5,
        "\(card.name)：聚焦时可用宽度跟图片一起加宽（聚焦 \(frames.left.width)、未聚焦 \(frames.right.width)、卡片 \(card.size.width)）")
      XCTAssertEqual(
        frames.left.minY - frames.right.minY, expectedOffset, accuracy: 0.5,
        "\(card.name)：聚焦时标题跟着剧照下移")
      XCTAssertGreaterThan(expectedOffset, 0, "\(card.name)：间距取大了标题就不动了")
    }
  }

  /// 两列并排放在同一个窗口里量：标题 frame 减去所在列的原点，消掉两列位置差。
  private func measurePair(
    imageSize: CGSize, stackSpacing: CGFloat, title: String = "", stretchy: Bool = false,
    left: (shared: Bool, focused: Bool), right: (shared: Bool, focused: Bool)
  ) async throws -> (left: CGRect, right: CGRect) {
    let boxes = (left: FrameBox(), right: FrameBox(), leftColumn: FrameBox(), rightColumn: FrameBox())
    let host = UIHostingController(
      rootView: TitleLayoutPair(
        imageSize: imageSize, stackSpacing: stackSpacing, title: title, stretchy: stretchy,
        left: left, right: right, boxes: boxes))
    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
    let previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
    let window = UIWindow(windowScene: scene)
    window.rootViewController = host
    window.makeKeyAndVisible()
    defer {
      window.isHidden = true
      window.rootViewController = nil
      previousKeyWindow?.makeKey()
    }
    try await Task.sleep(for: .milliseconds(300))
    host.view.layoutIfNeeded()

    let leftColumn = try XCTUnwrap(boxes.leftColumn.frame.nonNull)
    let rightColumn = try XCTUnwrap(boxes.rightColumn.frame.nonNull)
    let leftTitle = try XCTUnwrap(boxes.left.frame.nonNull)
    let rightTitle = try XCTUnwrap(boxes.right.frame.nonNull)
    return (leftTitle.offsetBy(dx: -leftColumn.minX, dy: -leftColumn.minY),
            rightTitle.offsetBy(dx: -rightColumn.minX, dy: -rightColumn.minY))
  }
}

private struct TitleLayoutPair: View {
  let imageSize: CGSize
  let stackSpacing: CGFloat
  let title: String
  let stretchy: Bool
  let left: (shared: Bool, focused: Bool)
  let right: (shared: Bool, focused: Bool)
  let boxes: (left: PosterCardTitleLayoutTests.FrameBox, right: PosterCardTitleLayoutTests.FrameBox,
              leftColumn: PosterCardTitleLayoutTests.FrameBox, rightColumn: PosterCardTitleLayoutTests.FrameBox)

  var body: some View {
    HStack(spacing: 200) {
      column(left, titleBox: boxes.left, columnBox: boxes.leftColumn)
      column(right, titleBox: boxes.right, columnBox: boxes.rightColumn)
    }
    .padding(60)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private func column(
    _ variant: (shared: Bool, focused: Bool),
    titleBox: PosterCardTitleLayoutTests.FrameBox, columnBox: PosterCardTitleLayoutTests.FrameBox
  ) -> some View {
    VStack(spacing: stackSpacing) {
      Color.gray.frame(width: imageSize.width, height: imageSize.height)
      titleBlock(variant, box: titleBox)
    }
    .frame(width: imageSize.width)
    .background(FrameProbe(box: columnBox))
  }

  /// 海报卡/人物卡是标题加副标题的 VStack，剧照卡只有一行标题；这里按海报卡那种形状量。
  @ViewBuilder
  private func titleContent(_ variant: (shared: Bool, focused: Bool)) -> some View {
    if stretchy {
      Color.clear.frame(height: 20)
    } else {
      VStack {
        Text(title)
          .font(.caption)
          .foregroundStyle(variant.focused ? .primary : .secondary)
      }
    }
  }

  @ViewBuilder
  private func titleBlock(
    _ variant: (shared: Bool, focused: Bool), box: PosterCardTitleLayoutTests.FrameBox
  ) -> some View {
    let content = titleContent(variant)
      .lineLimit(1)
      .compositingGroup()
      .background(FrameProbe(box: box))

    if variant.shared {
      content.posterCardTitleLayout(
        isFocused: variant.focused, width: imageSize.width, imageSize: imageSize,
        stackSpacing: stackSpacing)
    } else {
      // 抽取前 MediaCard / PersonCard 里手写的那条链。
      VStack(spacing: 4) {
        content
          .frame(
            maxWidth: variant.focused
              ? imageSize.width + PosterCardFocus.focusedTextExtraWidth : imageSize.width,
            alignment: .center)
      }
      .frame(width: imageSize.width + PosterCardFocus.focusedTextExtraWidth)
      .padding(.horizontal, -PosterCardFocus.focusedTextExtraWidth / 2)
      .offset(
        y: variant.focused
          ? PosterCardFocus.focusedTextOffset(forImageSize: imageSize, stackSpacing: stackSpacing)
          : 0)
    }
  }
}

private struct FrameProbe: View {
  let box: PosterCardTitleLayoutTests.FrameBox

  var body: some View {
    GeometryReader { proxy in
      Color.clear
        .onAppear { box.frame = proxy.frame(in: .global) }
        .onChange(of: proxy.frame(in: .global)) { _, newValue in box.frame = newValue }
    }
  }
}

extension CGRect {
  fileprivate var nonNull: CGRect? { isNull ? nil : self }
}