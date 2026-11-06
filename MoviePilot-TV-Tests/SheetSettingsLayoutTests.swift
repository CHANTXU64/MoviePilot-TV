import SwiftUI
import XCTest

@testable import MoviePilot_TV

/// Sheet 设置面板里几处布局规则：按实际排版量尺寸，不靠源码字符串。
@MainActor
final class SheetSettingsLayoutTests: XCTestCase {
  private func fittingSize<V: View>(_ view: V) -> CGSize {
    UIHostingController(rootView: view)
      .sizeThatFits(in: CGSize(width: 1000, height: 1000))
  }

  /// 加载中插入的转圈图标不能把按钮撑高：有图标、没图标的按钮，加载前后高度都一样。
  func testActionButtonKeepsHeightWhileLoading() {
    for systemImage in [nil, AppSymbol.reorganize] {
      let idle = fittingSize(
        SheetActionButton(
          title: "预览整理结果", systemImage: systemImage, loadingTitle: "预览中", isLoading: false
        ) {}
        .frame(width: 440))
      let loading = fittingSize(
        SheetActionButton(
          title: "预览整理结果", systemImage: systemImage, loadingTitle: "预览中", isLoading: true
        ) {}
        .frame(width: 440))
      XCTAssertEqual(loading.height, idle.height, "systemImage: \(systemImage ?? "nil")")
    }
  }

  /// 整行输入框：项名和内容在框里放得下才显示项名，放不下（长识别词）只显示内容；没填内容不显示。
  func testInlineTitleOnlyShowsWhenTitleAndTextFit() {
    let font = UIFont.preferredFont(forTextStyle: .body)
    let width: CGFloat = 488

    XCTAssertTrue(
      SheetInlineTextField.showsTitle(title: "总集数", text: "6", font: font, fieldWidth: width))
    XCTAssertFalse(
      SheetInlineTextField.showsTitle(title: "总集数", text: "", font: font, fieldWidth: width))
    XCTAssertFalse(
      SheetInlineTextField.showsTitle(
        title: "自定义识别词",
        text: "第(\\d+)集 => {[tmdbid=12345;type=tv;s=1;e=\\1]}",
        font: font, fieldWidth: width))
    // 宽度还没量出来时不显示，避免先叠在一起再消失。
    XCTAssertFalse(
      SheetInlineTextField.showsTitle(title: "总集数", text: "6", font: font, fieldWidth: 0))
  }

  /// 普通输入框（没有项名）保持 UIKit 默认的文字区域，只有整行输入框才改缩进。
  func testPlainNoBlurTextFieldKeepsDefaultTextRect() {
    let bounds = CGRect(x: 0, y: 0, width: 600, height: 66)
    let plain = NoBlurTextField(frame: bounds)
    let reference = UITextField(frame: bounds)
    XCTAssertEqual(plain.textRect(forBounds: bounds), reference.textRect(forBounds: bounds))
    XCTAssertEqual(
      plain.placeholderRect(forBounds: bounds), reference.placeholderRect(forBounds: bounds))

    let inline = NoBlurTextField(frame: bounds)
    inline.font = UIFont.systemFont(ofSize: 30, weight: .medium)
    inline.inlineTitle = "指定季"
    XCTAssertEqual(
      inline.textRect(forBounds: bounds).minX, SheetInlineTextField.horizontalInset)

    inline.text = "3"
    inline.refreshInlineTitle()
    // 显示项名时，内容从项名右边开始，不会压到项名上。
    XCTAssertGreaterThan(
      inline.textRect(forBounds: bounds).minX, SheetInlineTextField.horizontalInset)
  }

  // MARK: - 出错提示的保留规则

  /// 重试：ViewModel 先清掉原因、再进入忙碌；忙的时候继续显示原来的提示和「重试」，
  /// 忙完没有新的出错就消失。
  func testRetainedMessageStaysDuringRetryAndClearsAfterSuccess() {
    var retention = SheetMessageRetention()
    retention.update(current: "加载失败", hasRetry: true, isBusy: false)
    XCTAssertEqual(retention.shownMessage(current: "加载失败", isBusy: false), "加载失败")

    retention.update(current: nil, hasRetry: false, isBusy: true)
    XCTAssertEqual(retention.shownMessage(current: nil, isBusy: true), "加载失败")
    XCTAssertTrue(retention.showsRetry(current: nil, currentHasRetry: false))

    retention.update(current: nil, hasRetry: false, isBusy: false)
    XCTAssertNil(retention.shownMessage(current: nil, isBusy: false))
    XCTAssertNil(retention.retainedMessage)
  }

  /// 重试后又出错：显示新的原因。
  func testRetainedMessageIsReplacedByNewFailure() {
    var retention = SheetMessageRetention()
    retention.update(current: "加载失败", hasRetry: true, isBusy: false)
    retention.update(current: nil, hasRetry: false, isBusy: true)
    retention.update(current: "网络超时", hasRetry: true, isBusy: false)
    XCTAssertEqual(retention.shownMessage(current: "网络超时", isBusy: false), "网络超时")
  }

  /// 用户自己把问题改好（不在忙时提示变空），保留的旧提示一起忘掉；
  /// 之后按主按钮进入忙碌，不会把已经解决的提示翻出来。
  func testResolvedMessageIsNotShownAgainOnNextBusyPeriod() {
    var retention = SheetMessageRetention()
    retention.update(current: "请填写媒体 ID", hasRetry: false, isBusy: false)
    retention.update(current: nil, hasRetry: false, isBusy: false)
    XCTAssertNil(retention.retainedMessage)

    retention.update(current: nil, hasRetry: false, isBusy: true)
    XCTAssertNil(retention.shownMessage(current: nil, isBusy: true))
  }

  /// 不能重试的提示（如整理失败）在忙的时候保留，但不会凭空多出「重试」。
  func testRetainedMessageKeepsItsRetryAvailability() {
    var retention = SheetMessageRetention()
    retention.update(current: "整理没有开始", hasRetry: false, isBusy: false)
    retention.update(current: nil, hasRetry: false, isBusy: true)
    XCTAssertEqual(retention.shownMessage(current: nil, isBusy: true), "整理没有开始")
    XCTAssertFalse(retention.showsRetry(current: nil, currentHasRetry: false))
  }

  /// 搜索页「最佳结果」和查询媒体 ID 的卡片第二行用同一种写法：类型 · 年份 · 来源，缺的项跳过。
  func testBestResultCardSubtitleUsesTypeYearAndSource() throws {
    let media = try JSONDecoder().decode(
      MediaInfo.self,
      from: Data(#"{"tmdb_id":1,"title":"七王国的骑士","year":"2026","type":"电视剧","source":"themoviedb"}"#.utf8))
    XCTAssertEqual(BestResultCard.mediaSubtitle(for: media), "电视剧 · 2026 · TMDB")

    let noYear = try JSONDecoder().decode(
      MediaInfo.self, from: Data(#"{"douban_id":"2","title":"无年份","type":"电影","source":"douban"}"#.utf8))
    XCTAssertEqual(BestResultCard.mediaSubtitle(for: noYear), "电影 · 豆瓣")
  }
}
