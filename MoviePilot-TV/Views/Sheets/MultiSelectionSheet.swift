import SwiftUI

struct MultiSelectionSheet<T, ID: Hashable>: View {
  let options: [T]
  let id: KeyPath<T, ID>
  @Binding var selected: Set<ID>
  let label: (T) -> String

  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      List {
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
          .applySheetStyles()
        }
      }
      .padding(.vertical, 20)
      .padding()
    }
  }
}
