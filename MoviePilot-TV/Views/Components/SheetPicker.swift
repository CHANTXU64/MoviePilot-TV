import Combine
import SwiftUI

#if DEBUG
enum SheetPickerUIPreviewPresentation {
  case options
}
#endif

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
  #if DEBUG
  private let presentsPickerOnAppear: Bool
  #endif

  @State private var showingPicker = false

  init(
    title: String,
    selection: Binding<Value>,
    options: [PickerOption<Value>]
  ) {
    self.title = title
    _selection = selection
    self.options = options
    #if DEBUG
    self.presentsPickerOnAppear = false
    #endif
  }

  #if DEBUG
  init(
    title: String,
    selection: Binding<Value>,
    options: [PickerOption<Value>],
    uiPreviewPresentation: SheetPickerUIPreviewPresentation?
  ) {
    self.title = title
    _selection = selection
    self.options = options
    self.presentsPickerOnAppear = uiPreviewPresentation == .options
  }
  #endif

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
    #if DEBUG
    .onAppear {
      guard presentsPickerOnAppear else { return }
      Task { @MainActor in
        await Task.yield()
        showingPicker = true
      }
    }
    #endif
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
