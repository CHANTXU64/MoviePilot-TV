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
  }
}
