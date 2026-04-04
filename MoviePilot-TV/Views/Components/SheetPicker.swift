import Combine
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

struct SheetPicker<Value: Hashable>: View {
  let title: String
  @Binding var selection: Value
  let options: [PickerOption<Value>]

  @State private var showingPicker = false

  var body: some View {
    // 所有版本都使用嵌套 Sheet 模式，避免 NavigationLink 导致的 dismiss 问题
    Button(action: { showingPicker = true }) {
      LabeledContent(title) {
        if let selected = options.first(where: { $0.value == selection }) {
          Text(selected.title)
        } else {
          Text(String(describing: selection).isEmpty ? "未选择" : String(describing: selection))
        }
      }
      .if(SheetStyleFix.shouldApply) { view in
        view.padding(.horizontal)
      }
    }
    .sheet(isPresented: $showingPicker) {
      SheetPickerDetailView(
        title: title,
        selection: $selection,
        options: options,
        isPresented: $showingPicker
      )
    }
  }
}

private struct SheetPickerDetailView<Value: Hashable>: View {
  let title: String
  @Binding var selection: Value
  let options: [PickerOption<Value>]
  @Binding var isPresented: Bool

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack {
          ForEach(options) { option in
            Button(action: {
              selection = option.value
              isPresented = false
            }) {
              HStack {
                Text(option.title)
                Spacer()
                if option.value == selection {
                  Image(systemName: "checkmark")
                }
              }
              .if(SheetStyleFix.shouldApply) { view in
                view.padding(.horizontal)
              }
            }
          }
        }
        .applySheetStyles()
        .padding(28)
      }
    }
  }
}

