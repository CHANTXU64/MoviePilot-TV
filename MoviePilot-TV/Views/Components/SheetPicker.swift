import SwiftUI

struct PickerOption<Value: Hashable>: Identifiable {
  let id: Value
  let title: String
  let value: Value

  init(title: String, value: Value) {
    self.title = title
    self.value = value
    self.id = value
  }
}

/// Sheet 表单里的单选行：左边标题，右边当前值，点开是系统菜单。多选见 `SheetMultiPicker`。
///
/// 用系统 `Menu` 而不是再弹一个 Sheet：tvOS 26 起 sheet 上再叠 sheet，过渡时系统会把下层
/// sheet 提亮一下，看起来是「闪一下」。菜单在原位弹出，打勾显示当前值，选完自动收起；
/// Menu 键关闭菜单、所在 Sheet 关闭时菜单随之消失，都由系统处理。
struct SheetPicker<Value: Hashable>: View {
  let title: String
  @Binding var selection: Value
  let options: [PickerOption<Value>]
  /// 暂时不能选时菜单里只显示这句话（如「正在加载…」「请先填写 TMDB ID」），行仍可聚焦。
  /// 不用 `.disabled`：tvOS 上聚焦的元素变成禁用会让焦点跳走，禁用的行也移不上去、看不到说明。
  var unavailableMessage: String? = nil

  /// 行右侧显示的值。当前值不在选项里（旧配置、已停用项）时照原样显示，不悄悄当成默认。
  static func displayTitle(for selection: Value, in options: [PickerOption<Value>]) -> String {
    if let selected = options.first(where: { $0.value == selection }) {
      return selected.title
    }
    let raw = String(describing: selection)
    return raw.isEmpty ? "未选择" : raw
  }

  var body: some View {
    Menu {
      if let unavailableMessage {
        Text(unavailableMessage)
      } else {
        Picker(title, selection: $selection) {
          ForEach(options) { option in
            Text(option.title).tag(option.value)
          }
        }
        .pickerStyle(.inline)
      }
    } label: {
      LabeledContent(title) {
        MenuRowValue(text: Self.displayTitle(for: selection, in: options))
      }
      .if(SheetStyleFix.shouldApply) { view in
        view.padding(.horizontal)
      }
    }
    // 菜单按钮沿用环境里的按钮样式，tvOS 26.0–26.3 的 Sheet 样式修复才能作用到这一行。
    .menuStyle(.button)
  }
}

/// Sheet 表单里的多选行：左边标题，右边摘要，点开是系统菜单（内容见 `MultiSelectionMenuContent`）。
struct SheetMultiPicker<T, ID: Hashable>: View {
  let title: String
  let summary: String
  /// 没有选择时的含义，作为菜单最上面一项（如「全部」「无」）。
  let emptySelectionTitle: String
  let options: [T]
  let id: KeyPath<T, ID>
  @Binding var selected: Set<ID>
  let label: (T) -> String

  var body: some View {
    Menu {
      MultiSelectionMenuContent(
        options: options, id: id, selected: $selected, label: label,
        emptySelectionTitle: emptySelectionTitle
      )
    } label: {
      LabeledContent(title) {
        MenuRowValue(text: summary)
      }
      .if(SheetStyleFix.shouldApply) { view in
        view.padding(.horizontal)
      }
    }
    // 多选：点一项不收起菜单。
    .menuActionDismissBehavior(.disabled)
    // 同 SheetPicker：沿用环境里的按钮样式。
    .menuStyle(.button)
  }
}

/// 菜单行右侧：当前值 + 上下箭头。箭头是系统菜单按钮的通用标记，表示点开是选项菜单，
/// 区别于跳转下一页（右箭头）和输入框。
private struct MenuRowValue: View {
  let text: String

  var body: some View {
    HStack(spacing: 12) {
      Text(text)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
      Image(systemName: "chevron.up.chevron.down")
        .font(.caption.bold())
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }
  }
}
