import CoreGraphics
import MediaAccessibilityKit
import SwiftUI
import XCTest

@testable import MoviePilot_TV

/// 带 ASS `\pos` 的文字字幕：按播放界面的字幕排版（`TextSubtitleLayer`）渲染到 1920×1080 的透明画布，
/// 用画出来的像素范围检查换行、锚点和是否越出画面。字幕窗口在测试样式里是不透明的直角黑底，
/// 画出来的范围就是整块字幕（含内边距）。
@MainActor
final class PositionedSubtitleLayoutTests: XCTestCase {

  private static let screen = CGSize(width: 1920, height: 1080)
  private static let picture = CGRect(origin: .zero, size: screen)
  /// tvOS 播放界面的基准字号（`viewLayout.value(standard: 21, large: 36)`，tvOS 是 large）。
  private static let basePointSize: CGFloat = 36
  /// 像素取整、圆角抗锯齿的余量。
  private static let tolerance: CGFloat = 2
  private static let maximumWidth = screen.width * SubtitleAnchor.maximumWidthFraction
  private static let minimumWidth = screen.width * SubtitleAnchor.minimumPositionedWidthFraction

  private static let longChinese =
    "这是一句没有手动换行的很长很长的中文对白，用来检查带定位的字幕会不会在画面里自动换行，而不是一直往右边延伸到画面外面去"
  private static let longEnglish =
    "This is a very long line of English dialogue without any manual line breaks, written to check that a positioned subtitle wraps inside the picture instead of running off the screen"
  private static let bilingual =
    "我们必须在天亮之前离开这座城市，否则所有人都会被困在这里，再也没有人能来救我们\nWe have to leave this city before dawn, or everyone here will be trapped with no way out and nobody coming to help us"
  private static let shortText = "标识"

  // MARK: 排版规则

  func testPositionedWidthFollowsRoomTowardsTheTextDirection() {
    let picture = Self.picture
    XCTAssertEqual(
      SubtitleAnchor.positionedWidth(alignment: 2, anchorX: 960, in: picture), Self.maximumWidth, "画面正中与普通字幕同宽")
    XCTAssertEqual(
      SubtitleAnchor.positionedWidth(alignment: 1, anchorX: 1000, in: picture), 920, "左对齐量到右边缘")
    XCTAssertEqual(
      SubtitleAnchor.positionedWidth(alignment: 9, anchorX: 1000, in: picture), 1000, "右对齐量到左边缘")
    XCTAssertEqual(
      SubtitleAnchor.positionedWidth(alignment: 8, anchorX: 400, in: picture), 800, "居中按离得近的一边算两倍")
    XCTAssertEqual(
      SubtitleAnchor.positionedWidth(alignment: 7, anchorX: 1850, in: picture), Self.minimumWidth, "贴着右边缘也至少留 1/3")
    XCTAssertEqual(
      SubtitleAnchor.positionedWidth(alignment: 3, anchorX: -50, in: picture), Self.minimumWidth, "锚点在画面外")
  }

  func testPositionedOriginKeepsTheAnchorUnlessTheBlockWouldLeaveThePicture() {
    let picture = Self.picture
    let size = CGSize(width: 200, height: 50)
    XCTAssertEqual(
      SubtitleAnchor.positionedOrigin(size: size, anchor: CGPoint(x: 960, y: 1000), alignment: 2, in: picture),
      CGPoint(x: 860, y: 950), "底边中点落在锚点")
    XCTAssertEqual(
      SubtitleAnchor.positionedOrigin(size: size, anchor: CGPoint(x: 300, y: 200), alignment: 7, in: picture),
      CGPoint(x: 300, y: 200), "左上角落在锚点")
    XCTAssertEqual(
      SubtitleAnchor.positionedOrigin(size: size, anchor: CGPoint(x: 1800, y: 600), alignment: 6, in: picture),
      CGPoint(x: 1600, y: 575), "右边中点落在锚点")
    XCTAssertEqual(
      SubtitleAnchor.positionedOrigin(size: size, anchor: CGPoint(x: 1850, y: 10), alignment: 7, in: picture),
      CGPoint(x: 1720, y: 10), "越出右边缘时整块挪回")
    XCTAssertEqual(
      SubtitleAnchor.positionedOrigin(size: size, anchor: CGPoint(x: 50, y: 20), alignment: 2, in: picture),
      CGPoint(x: 0, y: 0), "越出左上时贴边")
    XCTAssertEqual(
      SubtitleAnchor.positionedOrigin(
        size: CGSize(width: 2400, height: 1200), anchor: CGPoint(x: 960, y: 540), alignment: 5, in: picture),
      CGPoint(x: 0, y: 0), "比画面还大时贴左上角")
  }

  // MARK: 渲染

  /// 短字幕按自身宽度排，锚点照 ASS 对齐落在字幕块上。
  func testShortPositionedSubtitlesLandOnTheirAnchors() throws {
    let bottomLeft = try render(Self.shortText, alignment: 1, at: CGPoint(x: 200, y: 900))
    assertNear(bottomLeft.minX, 200, "\\an1 左边")
    assertNear(bottomLeft.maxY, 900, "\\an1 底边")

    let bottomCenter = try render(Self.shortText, alignment: 2, at: CGPoint(x: 960, y: 1000))
    assertNear(bottomCenter.midX, 960, "\\an2 水平居中")
    assertNear(bottomCenter.maxY, 1000, "\\an2 底边")

    let bottomRight = try render(Self.shortText, alignment: 3, at: CGPoint(x: 1700, y: 900))
    assertNear(bottomRight.maxX, 1700, "\\an3 右边")
    assertNear(bottomRight.maxY, 900, "\\an3 底边")

    let middle = try render(Self.shortText, alignment: 5, at: CGPoint(x: 700, y: 540))
    assertNear(middle.midX, 700, "\\an5 水平居中")
    assertNear(middle.midY, 540, "\\an5 垂直居中")

    let topLeft = try render(Self.shortText, alignment: 7, at: CGPoint(x: 200, y: 150))
    assertNear(topLeft.minX, 200, "\\an7 左边")
    assertNear(topLeft.minY, 150, "\\an7 上边")

    let topRight = try render(Self.shortText, alignment: 9, at: CGPoint(x: 1700, y: 150))
    assertNear(topRight.maxX, 1700, "\\an9 右边")
    assertNear(topRight.minY, 150, "\\an9 上边")

    // 贴近边缘但放得下的短字幕不挪。
    let nearRightEdge = try render(Self.shortText, alignment: 9, at: CGPoint(x: 1915, y: 10))
    assertNear(nearRightEdge.maxX, 1915, "贴近右上角放得下，不挪")
    assertNear(nearRightEdge.minY, 10)
    let nearLeftEdge = try render(Self.shortText, alignment: 1, at: CGPoint(x: 5, y: 1075))
    assertNear(nearLeftEdge.minX, 5, "贴近左下角放得下，不挪")
    assertNear(nearLeftEdge.maxY, 1075)
  }

  /// 长中文、长英文和双语字幕在左、中、右锚点：在画面内换行，宽度不超过画面的 90%，锚点仍在原处。
  func testLongPositionedSubtitlesWrapInsideThePictureAtLeftCenterAndRightAnchors() throws {
    let lineHeight = try render(Self.shortText, alignment: 2, at: CGPoint(x: 960, y: 1040)).height
    for (name, text) in [("中文", Self.longChinese), ("英文", Self.longEnglish), ("双语", Self.bilingual)] {
      let center = try render(text, alignment: 2, at: CGPoint(x: 960, y: 1040))
      assertWrappedInsidePicture(center, lineHeight: lineHeight, maximumWidth: Self.maximumWidth, "\(name) \\an2")
      assertNear(center.midX, 960, "\(name) \\an2 仍以锚点居中")
      assertNear(center.maxY, 1040, "\(name) \\an2 底边仍在锚点")

      let left = try render(text, alignment: 1, at: CGPoint(x: 100, y: 1040))
      assertWrappedInsidePicture(left, lineHeight: lineHeight, maximumWidth: Self.maximumWidth, "\(name) \\an1")
      assertNear(left.minX, 100, "\(name) \\an1 左边仍在锚点")
      assertNear(left.maxY, 1040, "\(name) \\an1 底边仍在锚点")

      let right = try render(text, alignment: 9, at: CGPoint(x: 1820, y: 60))
      assertWrappedInsidePicture(right, lineHeight: lineHeight, maximumWidth: Self.maximumWidth, "\(name) \\an9")
      assertNear(right.maxX, 1820, "\(name) \\an9 右边仍在锚点")
      assertNear(right.minY, 60, "\(name) \\an9 上边仍在锚点")
    }
  }

  /// 锚点贴近左右边缘的长字幕：至少按画面宽度的 1/3 换行，整块留在画面内。
  func testLongPositionedSubtitlesNearTheLeftAndRightEdgesStayInsideThePicture() throws {
    let lineHeight = try render(Self.shortText, alignment: 2, at: CGPoint(x: 960, y: 1040)).height

    let leftAlignedAtRightEdge = try render(Self.longChinese, alignment: 7, at: CGPoint(x: 1850, y: 80))
    assertWrappedInsidePicture(
      leftAlignedAtRightEdge, lineHeight: lineHeight, maximumWidth: Self.minimumWidth, "左对齐、锚点贴右边缘")
    assertNear(leftAlignedAtRightEdge.maxX, Self.screen.width, "挪回到右边缘以内")
    assertNear(leftAlignedAtRightEdge.minY, 80, "上边仍在锚点")

    let rightAlignedAtLeftEdge = try render(Self.longEnglish, alignment: 3, at: CGPoint(x: 60, y: 1000))
    assertWrappedInsidePicture(
      rightAlignedAtLeftEdge, lineHeight: lineHeight, maximumWidth: Self.minimumWidth, "右对齐、锚点贴左边缘")
    assertNear(rightAlignedAtLeftEdge.minX, 0, "挪回到左边缘以内")
    assertNear(rightAlignedAtLeftEdge.maxY, 1000, "底边仍在锚点")

    let centeredAtLeftEdge = try render(Self.bilingual, alignment: 2, at: CGPoint(x: 30, y: 1040))
    assertWrappedInsidePicture(
      centeredAtLeftEdge, lineHeight: lineHeight, maximumWidth: Self.minimumWidth, "居中、锚点贴左边缘")
    assertNear(centeredAtLeftEdge.minX, 0)

    let centeredAtRightEdge = try render(Self.bilingual, alignment: 8, at: CGPoint(x: 1890, y: 20))
    assertWrappedInsidePicture(
      centeredAtRightEdge, lineHeight: lineHeight, maximumWidth: Self.minimumWidth, "居中、锚点贴右边缘")
    assertNear(centeredAtRightEdge.maxX, Self.screen.width)
    assertNear(centeredAtRightEdge.minY, 20, "上边仍在锚点")

    let leftAlignedAtLeftEdge = try render(Self.longEnglish, alignment: 1, at: CGPoint(x: 40, y: 1000))
    assertWrappedInsidePicture(
      leftAlignedAtLeftEdge, lineHeight: lineHeight, maximumWidth: Self.maximumWidth, "左对齐、锚点贴左边缘")
    assertNear(leftAlignedAtLeftEdge.minX, 40, "往右排得下，左边仍在锚点")
  }

  /// 系统字幕样式调到 2 倍字号：长字幕照样换行，整块留在画面内。
  /// （大字号的长句贴着边缘时按 1/3 画面宽换行会高过画面，那是放不下，不在这里检查。）
  func testLargeCaptionStyleKeepsPositionedSubtitlesInsideThePicture() throws {
    let scale: CGFloat = 2
    let lineHeight = try render(Self.shortText, alignment: 2, at: CGPoint(x: 960, y: 1040), sizeScale: scale).height
    for (name, text) in [("中文", Self.longChinese), ("英文", Self.longEnglish), ("双语", Self.bilingual)] {
      let center = try render(text, alignment: 2, at: CGPoint(x: 960, y: 1040), sizeScale: scale)
      assertWrappedInsidePicture(center, lineHeight: lineHeight, maximumWidth: Self.maximumWidth, "大字幕 \(name) \\an2")
      assertNear(center.midX, 960, "大字幕 \(name) \\an2 仍以锚点居中")

      // 左对齐的锚点在画面中间偏左：按到右边缘的 1020 点换行，块底离画面底边留足余量。
      let topLeft = try render(text, alignment: 7, at: CGPoint(x: 900, y: 40), sizeScale: scale)
      assertWrappedInsidePicture(topLeft, lineHeight: lineHeight, maximumWidth: 1020, "大字幕 \(name) \\an7")
      XCTAssertLessThan(topLeft.maxY, Self.screen.height - lineHeight, "大字幕 \(name) \\an7 没被挤到底边")
      assertNear(topLeft.minX, 900, "大字幕 \(name) \\an7 左边仍在锚点")
      assertNear(topLeft.minY, 40, "大字幕 \(name) \\an7 上边仍在锚点")

      let bottomRight = try render(text, alignment: 3, at: CGPoint(x: 1880, y: 1060), sizeScale: scale)
      assertWrappedInsidePicture(bottomRight, lineHeight: lineHeight, maximumWidth: Self.maximumWidth, "大字幕 \(name) \\an3")
      assertNear(bottomRight.maxX, 1880, "大字幕 \(name) \\an3 右边仍在锚点")
    }
  }

  /// 2.39:1 的片子在 16:9 屏幕上下有黑边：锚点按画面（不是屏幕）换算，越出画面时挪回画面内，不进黑边。
  func testPositionedSubtitlesInALetterboxedPictureFollowThePictureNotTheScreen() throws {
    let video = CGSize(width: 1920, height: 804)
    let picture = CGRect(x: 0, y: 138, width: 1920, height: 804)
    let lineHeight = try render(Self.shortText, alignment: 2, at: CGPoint(x: 0.5, y: 1), in: video).height

    let top = try render(Self.shortText, alignment: 8, at: CGPoint(x: 0.5, y: 0), in: video)
    assertNear(top.minY, picture.minY, "\\an8 贴画面上边，不是屏幕上边")
    assertNear(top.midX, picture.midX)

    let bottom = try render(Self.longEnglish, alignment: 2, at: CGPoint(x: 0.5, y: 1), in: video)
    XCTAssertGreaterThan(bottom.height, lineHeight * 1.5, "应换行")
    assertNear(bottom.maxY, picture.maxY, "\\an2 贴画面下边")

    let corner = try render(Self.longChinese, alignment: 7, at: CGPoint(x: 0.97, y: 0.95), in: video)
    XCTAssertTrue(
      picture.insetBy(dx: -Self.tolerance, dy: -Self.tolerance).contains(corner), "挪回画面内，不进黑边：\(corner)")
  }

  // MARK: 辅助

  private func assertNear(
    _ actual: CGFloat, _ expected: CGFloat, _ message: String = "", file: StaticString = #filePath, line: UInt = #line
  ) {
    XCTAssertEqual(actual, expected, accuracy: Self.tolerance, message, file: file, line: line)
  }

  /// 换了行（高于一行）、不超过 `maximumWidth`、整块在画面内。
  private func assertWrappedInsidePicture(
    _ bounds: CGRect, lineHeight: CGFloat, maximumWidth: CGFloat, _ message: String,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    XCTAssertGreaterThan(bounds.height, lineHeight * 1.5, "\(message)：应换行", file: file, line: line)
    XCTAssertLessThanOrEqual(bounds.width, maximumWidth + Self.tolerance, "\(message)：宽度", file: file, line: line)
    XCTAssertTrue(
      Self.picture.insetBy(dx: -Self.tolerance, dy: -Self.tolerance).contains(bounds),
      "\(message)：越出画面 \(bounds)", file: file, line: line)
  }

  /// 按播放界面的排版画一句带 `\pos` 的字幕（锚点按 1920×1080 画面给出），返回画出来的像素范围。
  private func render(
    _ text: String, alignment: Int, at anchor: CGPoint, sizeScale: CGFloat = 1
  ) throws -> CGRect {
    try render(
      text, alignment: alignment, at: CGPoint(x: anchor.x / Self.screen.width, y: anchor.y / Self.screen.height),
      in: Self.screen, sizeScale: sizeScale)
  }

  /// 在 1920×1080 的屏幕上按 `video` 的宽高比放画面，`normalized` 是 `\pos` 锚点按画面归一化的位置。
  private func render(
    _ text: String, alignment: Int, at normalized: CGPoint, in video: CGSize, sizeScale: CGFloat = 1
  ) throws -> CGRect {
    let cue = SubtitleSnapshot.TextCue(
      id: 1, spans: [SubtitleSpan(text: text)], alignment: alignment, position: normalized)
    let layer = TextSubtitleLayer(
      snapshot: SubtitleSnapshot(texts: [cue]),
      videoLayout: VideoPlayer.VideoLayout(videoSize: video, viewportSize: Self.screen, behavior: .fit),
      style: Self.captionStyle(sizeScale: sizeScale),
      basePointSize: Self.basePointSize
    )
    .frame(width: Self.screen.width, height: Self.screen.height)
    let renderer = ImageRenderer(content: layer)
    renderer.scale = 1
    renderer.proposedSize = ProposedViewSize(Self.screen)
    let image = try XCTUnwrap(renderer.cgImage, "渲染失败")
    XCTAssertEqual(image.width, Int(Self.screen.width))
    return try XCTUnwrap(Self.paintedBounds(of: image), "没有画出字幕")
  }

  /// 白字、不透明直角黑底：画出来的范围就是整块字幕。字号按 `sizeScale` 缩放，字体取系统默认。
  private static func captionStyle(sizeScale: CGFloat) -> CaptionStyle {
    let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
    let black = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
    return CaptionStyle(
      text: CaptionStyle.Text(
        color: CaptionSetting(value: white, behavior: .overrideContent),
        opacity: CaptionSetting(value: 1, behavior: .overrideContent),
        sizeScale: CaptionSetting(value: sizeScale, behavior: .overrideContent),
        edgeStyle: CaptionSetting(value: .none, behavior: .overrideContent),
        fonts: CaptionStyle.systemDefaults.text.fonts
      ),
      textBackground: CaptionStyle.Fill(
        color: CaptionSetting(value: black, behavior: .overrideContent),
        opacity: CaptionSetting(value: 1, behavior: .overrideContent)
      ),
      window: CaptionStyle.Window(
        color: CaptionSetting(value: black, behavior: .overrideContent),
        opacity: CaptionSetting(value: 1, behavior: .overrideContent),
        cornerRadius: CaptionSetting(value: 0, behavior: .overrideContent)
      ),
      isCustomized: true
    )
  }

  /// 不透明度过半的像素围出的范围（左上为原点）；什么都没画时为 nil。
  private static func paintedBounds(of image: CGImage) -> CGRect? {
    let width = image.width
    let height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
      guard
        let context = CGContext(
          data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
      else { return false }
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
      return true
    }
    guard drawn else { return nil }
    var minX = width
    var minY = height
    var maxX = -1
    var maxY = -1
    for y in 0..<height {
      let row = y * width * 4
      for x in 0..<width where pixels[row + x * 4 + 3] > 127 {
        minX = min(minX, x)
        maxX = max(maxX, x)
        minY = min(minY, y)
        maxY = max(maxY, y)
      }
    }
    guard maxX >= 0 else { return nil }
    return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
  }
}
