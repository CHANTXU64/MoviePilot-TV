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
  }
}

/// 单个 Shelf Chip - 胶囊样式
struct ShelfChip: View {
  let title: String
  let isSelected: Bool
  let isFocused: Bool
  let action: () -> Void

  /// F-169：把「当前正驱动下方结果的货架」这层语义交给 VoiceOver。
  ///
  /// 原先只有 `overlay` 的视觉压暗，而**焦点与持久选择是两种状态**：`isFocused` 是
  /// 「遥控器现在停在这个 chip 上」，`isSelected` 是「下方结果正由这个货架驱动」。
  /// 用户把焦点移到别的 chip 但还没按下去时，结果仍归原来的货架 —— 此时 VoiceOver
  /// 只能听到 chip 名称，无从判断哪个货架在生效。默认 Button 只提供名称与动作语义。
  ///
  /// 按审计裁决只加这一个 trait：不加自定义 label/value（名称已由 `Text(title)` 提供），
  /// 也不引入 selection/focus 框架。抽成属性而非内联三元是为了让「只有选中项才带、
  /// 焦点不参与」这条规则可被单测直接断言 —— trait 本身无法在 XCTest 里从渲染树读回。
  var accessibilityTraits: AccessibilityTraits {
    isSelected ? .isSelected : []
  }

  var body: some View {
    Button(action: action) {
      Text(title)
    }
    .buttonStyle(.borderedProminent)
    .foregroundColor(.primary)
    .buttonBorderShape(.capsule)
    .overlay {
      if !isSelected && !isFocused {
        Capsule()
          .fill(Color.black.opacity(0.2))
          .allowsHitTesting(false)
      }
    }
    // 放在链尾：`overlay` 会再包一层，此处确保 trait 落在最终的可访问元素上。
    .accessibilityAddTraits(accessibilityTraits)
  }
}
