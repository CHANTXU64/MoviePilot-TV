import SwiftUI

/// 多选的共用语义。
enum MultiSelection {
  /// 已选但不在可选项中的值（旧配置/已停用项）。
  nonisolated static func unavailableSelections<T, ID: Hashable>(
    in selected: Set<ID>,
    options: [T],
    id: KeyPath<T, ID>
  ) -> Set<ID> {
    selected.subtracting(options.map { $0[keyPath: id] })
  }
}

/// 多选系统菜单的内容：每个选项一行系统 `Toggle`，外加不可选分组和「清除不可用选择」。
///
/// SwiftUI 的 `Picker` 只有单选，系统菜单里的多选就是一组 `Toggle`。放在 `Menu { }` 里使用，
/// 并配合 `.menuActionDismissBehavior(.disabled)`：点一项立即生效、菜单不收起，选好按 Menu 键关闭。
///
/// `emptySelectionTitle` 在最上面放一项「不选」（如「全部」），没有选择时它打勾。系统菜单只在有
/// 打勾项时才留出对勾位置，始终有一项打勾，才不会在第一次勾选时整列右移。
struct MultiSelectionMenuContent<T, ID: Hashable, Header: View>: View {
  let options: [T]
  let id: KeyPath<T, ID>
  @Binding var selected: Set<ID>
  let label: (T) -> String
  var disabledOptions: Set<ID> = []
  var disabledOptionsTitle: String? = nil
  /// 最上面「不选」那一项的名称；nil 时不显示（调用方自己提供了等价项，如搜索站点的「默认」）。
  var emptySelectionTitle: String? = nil
  /// 有值时，可选项放进这个标题的分组。
  var sectionTitle: String? = nil
  /// 放在可选项前面的说明（如加载中、加载失败）。
  @ViewBuilder var header: () -> Header

  var body: some View {
    if let emptySelectionTitle {
      Section {
        Toggle(emptySelectionTitle, isOn: Binding(
          get: { selected.isEmpty },
          set: { if $0 { selected = [] } }
        ))
      }
    }

    if let sectionTitle {
      Section(sectionTitle) {
        header()
        rows(enabledOptions)
      }
    } else {
      header()
      rows(enabledOptions)
    }

    let disabledItems = options.filter { disabledOptions.contains($0[keyPath: id]) }
    if !disabledItems.isEmpty {
      Section(disabledOptionsTitle ?? "") {
        rows(disabledItems)
          .disabled(true)
      }
    }

    let unavailableSelections = MultiSelection.unavailableSelections(
      in: selected, options: options, id: id
    )
    if !unavailableSelections.isEmpty {
      Section {
        Button(role: .destructive) {
          selected.subtract(unavailableSelections)
        } label: {
          Text("清除不可用选择（\(unavailableSelections.count)）")
        }
      }
    }
  }

  private var enabledOptions: [T] {
    options.filter { !disabledOptions.contains($0[keyPath: id]) }
  }

  private func rows(_ items: [T]) -> some View {
    ForEach(items, id: id) { item in
      let itemID = item[keyPath: id]
      Toggle(label(item), isOn: Binding(
        get: { selected.contains(itemID) },
        set: { isSelected in
          if isSelected { selected.insert(itemID) }
          else { selected.remove(itemID) }
        }
      ))
    }
  }
}

extension MultiSelectionMenuContent where Header == EmptyView {
  init(
    options: [T],
    id: KeyPath<T, ID>,
    selected: Binding<Set<ID>>,
    label: @escaping (T) -> String,
    disabledOptions: Set<ID> = [],
    disabledOptionsTitle: String? = nil,
    emptySelectionTitle: String? = nil
  ) {
    self.init(
      options: options, id: id, selected: selected, label: label,
      disabledOptions: disabledOptions, disabledOptionsTitle: disabledOptionsTitle,
      emptySelectionTitle: emptySelectionTitle,
      header: { EmptyView() }
    )
  }
}
