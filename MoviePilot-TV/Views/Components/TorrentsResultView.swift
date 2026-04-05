import SwiftUI

struct TorrentsResultView<Header: View>: View {
  let result: [Context]
  var overrideMediaInfo: MediaInfo? = nil
  let header: Header

  // 筛选与排序状态
  @State private var filterForm: [String: Set<String>] = [:]
  @State private var sortField: SortField = .default
  @State private var sortType: SortType = .desc

  // Sheet 状态
  @State private var activeFilter: FilterConfig?
  @State private var tempFilterSelection: Set<String> = []

  // 计算/缓存状态
  @State private var filterOptions: [String: [String]] = [:]
  @State private var filteredResults: [Context] = []

  // 底部重定向器的焦点管理
  @FocusState private var focusedItemId: Context.ID?
  @FocusState private var isBottomRedirectorFocused: Bool

  let columns = [GridItem(.adaptive(minimum: 500, maximum: 600), spacing: 36, alignment: .top)]

  init(
    result: [Context],
    overrideMediaInfo: MediaInfo? = nil,
    @ViewBuilder header: () -> Header
  ) {
    self.result = result
    self.overrideMediaInfo = overrideMediaInfo
    self.header = header()
  }

  var body: some View {
    ScrollView(.vertical) {
      VStack(spacing: 20) {
        header

        if result.isEmpty {
          EmptyDataView(  // TODO 对于整页的加个按钮吧
            title: "未找到相关资源",
            systemImage: "magnifyingglass"
          )
          .padding(.top, 50)
        } else {
          // 筛选栏
          TorrentFilterBar(
            filterOptions: filterOptions,
            filterForm: $filterForm,
            sortField: $sortField,
            sortType: $sortType,
            activeFilter: $activeFilter,
            totalCount: filteredResults.count,
            onFilterClick: { key in
              // 打开 sheet 时初始化临时选择
              tempFilterSelection = filterForm[key] ?? []
              return computeDisabledOptions(for: key)
            },
            onSortChange: {
              updateFilteredResults()
            }
          )

          LazyVGrid(columns: columns, spacing: 36) {
            ForEach(filteredResults) { context in
              TorrentCard(context: context, overrideMediaInfo: overrideMediaInfo)
                .focused($focusedItemId, equals: context.id)
            }
          }

          // 焦点重定向器：捕获从不完整行向下导航时的焦点
          Color.clear
            .frame(height: 1)
            .focusable()
            .focused($isBottomRedirectorFocused)
            .onChange(of: isBottomRedirectorFocused) { _, isFocused in
              if isFocused {
                // 将焦点重定向到最后一项
                focusedItemId = filteredResults.last?.id
                isBottomRedirectorFocused = false
              }
            }
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .focusSection()
    .sheet(item: $activeFilter) { config in
      MultiSelectionSheet(
        options: config.options,
        id: \.self,
        selected: $tempFilterSelection,
        label: { $0 },
        disabledOptions: config.disabledOptions,
        disabledOptionsTitle: "已被其他条件筛选"
      )
      .onDisappear {
        // 当 sheet 消失时提交选择
        if tempFilterSelection.isEmpty {
          filterForm.removeValue(forKey: config.id)
        } else {
          filterForm[config.id] = tempFilterSelection
        }
        updateFilteredResults()
      }
    }
    .onChange(of: result.map { $0.id }) { _, _ in
      updateFilterOptions()
      updateFilteredResults()
    }
    .onAppear {
      updateFilterOptions()
      updateFilteredResults()
    }
  }

  // MARK: - 逻辑

  private func updateFilterOptions() {
    var sites = Set<String>()
    var seasons = Set<String>()
    var resolutions = Set<String>()
    var videoCodes = Set<String>()
    var editions = Set<String>()
    var releaseGroups = Set<String>()
    var freeStates = Set<String>()

    for context in result {
      let site = context.torrent_info?.site_name ?? ""
      sites.insert(site.isEmpty ? "无" : site)

      let seasonEpisode = context.meta_info?.season_episode ?? ""
      seasons.insert(seasonEpisode.isEmpty ? "无" : seasonEpisode)

      let res = context.meta_info?.resource_pix ?? ""
      resolutions.insert(res.isEmpty ? "无" : res)

      let code = context.meta_info?.video_encode ?? ""
      videoCodes.insert(code.isEmpty ? "无" : code)

      let edition = context.meta_info?.edition ?? ""
      editions.insert(edition.isEmpty ? "无" : edition)

      let group = context.meta_info?.resource_team ?? ""
      releaseGroups.insert(group.isEmpty ? "无" : group)

      freeStates.insert(getFreeState(context))
    }

    // 辅助排序方法：将"无"放在最后
    let sortWithNoneLast: (Set<String>) -> [String] = { set in
      set.sorted { a, b in
        if a == "无" { return false }
        if b == "无" { return true }
        return a < b
      }
    }

    filterOptions = [
      "site": sortWithNoneLast(sites),
      "season": ParsedSeason.sortSeasonOptions(Array(seasons)),  // "无" 会被解析为 season 0 放最后
      "resolution": sortWithNoneLast(resolutions),
      "videoCode": sortWithNoneLast(videoCodes),
      "edition": sortWithNoneLast(editions),
      "releaseGroup": sortWithNoneLast(releaseGroups),
      "freeState": sortWithNoneLast(freeStates),
    ]
  }

  private func contextMatches(_ context: Context, key: String, values: Set<String>) -> Bool {
    switch key {
    case "site":
      let val = context.torrent_info?.site_name ?? ""
      return values.contains(val.isEmpty ? "无" : val)
    case "season":
      let val = context.meta_info?.season_episode ?? ""
      return values.contains(val.isEmpty ? "无" : val)
    case "resolution":
      let val = context.meta_info?.resource_pix ?? ""
      return values.contains(val.isEmpty ? "无" : val)
    case "videoCode":
      let val = context.meta_info?.video_encode ?? ""
      return values.contains(val.isEmpty ? "无" : val)
    case "edition":
      let val = context.meta_info?.edition ?? ""
      return values.contains(val.isEmpty ? "无" : val)
    case "releaseGroup":
      let val = context.meta_info?.resource_team ?? ""
      return values.contains(val.isEmpty ? "无" : val)
    case "freeState":
      return values.contains(getFreeState(context))
    default:
      return true
    }
  }

  private func computeDisabledOptions(for targetKey: String) -> Set<String> {
    // 1. 过滤 result，但忽略 targetKey 的筛选条件
    let partiallyFiltered = result.filter { context in
      for (key, values) in filterForm where key != targetKey {
        if values.isEmpty { continue }
        if !contextMatches(context, key: key, values: values) { return false }
      }
      return true
    }

    // 2. 从 partiallyFiltered 中收集 targetKey 的所有可用选项
    var availableOptions = Set<String>()
    for context in partiallyFiltered {
      switch targetKey {
      case "site":
        let val = context.torrent_info?.site_name ?? ""
        availableOptions.insert(val.isEmpty ? "无" : val)
      case "season":
        let val = context.meta_info?.season_episode ?? ""
        availableOptions.insert(val.isEmpty ? "无" : val)
      case "resolution":
        let val = context.meta_info?.resource_pix ?? ""
        availableOptions.insert(val.isEmpty ? "无" : val)
      case "videoCode":
        let val = context.meta_info?.video_encode ?? ""
        availableOptions.insert(val.isEmpty ? "无" : val)
      case "edition":
        let val = context.meta_info?.edition ?? ""
        availableOptions.insert(val.isEmpty ? "无" : val)
      case "releaseGroup":
        let val = context.meta_info?.resource_team ?? ""
        availableOptions.insert(val.isEmpty ? "无" : val)
      case "freeState":
        availableOptions.insert(getFreeState(context))
      default:
        break
      }
    }

    // 3. 所有 targetKey 的选项中，不属于 availableOptions 的即为 disabledOptions
    let allOptions = Set(filterOptions[targetKey] ?? [])
    return allOptions.subtracting(availableOptions)
  }

  private func updateFilteredResults() {
    var results = result

    // 1. 筛选
    if !filterForm.isEmpty {
      results = results.filter { context in
        for (key, values) in filterForm {
          if values.isEmpty { continue }
          if !contextMatches(context, key: key, values: values) { return false }
        }
        return true
      }
    }

    // 2. 排序
    results.sort { (lhs, rhs) -> Bool in
      let lInfo = lhs.torrent_info
      let rInfo = rhs.torrent_info

      let isAsc = sortType == .asc

      switch sortField {
      case .size:
        return isAsc ? (lInfo?.size ?? 0 < rInfo?.size ?? 0) : (lInfo?.size ?? 0 > rInfo?.size ?? 0)
      case .seeders:
        return isAsc
          ? (lInfo?.seeders ?? 0 < rInfo?.seeders ?? 0)
          : (lInfo?.seeders ?? 0 > rInfo?.seeders ?? 0)
      case .peers:
        return isAsc
          ? (lInfo?.peers ?? 0 < rInfo?.peers ?? 0) : (lInfo?.peers ?? 0 > rInfo?.peers ?? 0)
      case .time:
        let lDate = lInfo?.pubdate ?? ""
        let rDate = rInfo?.pubdate ?? ""
        return isAsc ? (lDate < rDate) : (lDate > rDate)
      case .default:
        return lhs.torrent_info?.pri_order ?? 0 > rhs.torrent_info?.pri_order ?? 0
      }
    }

    // 如果没有选择特定排序或作为次要排序，是否应用默认排序？
    // 当前逻辑仅替换列表。

    filteredResults = results
  }

  private func getFreeState(_ context: Context) -> String {
    let dl = context.torrent_info?.downloadvolumefactor ?? 1.0
    let up = context.torrent_info?.uploadvolumefactor ?? 1.0

    if dl == 0 {
      if up > 1 { return "2xFree" }
      return "Free"
    }
    if dl < 1.0 {
      return "50%"
    }
    if up > 1.0 {
      return "2x"
    }
    return "Normal"
  }

}

extension TorrentsResultView where Header == EmptyView {
  init(result: [Context], overrideMediaInfo: MediaInfo? = nil) {
    self.init(result: result, overrideMediaInfo: overrideMediaInfo, header: { EmptyView() })
  }
}

// MARK: - 模型

struct FilterConfig: Identifiable {
  let id: String
  let title: String
  let options: [String]
  let disabledOptions: Set<String>
}

// MARK: - 枚举
enum SortField: String, CaseIterable, Identifiable {
  case `default` = "默认"
  case size = "大小"
  case seeders = "做种"
  case peers = "下载"
  case time = "时间"

  var id: String { self.rawValue }
}

enum SortType: String, CaseIterable, Identifiable {
  case asc = "升序"
  case desc = "降序"

  var id: String { self.rawValue }
}

// MARK: - 子视图

struct TorrentFilterBar: View {
  let filterOptions: [String: [String]]
  @Binding var filterForm: [String: Set<String>]
  @Binding var sortField: SortField
  @Binding var sortType: SortType
  @Binding var activeFilter: FilterConfig?
  let totalCount: Int

  var onFilterClick: (String) -> Set<String>
  var onSortChange: () -> Void

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 12) {
        // 总数标签
        Text("\(totalCount) 个资源")
          .font(.caption)
          .padding(.horizontal, 12)
          .padding(.vertical, 6)
          .background(Color.blue.opacity(0.2))
          .foregroundColor(.blue)
          .cornerRadius(20)

        Divider()
          .frame(height: 20)

        // 排序菜单
        Menu {
          Picker("排序字段", selection: $sortField) {
            ForEach(SortField.allCases) { field in
              Text(field.rawValue).tag(field)
            }
          }
          Picker("排序方式", selection: $sortType) {
            ForEach(SortType.allCases) { type in
              Text(type.rawValue).tag(type)
            }
          }
        } label: {
          HStack(spacing: 4) {
            Image(systemName: sortType == .asc ? "arrow.up" : "arrow.down")
            Text(sortField.rawValue)
          }
          .font(.caption)
          .foregroundColor(.primary)
        }
        .onChange(of: sortField) { _, _ in onSortChange() }
        .onChange(of: sortType) { _, _ in onSortChange() }

        Divider()
          .frame(height: 20)

        // 筛选器
        ForEach(filterKeys, id: \.self) { key in
          if let options = filterOptions[key], !options.isEmpty {
            Button {
              let disabled = onFilterClick(key)
              activeFilter = FilterConfig(
                id: key,
                title: filterTitles[key] ?? key,
                options: options,
                disabledOptions: disabled
              )
            } label: {
              HStack(spacing: 4) {
                if let selected = filterForm[key], !selected.isEmpty {
                  Image(systemName: "line.3.horizontal.decrease.circle.fill")
                } else {
                  Image(systemName: "line.3.horizontal.decrease.circle")
                }
                Text(filterTitles[key] ?? key)
                if let selected = filterForm[key], !selected.isEmpty {
                  Text("(\(selected.count))")
                }
              }
              .font(.caption)
              .foregroundColor((filterForm[key]?.isEmpty ?? true) ? .primary : .blue)
            }
          }
        }

        // 清除全部
        let hasActiveFilters = filterForm.values.contains { !$0.isEmpty }
        if hasActiveFilters {
          Button(action: {
            filterForm = [:]
            onSortChange()  // 触发更新
          }) {
            Text("清除筛选")
              .font(.caption)
              .foregroundColor(.red)
          }
        }
      }
      .padding(.vertical, 8)
    }
    .scrollClipDisabled()
  }

  private var filterKeys: [String] {
    ["site", "season", "resolution", "videoCode", "edition", "releaseGroup", "freeState"]
  }

  private var filterTitles: [String: String] {
    [
      "site": "站点",
      "season": "剧集",
      "resolution": "分辨率",
      "videoCode": "编码",
      "edition": "版本",
      "releaseGroup": "制作组",
      "freeState": "促销",
    ]
  }
}
