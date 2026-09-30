import SwiftUI

/// 货架选择器 - 横向滚动的胶囊样式选择器
struct ShelfPicker: View {
  let shelves: [RecommendShelf]
  @Binding var selectedShelf: RecommendShelf?

  @FocusState private var focusedShelfId: String?
  @FocusState private var isTopRedirectorFocused: Bool
  @FocusState private var isBottomRedirectorFocused: Bool

  var body: some View {
    VStack(spacing: 0) {
      // 顶部焦点重定向器 - 捕获来自上方 CategoryPicker 的焦点
      Color.clear
        .frame(height: 1)
        .focusable(focusedShelfId == nil)
        .focused($isTopRedirectorFocused)
        .onChange(of: isTopRedirectorFocused) { _, isFocused in
          if isFocused {
            focusedShelfId = selectedShelf?.id ?? shelves.first?.id
            isTopRedirectorFocused = false
          }
        }

      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 20) {
          ForEach(shelves) { shelf in
            ShelfChip(
              title: shelf.title,
              isSelected: selectedShelf?.id == shelf.id,
              isFocused: focusedShelfId == shelf.id
            ) {
              selectedShelf = shelf
            }
            .focused($focusedShelfId, equals: shelf.id)
          }
        }
      }
      .scrollClipDisabled()

      // 底部焦点重定向器 - 捕获来自下方 MediaGrid 的焦点
      Color.clear
        .frame(height: 1)
        .focusable(focusedShelfId == nil)
        .focused($isBottomRedirectorFocused)
        .onChange(of: isBottomRedirectorFocused) { _, isFocused in
          if isFocused {
            focusedShelfId = selectedShelf?.id ?? shelves.first?.id
            isBottomRedirectorFocused = false
          }
        }
    }
    // 焦点光晕超出按钮，盖住上方分段选择器。层级只抬这一行，不改按钮和焦点条的位置。
    .zIndex(1)
  }
}

/// 货架胶囊的底色和字色。未聚焦时不使用实心白，也不另画边框。
/// 亮白色只留给系统焦点。
struct ShelfChipAppearance: Equatable {
  var tint: Color?
  var foreground: Color

  static let selectedTint = Color(white: 0.34)
  static let selectedForeground = Color.white
  static let unselectedTint = Color(white: 0.16)
  static let unselectedForeground = Color.white.opacity(0.62)
  static let focusedForeground = Color.black

  static func resolve(isSelected: Bool, isFocused: Bool) -> ShelfChipAppearance {
    if isFocused {
      return ShelfChipAppearance(tint: nil, foreground: focusedForeground)
    }
    if isSelected {
      return ShelfChipAppearance(tint: selectedTint, foreground: selectedForeground)
    }
    return ShelfChipAppearance(tint: unselectedTint, foreground: unselectedForeground)
  }
}

/// 单个 Shelf Chip - 胶囊样式
struct ShelfChip: View {
  let title: String
  let isSelected: Bool
  let isFocused: Bool
  let action: () -> Void

  /// F-169：把「当前正驱动下方结果的货架」交给 VoiceOver。
  ///
  /// 焦点和持久选择是两种状态：`isFocused` 是遥控器停在这个 chip 上，`isSelected`
  /// 是下方结果正由这个货架驱动。用户把焦点移到别的 chip 但还没按下去时，结果仍归原来的货架。
  /// 默认 Button 只有名称和动作，VoiceOver 分不清哪个货架在生效。
  ///
  /// 按审计裁决只加这一个 trait：不加自定义 label/value（名称已由 `Text(title)` 提供），
  /// 也不引入 selection/focus 框架。抽成属性而非内联三元是为了让「只有选中项才带、
  /// 焦点不参与」这条规则可被单测直接断言 —— trait 本身无法在 XCTest 里从渲染树读回。
  var accessibilityTraits: AccessibilityTraits {
    isSelected ? .isSelected : []
  }

  var body: some View {
    let appearance = ShelfChipAppearance.resolve(isSelected: isSelected, isFocused: isFocused)
    Button(action: action) {
      Text(title)
        .foregroundStyle(appearance.foreground)
    }
    .buttonStyle(.borderedProminent)
    .buttonBorderShape(.capsule)
    .tint(appearance.tint)
    // 放在链尾：样式会再包一层，此处确保 trait 落在最终的可访问元素上。
    .accessibilityAddTraits(accessibilityTraits)
  }
}
