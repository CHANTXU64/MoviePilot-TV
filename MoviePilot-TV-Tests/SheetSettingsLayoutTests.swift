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
    for systemImage in [nil, "arrow.triangle.2.circlepath"] {
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
}
