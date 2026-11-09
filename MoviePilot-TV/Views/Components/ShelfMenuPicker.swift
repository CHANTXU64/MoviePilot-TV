import SwiftUI

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
