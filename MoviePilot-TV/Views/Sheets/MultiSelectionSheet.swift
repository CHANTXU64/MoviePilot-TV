import SwiftUI

struct MultiSelectionSheet<T, ID: Hashable>: View {
  let options: [T]
  let id: KeyPath<T, ID>
  @Binding var selected: Set<ID>
  let label: (T) -> String
  var disabledOptions: Set<ID> = []
  var disabledOptionsTitle: String? = nil

  @Environment(\.dismiss) private var dismiss

  /// 已选但不在可选项中的值（旧配置/已停用项）。
  static func unavailableSelections(
    in selected: Set<ID>,
    options: [T],
    id: KeyPath<T, ID>
  ) -> Set<ID> {
    selected.subtracting(options.map { $0[keyPath: id] })
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack {
          // Available options
          ForEach(options.filter { !disabledOptions.contains($0[keyPath: id]) }, id: id) { item in
            let itemId = item[keyPath: id]
            Toggle(
              label(item),
              isOn: Binding(
                get: { selected.contains(itemId) },
                set: { isSelected in
                  if isSelected {
                    selected.insert(itemId)
                  } else {
                    selected.remove(itemId)
                  }
                }
              )
            )
          }

          Button(action: { dismiss() }) {
            Text("确认")
              .frame(maxWidth: .infinity)
          }

          // Disabled options
          let disabledItems = options.filter { disabledOptions.contains($0[keyPath: id]) }
          if !disabledItems.isEmpty {
            Divider()

            if let title = disabledOptionsTitle {
              Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2)
                .padding(.leading, 8)
            }

            ForEach(disabledItems, id: id) { item in
              let itemId = item[keyPath: id]
              Toggle(
                label(item),
                isOn: Binding(
                  get: { selected.contains(itemId) },
                  set: { isSelected in
                    if isSelected {
                      selected.insert(itemId)
                    } else {
                      selected.remove(itemId)
                    }
                  }
                )
              )
              .disabled(true)
              .opacity(0.5)
            }
          }

          // 已选但不在可选项中的值（旧配置/已停用项）：给出可见的主动清除入口
          let unavailableSelections = Self.unavailableSelections(
            in: selected,
            options: options,
            id: id
          )
          if !unavailableSelections.isEmpty {
            Divider()
            Button {
              selected.subtract(unavailableSelections)
            } label: {
              Text("清除不可用选择（\(unavailableSelections.count)）")
                .frame(maxWidth: .infinity)
                .foregroundColor(.red)
            }
          }
        }
        .applySheetStyles()
        .padding(28)
      }
    }
  }
}
