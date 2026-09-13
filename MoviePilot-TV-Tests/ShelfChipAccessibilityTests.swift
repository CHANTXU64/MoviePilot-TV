import SwiftUI
import XCTest

@testable import MoviePilot_TV

/// F-169：货架选择器的**持久选择**必须对 VoiceOver 可见。
///
/// 关键前提是**焦点与持久选择是两种状态**：`isFocused` 表示「遥控器现在停在这个 chip
/// 上」，`isSelected` 表示「下方结果正由这个货架驱动」。两者可以分离 —— 用户把焦点移到
/// 别的 chip 但还没按下去时，驱动结果的仍是原来那个货架，视觉上也只有它在高亮。
/// 修复前默认 Button 只提供名称与动作语义，这个区别对 VoiceOver 用户完全不可见。
///
/// SwiftUI 的 trait 无法在 XCTest 里从渲染树读回，所以这里分两层：本文件断言
/// `accessibilityTraits` 这条**规则**，`ShelfChipTraitWiringTests` 断言它确实**接在
/// Button 上** —— 只测其中一层都会漏掉「属性写对了但没挂上去」这种情形。
@MainActor
final class ShelfChipAccessibilityTests: XCTestCase {

  private func chip(isSelected: Bool, isFocused: Bool) -> ShelfChip {
    ShelfChip(title: "热门", isSelected: isSelected, isFocused: isFocused, action: {})
  }

  // MARK: - 阳性

  /// 选中项必须带 `.isSelected`。
  func testSelectedShelfCarriesSelectedTrait() {
    let traits = chip(isSelected: true, isFocused: false).accessibilityTraits

    XCTAssertTrue(traits.contains(.isSelected), "当前驱动结果的货架必须播报为已选中")
  }

  // MARK: - 阴性对照

  /// 未选中项绝不能带 —— 每个 chip 都播报「已选中」比不播报更糟，等于把区别抹掉。
  func testUnselectedShelfDoesNotCarrySelectedTrait() {
    let traits = chip(isSelected: false, isFocused: false).accessibilityTraits

    XCTAssertFalse(traits.contains(.isSelected))
  }

  /// **本项的核心**：焦点不是选择。焦点停在这个 chip 上、但它并不是驱动结果的货架时，
  /// 不得据此播报「已选中」—— 否则「把焦点移过去看看」会立刻谎报结果已经切过去了。
  func testFocusedButUnselectedShelfIsNotAnnouncedAsSelected() {
    let traits = chip(isSelected: false, isFocused: true).accessibilityTraits

    XCTAssertFalse(traits.contains(.isSelected), "焦点落在未选中的 chip 上不等于它已选中")
  }

  /// 只加这一个 trait，不夹带别的语义 —— 审计明确要求不加自定义 label/value，
  /// 也不引入 selection/focus 框架；名称由 `Text(title)` 提供，无需重复。
  func testOnlySelectedTraitIsAdded() {
    let traits = chip(isSelected: true, isFocused: true).accessibilityTraits

    XCTAssertEqual(traits, [.isSelected])
  }
}

/// 接线守卫：`accessibilityTraits` 定义对了却没挂到 Button 上，上面四条会全过而
/// VoiceOver 什么也听不到。trait 无法从渲染树读回，故按本仓库既有做法
/// （见 `TMDBJumpAlertCallSiteTests`）直接断言源码。
final class ShelfChipTraitWiringTests: XCTestCase {

  private func source(_ relativePath: String) throws -> String {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath))
  }

  func testTraitIsAppliedToTheChipButton() throws {
    let shelfPicker = try source("MoviePilot-TV/Views/Components/ShelfPicker.swift")

    XCTAssertTrue(
      shelfPicker.contains(".accessibilityAddTraits(accessibilityTraits)"),
      "accessibilityTraits 必须真的挂到 ShelfChip 的 Button 上")
  }

  /// 审计裁决的边界：不加自定义 label/value。名称已由 `Text(title)` 提供，
  /// 另起一套文案会与可见文本分叉，也让播报措辞脱离本项范围。
  /// 同时守住「不引入 selection/focus 框架」—— 焦点仍由 `@FocusState` 管理。
  func testNoCustomLabelValueOrSelectionFrameworkIsIntroduced() throws {
    let shelfPicker = try source("MoviePilot-TV/Views/Components/ShelfPicker.swift")

    for forbidden in [".accessibilityLabel(", ".accessibilityValue(", ".accessibilityElement("] {
      XCTAssertFalse(shelfPicker.contains(forbidden), "本项不引入 \(forbidden)")
    }
  }
}
