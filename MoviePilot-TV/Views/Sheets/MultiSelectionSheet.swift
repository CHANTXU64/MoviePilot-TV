import SwiftUI

struct MultiSelectionSheet<T, ID: Hashable>: View {
  let options: [T]
  let id: KeyPath<T, ID>
  @Binding var selected: Set<ID>
  let label: (T) -> String
  var disabledOptions: Set<ID> = []
  var disabledOptionsTitle: String? = nil

  @Environment(\.dismiss) private var dismiss

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
        }
        .applySheetStyles()
        .padding(28)
      }
    }
  }
}
