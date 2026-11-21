import SwiftUI

/// 探索条件编辑页（主屏探索与探索页默认配置共用）。
/// VM、焦点映射、重置/保存动作由调用方注入；字段渲染复用 ExploreSettingsFields。
struct ExploreConfigurationEditorPage: View {
  @ObservedObject var viewModel: ExploreViewModel
  @FocusState.Binding var focusedItem: SystemSettingsFocus?
  let sourceFocus: SystemSettingsFocus
  let fieldFocus: (String) -> SystemSettingsFocus
  let resetFocus: SystemSettingsFocus
  let factoryResetFocus: SystemSettingsFocus?
  let saveFocus: SystemSettingsFocus
  let pushSources: () -> Void
  let pushField: (String) -> Void
  let onResetFilters: () -> Void
  let onFactoryReset: (() -> Void)?
  let onSave: () -> Void
  let saveDisabled: Bool

  var body: some View {
    SettingsSection(nil) {
      Button(action: pushSources) {
        SettingsRowLabel("数据源", value: viewModel.selectedSource.title, showsDisclosure: true)
      }
      .focused($focusedItem, equals: sourceFocus)
      ForEach(viewModel.settingsFields) { field in
        switch field.kind {
        case .choice, .multiChoice:
          Button { pushField(field.id) } label: {
            SettingsRowLabel(field.title, value: field.summary, showsDisclosure: true)
          }
          .focused($focusedItem, equals: fieldFocus(field.id))
        case .text, .number:
          TextField(
            field.title,
            text: Binding(
              get: { field.value.wrappedValue.queryString ?? "" },
              set: {
                field.value.wrappedValue = $0.isEmpty ? .null
                  : (field.kind == .number ? Int($0).map(JSONValue.int) ?? .string($0) : .string($0))
              }))
          .focused($focusedItem, equals: fieldFocus(field.id))
        case .toggle:
          Toggle(
            field.title,
            isOn: Binding(
              get: { field.value.wrappedValue == .bool(true) },
              set: { field.value.wrappedValue = .bool($0) }))
          .focused($focusedItem, equals: fieldFocus(field.id))
        }
      }
      Button(action: onResetFilters) {
        SettingsRowLabel("重置筛选")
      }
      .focused($focusedItem, equals: resetFocus)
      if let onFactoryReset, let factoryResetFocus {
        Button(action: onFactoryReset) {
          SettingsRowLabel("恢复初始默认")
        }
        .focused($focusedItem, equals: factoryResetFocus)
      }
      Button(action: onSave) {
        SettingsRowLabel("保存")
      }
      .disabled(saveDisabled)
      .focused($focusedItem, equals: saveFocus)
    }
  }
}

/// 探索数据源选择页（主屏探索与探索页默认配置共用）。
struct ExploreConfigurationSourceListPage: View {
  @ObservedObject var viewModel: ExploreViewModel
  @FocusState.Binding var focusedItem: SystemSettingsFocus?
  let optionFocus: (String) -> SystemSettingsFocus
  let isSourceDisabled: (DiscoverSource) -> Bool
  let sourceNote: (DiscoverSource) -> String?
  let onSelect: (DiscoverSource) -> Void

  var body: some View {
    SettingsSection(nil) {
      ForEach(viewModel.availableSources) { source in
        Button { onSelect(source) } label: {
          SettingsRowLabel(
            source.title,
            value: viewModel.selectedSource.id == source.id ? "已选择" : sourceNote(source))
        }
        .disabled(isSourceDisabled(source))
        .focused($focusedItem, equals: optionFocus(source.id))
      }
    }
  }
}

/// 探索筛选字段编辑页（单选/多选，主屏探索与探索页默认配置共用）。
struct ExploreConfigurationFieldPage: View {
  let field: ExploreSettingsField
  @FocusState.Binding var focusedItem: SystemSettingsFocus?
  let optionFocus: (JSONValue) -> SystemSettingsFocus
  let onSingleSelect: () -> Void

  var body: some View {
    SettingsSection(field.title) {
      if field.kind == .multiChoice {
        Button { field.value.wrappedValue = .array([]) } label: {
          SettingsRowLabel("全部", value: field.value.wrappedValue.arrayValue?.isEmpty != false ? "已选择" : nil)
        }
        .focused($focusedItem, equals: optionFocus(.null))
      } else if !field.options.contains(where: { $0.value == field.value.wrappedValue }) {
        Button {} label: {
          SettingsRowLabel(field.summary, value: "已选择")
        }
        .focused($focusedItem, equals: optionFocus(field.value.wrappedValue))
      }
      ForEach(field.options) { option in
        let selected = field.kind == .multiChoice
          ? field.value.wrappedValue.arrayValue?.contains(option.value) == true
          : field.value.wrappedValue == option.value
        Button {
          if field.kind == .multiChoice {
            var values = field.value.wrappedValue.arrayValue ?? []
            if selected { values.removeAll { $0 == option.value } } else { values.append(option.value) }
            field.value.wrappedValue = .array(values)
          } else {
            field.value.wrappedValue = option.value
            onSingleSelect()
          }
        } label: {
          SettingsRowLabel(option.title, value: selected ? "已选择" : nil)
        }
        .focused($focusedItem, equals: optionFocus(option.value))
      }
    }
  }
}