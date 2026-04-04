import SwiftUI

struct SubscribeSheet: View {
  @Environment(\.dismiss) var dismiss
  @StateObject private var viewModel: SubscribeSheetViewModel
  @State private var hasAppeared = false
  @State private var showingSiteSelection = false
  @State private var showingFilterGroupSelection = false
  @State private var showAdvanced = false
  @FocusState private var isAdvancedButtonFocused: Bool

  init(subscribe: Subscribe, isNewSubscription: Bool = false) {
    _viewModel = StateObject(
      wrappedValue: SubscribeSheetViewModel(
        subscribe: subscribe, isNewSubscription: isNewSubscription))
  }

  var body: some View {
    NavigationStack {
      Group {
        if viewModel.isLoading {
          ProgressView("加载配置中...")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          VStack {
            Text(
              (viewModel.isNewSubscription ? "新增" : "编辑") + "：\(viewModel.subscribe.name)"
            )
            .font(.headline)
            .lineLimit(1)
            .foregroundColor(.secondary)
            .padding(.top, 28)
            .padding(.bottom, 0)

            ScrollView {
              VStack {
                if viewModel.subscribe.type == "电视剧" {
                  SheetTextField(
                    title: "电视剧总集数",
                    placeholder: "0",
                    text: Binding(
                      get: { String(viewModel.subscribe.total_episode ?? 0) },
                      set: { viewModel.subscribe.total_episode = Int($0) }
                    ),
                    keyboardType: .numberPad
                  )

                  SheetTextField(
                    title: "开始订阅集数",
                    placeholder: "0",
                    text: Binding(
                      get: { String(viewModel.subscribe.start_episode ?? 0) },
                      set: { viewModel.subscribe.start_episode = Int($0) }
                    ),
                    keyboardType: .numberPad
                  )
                }

                SheetPicker(
                  title: "质量",
                  selection: Binding(
                    get: { viewModel.subscribe.quality ?? "" },
                    set: { viewModel.subscribe.quality = $0 }
                  ),
                  options: viewModel.qualityOptions.map {
                    PickerOption(title: $0.title, value: $0.value)
                  }
                )

                SheetPicker(
                  title: "分辨率",
                  selection: Binding(
                    get: { viewModel.subscribe.resolution ?? "" },
                    set: { viewModel.subscribe.resolution = $0 }
                  ),
                  options: viewModel.resolutionOptions.map {
                    PickerOption(title: $0.title, value: $0.value)
                  }
                )

                SheetPicker(
                  title: "特效",
                  selection: Binding(
                    get: { viewModel.subscribe.effect ?? "" },
                    set: { viewModel.subscribe.effect = $0 }
                  ),
                  options: viewModel.effectOptions.map {
                    PickerOption(title: $0.title, value: $0.value)
                  }
                )

                Button(action: { showingSiteSelection = true }) {
                  LabeledContent("站点") {
                    Text(siteButtonLabel)
                  }
                  .if(SheetStyleFix.shouldApply) { view in
                    view.padding(.horizontal)
                  }
                }

                SheetPicker(
                  title: "下载器",
                  selection: Binding(
                    get: { viewModel.subscribe.downloader ?? "" },
                    set: { viewModel.subscribe.downloader = $0 }
                  ),
                  options: [PickerOption(title: "默认", value: "")]
                    + viewModel.downloaders.map {
                      PickerOption(title: $0.name, value: $0.name)
                    }
                )

                SheetPicker(
                  title: "保存路径",
                  selection: Binding(
                    get: { viewModel.subscribe.save_path ?? "" },
                    set: { viewModel.subscribe.save_path = $0 }
                  ),
                  options: [PickerOption(title: "自动", value: "")]
                    + viewModel.directories.map {
                      PickerOption(title: $0.name, value: $0.download_path ?? "")
                    }
                )

                Toggle(
                  "洗版",
                  isOn: Binding(
                    get: { (viewModel.subscribe.best_version ?? 0) == 1 },
                    set: { viewModel.subscribe.best_version = $0 ? 1 : 0 }
                  ))

                Toggle(
                  "使用IMDB搜索",
                  isOn: Binding(
                    get: { (viewModel.subscribe.search_imdbid ?? 0) == 1 },
                    set: { viewModel.subscribe.search_imdbid = $0 ? 1 : 0 }
                  ))

                Button {
                  withAnimation {
                    showAdvanced.toggle()
                  }
                } label: {
                  HStack {
                    Text("高级配置")
                    Spacer()
                    Image(systemName: showAdvanced ? "chevron.down" : "chevron.right")
                  }
                  .foregroundColor(isAdvancedButtonFocused ? .black : .secondary)
                  .if(SheetStyleFix.shouldApply) { view in
                    view.padding(.horizontal)
                  }
                }
                .focused($isAdvancedButtonFocused)

                if showAdvanced {
                  SheetTextField(
                    title: "搜索关键词",
                    placeholder: "",
                    text: Binding(
                      get: { viewModel.subscribe.keyword ?? "" },
                      set: { viewModel.subscribe.keyword = $0.isEmpty ? nil : $0 }
                    ))

                  SheetTextField(
                    title: "包含词",
                    placeholder: "",
                    text: Binding(
                      get: { viewModel.subscribe.include ?? "" },
                      set: { viewModel.subscribe.include = $0.isEmpty ? nil : $0 }
                    ))

                  SheetTextField(
                    title: "排除词",
                    placeholder: "",
                    text: Binding(
                      get: { viewModel.subscribe.exclude ?? "" },
                      set: { viewModel.subscribe.exclude = $0.isEmpty ? nil : $0 }
                    ))

                  Button(action: { showingFilterGroupSelection = true }) {
                    LabeledContent("优先级规则组") {
                      Text(filterGroupButtonLabel)
                    }
                    .if(SheetStyleFix.shouldApply) { view in
                      view.padding(.horizontal)
                    }
                  }

                  if viewModel.subscribe.type == "电视剧" {
                    SheetPicker(
                      title: "剧集组",
                      selection: Binding(
                        get: { viewModel.subscribe.episode_group ?? "" },
                        set: { viewModel.subscribe.episode_group = $0.isEmpty ? nil : $0 }
                      ),
                      options: [PickerOption(title: "默认", value: "")]
                        + viewModel.episodeGroups.map {
                          PickerOption(
                            title: "\($0.name) (\($0.group_count)季 \($0.episode_count)集)",
                            value: $0.id)
                        }
                    )

                    SheetPicker(
                      title: "指定季",
                      selection: Binding(
                        get: {
                          if let s = viewModel.subscribe.season { return String(s) }
                          return ""
                        },
                        set: { viewModel.subscribe.season = Int($0) }
                      ),
                      options: [PickerOption(title: "全部", value: "")]
                        + viewModel.seasonOptions.map {
                          PickerOption(title: "第 \($0) 季", value: String($0))
                        }
                    )
                  }

                  SheetTextField(
                    title: "自定义类别",
                    placeholder: "",
                    text: Binding(
                      get: { viewModel.subscribe.media_category ?? "" },
                      set: { viewModel.subscribe.media_category = $0.isEmpty ? nil : $0 }
                    ))

                  SheetTextField(
                    title: "自定义识别词",
                    placeholder: "",
                    text: Binding(
                      get: { viewModel.subscribe.custom_words ?? "" },
                      set: { viewModel.subscribe.custom_words = $0.isEmpty ? nil : $0 }
                    ))
                }

                Button(action: {
                  Task {
                    if await viewModel.save() {
                      dismiss()
                    }
                  }
                }) {
                  HStack(spacing: 8) {
                    if viewModel.isSaving {
                      ProgressView()
                    }
                    Text(viewModel.isNewSubscription ? "确定" : "保存")
                  }
                  .frame(maxWidth: .infinity)
                }
                .disabled(viewModel.isSaving)

                Button {
                  dismiss()
                } label: {
                  Text(viewModel.isNewSubscription ? "取消订阅" : "取消修改")
                    .frame(maxWidth: .infinity)
                }
              }
              .padding(.horizontal, 28)
              .padding(.top, 10)
              .padding(.bottom, 28)
              .applySheetStyles()
            }
          }
          .opacity(viewModel.isLoading ? 0 : 1)
          .onAppear {
            guard !hasAppeared else { return }
            hasAppeared = true
            Task {
              await viewModel.loadData()
            }
          }
          .onDisappear {
            if !viewModel.isSaved {
              Task {
                await viewModel.cancel()
              }
            }
          }
        }
      }
    }
    .sheet(isPresented: $showingSiteSelection) {
      MultiSelectionSheet(
        options: viewModel.sites,
        id: \.id,
        selected: Binding(
          get: { Set(viewModel.subscribe.sites ?? []) },
          set: { viewModel.subscribe.sites = $0.isEmpty ? nil : Array($0) }
        ),
        label: { $0.name }
      )
    }
    .sheet(isPresented: $showingFilterGroupSelection) {
      MultiSelectionSheet(
        options: viewModel.filterGroups,
        id: \.name,
        selected: Binding(
          get: { Set(viewModel.subscribe.filter_groups ?? []) },
          set: { viewModel.subscribe.filter_groups = $0.isEmpty ? nil : Array($0) }
        ),
        label: { $0.name }
      )
    }
  }

  /// Site selection button label
  private var siteButtonLabel: String {
    let selectedSiteIds = viewModel.subscribe.sites ?? []
    if selectedSiteIds.isEmpty {
      return "全部"
    }
    if selectedSiteIds.count == 1 {
      let siteId = selectedSiteIds[0]
      if let site = viewModel.sites.first(where: { $0.id == siteId }) {
        return site.name
      }
      return "已选 1 个"
    }
    return "已选 \(selectedSiteIds.count) 个"
  }

  private var filterGroupButtonLabel: String {
    let selectedGroups = viewModel.subscribe.filter_groups ?? []
    if selectedGroups.isEmpty {
      return "无"
    }
    if selectedGroups.count == 1 {
      return selectedGroups[0]
    }
    return "已选 \(selectedGroups.count) 个"
  }
}
