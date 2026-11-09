import SwiftUI

/// 横向滚动的胶囊选择器：推荐页货架、详情页「短评 / 影评」共用。
///
/// 上下各有一条 1pt 的焦点重定向条：焦点从相邻行移进来时，落到当前选中的胶囊上，
/// 而不是几何上离得最近的那颗。
struct ShelfPicker<Item: Identifiable>: View {
  let items: [Item]
  @Binding var selection: Item?
  let title: (Item) -> String

  @FocusState private var focusedShelfId: Item.ID?
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
            focusedShelfId = selection?.id ?? items.first?.id
            isTopRedirectorFocused = false
          }
        }

      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 20) {
          ForEach(items) { shelf in
            ShelfChip(
              title: title(shelf),
              isSelected: selection?.id == shelf.id,
              isFocused: focusedShelfId == shelf.id
            ) {
              selection = shelf
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
            focusedShelfId = selection?.id ?? items.first?.id
            isBottomRedirectorFocused = false
          }
        }
    }
    // 焦点光晕超出按钮，盖住上方分段选择器。层级只抬这一行，不改按钮和焦点条的位置。
    .zIndex(1)
  }
}

struct ShelfMenuOptionGroup<Value: Hashable>: Identifiable {
  let id: Value
  /// 没有标题的分组直接显示在第一层。
  let title: String?
  let options: [PickerOption<Value>]
}

/// 货架行头的下拉选择：当前值后面跟上下箭头，与 Sheet 里的菜单行（`SheetPicker`）同一个标记，
/// 一眼能和直接生效的胶囊、按钮区分开。选项多到胶囊放不下（如季很多）或本来就是一组设置（剧集组）时用它。
struct ShelfMenuPicker<Value: Hashable>: View {
  /// 菜单标题与无障碍名称
  let title: String
  @Binding var selection: Value
  let options: [PickerOption<Value>]
  /// 按钮上的文字由当前值生成，如「剧集组：默认」；不传时只显示当前值。
  var label: ((String) -> String)? = nil
  var groups: [ShelfMenuOptionGroup<Value>] = []

  var body: some View {
    let selected = options.first { $0.value == selection }
    let value = selected?.title ?? SheetPicker<Value>.displayTitle(for: selection, in: options)
    Menu {
      if groups.isEmpty {
        picker(options)
      } else {
        ForEach(groups) { group in
          if let groupTitle = group.title {
            Menu(groupTitle) {
              groupChoices(group.options)
            }
            .menuOrder(.fixed)
          } else {
            groupChoices(group.options)
          }
        }
      }
    } label: {
      HStack(spacing: 12) {
        Text(label?(value) ?? value)
          .lineLimit(1)
        if let detail = selected?.detail {
          Text(detail)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: true, vertical: false)
        }
        Image(systemName: AppSymbol.menuDisclosure)
          .font(.caption.bold())
          .foregroundStyle(.secondary)
          .accessibilityHidden(true)
      }
    }
    .menuStyle(.button)
    .menuOrder(groups.isEmpty ? .automatic : .fixed)
    .buttonBorderShape(.capsule)
    .accessibilityLabel(title)
    .accessibilityValue(selected?.titleWithDetail ?? value)
  }

  private func picker(_ choices: [PickerOption<Value>]) -> some View {
    Picker(title, selection: $selection) {
      ForEach(choices) { option in
        option.menuLabel().tag(option.value)
      }
    }
    .pickerStyle(.inline)
  }

  @ViewBuilder
  private func groupChoices(_ choices: [PickerOption<Value>]) -> some View {
    if choices.contains(where: { $0.value == selection }) {
      picker(choices)
    } else {
      // 当前项在另一个子菜单时，这里没有选中项。
      ForEach(choices) { option in
        Button { selection = option.value } label: { option.menuLabel() }
      }
    }
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
