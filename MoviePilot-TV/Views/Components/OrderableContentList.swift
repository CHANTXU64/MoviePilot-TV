import SwiftUI

enum ContentMoveDirection: Hashable {
  case up
  case down
}

enum ContentRowRole: Hashable {
  case toggle
  case moveUp
  case moveDown
}

/// 设置页"内容与顺序"列表：普通模式 Toggle 显隐，排序模式上移/下移。
/// 行身份用稳定业务 id，焦点 id 由调用方映射到页面级焦点枚举；
/// 行移动后焦点随同一控件跟随，到边界时移到同一行反方向按钮。
struct OrderableContentList<Item: Identifiable, Focus: Hashable>: View {
  let items: [Item]
  let title: (Item) -> String
  let isEnabled: (Item) -> Bool
  let isOrdering: Bool
  let onToggle: (Item, Bool) -> Void
  let onMove: (Item, ContentMoveDirection) -> Void
  let focus: (Item, ContentRowRole) -> Focus
  @FocusState.Binding var focusedItem: Focus?

  var body: some View {
    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
      if isOrdering {
        orderRow(item, index: index)
      } else {
        Toggle(
          title(item),
          isOn: Binding(
            get: { isEnabled(item) },
            set: { onToggle(item, $0) }
          )
        )
        .font(.body.bold())
        .focused($focusedItem, equals: focus(item, .toggle))
      }
    }
  }

  private func orderRow(_ item: Item, index: Int) -> some View {
    HStack(spacing: 16) {
      Text(title(item))
        .font(.body.bold())
        .lineLimit(1)
        .foregroundStyle(isEnabled(item) ? .primary : .secondary)
      if !isEnabled(item) {
        Text("已隐藏")
          .font(.callout)
          .foregroundStyle(.secondary)
      }
      Spacer()
      moveButton(item, index: index, direction: .up)
      moveButton(item, index: index, direction: .down)
    }
  }

  private func moveButton(_ item: Item, index: Int, direction: ContentMoveDirection) -> some View {
    let isBoundary = direction == .up ? index == 0 : index == items.count - 1
    return Button {
      move(item, index: index, direction: direction)
    } label: {
      Image(systemName: direction == .up ? AppSymbol.moveUp : AppSymbol.moveDown)
        .frame(width: 56, height: 56)
    }
    .disabled(isBoundary)
    .focused($focusedItem, equals: focus(item, direction == .up ? .moveUp : .moveDown))
    .accessibilityLabel("\(direction == .up ? "上移" : "下移") \(title(item))")
  }

  private func move(_ item: Item, index: Int, direction: ContentMoveDirection) {
    let newIndex = direction == .up ? index - 1 : index + 1
    guard newIndex >= 0, newIndex < items.count else { return }
    onMove(item, direction)
    let sameDirectionStillEnabled = direction == .up ? newIndex > 0 : newIndex < items.count - 1
    if !sameDirectionStillEnabled {
      let opposite: ContentRowRole = direction == .up ? .moveDown : .moveUp
      DispatchQueue.main.async {
        focusedItem = focus(item, opposite)
      }
    }
  }
}