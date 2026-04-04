import SwiftUI

struct MultiSelectionSheet<T, ID: Hashable>: View {
  let options: [T]
  let id: KeyPath<T, ID>
  @Binding var selected: Set<ID>
  let label: (T) -> String

  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack {
          ForEach(options, id: id) { item in
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
        }
        .applySheetStyles()
        .padding(28)
      }
    }
  }
}
