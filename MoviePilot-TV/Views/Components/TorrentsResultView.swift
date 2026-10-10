import SwiftUI

struct TorrentsResultView<Header: View>: View {
  let result: [Context]
  var overrideMediaInfo: MediaInfo? = nil
  var emptyDescription: String? = nil
  let header: Header

  // 筛选与排序状态
  @State private var filterForm: [String: Set<String>] = [:]
  @State private var sortField: SortField = .default
  @State private var sortType: SortType = .default

  // Sheet 状态
  @State private var activeFilter: FilterConfig?
  @State private var tempFilterSelection: Set<String> = []

  // 计算/缓存状态
  @State private var filterOptions: [String: [String]] = [:]
  @State private var filteredResults: [Context] = []

  init(
    result: [Context],
    overrideMediaInfo: MediaInfo? = nil,
    emptyDescription: String? = nil,
    @ViewBuilder header: () -> Header
  ) {
    self.result = result
    self.overrideMediaInfo = overrideMediaInfo
    self.emptyDescription = emptyDescription
    self.header = header()
  }

  var body: some View {
    ScrollView(.vertical) {
      VStack(spacing: 20) {
        header

        if !result.isEmpty {
          TorrentResultCount(count: filteredResults.count)
            .frame(maxWidth: .infinity, alignment: .leading)
          TorrentFilterBar(
            filterOptions: filterOptions,
            filterForm: $filterForm,
            sortField: $sortField,
            sortType: $sortType,
            activeFilter: $activeFilter,
            onFilterClick: { key in
              // 打开 sheet 时初始化临时选择
              tempFilterSelection = filterForm[key] ?? []
              return computeDisabledOptions(for: key)
            },
            onSortChange: {
              updateFilteredResults()
            }
          )
        }

        if result.isEmpty {
          EmptyDataView(
            title: "未找到相关资源",
            systemImage: "magnifyingglass",
            description: emptyDescription
          )
          .padding(.top, 50)
        } else {
          TorrentResultsGrid(items: filteredResults, alignment: .top) { context in
            TorrentCard(context: context, overrideMediaInfo: overrideMediaInfo)
          }
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .focusSection()
    .onReceive(NotificationCenter.default.publisher(for: .imageNavigationPresentationWillReset, object: APIService.shared)) { _ in activeFilter = nil }
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

  static func normalizedFilterOption(_ value: String?) -> String {
    ResourceResultSemantics.normalized(value)
  }

  static func freeStateValue(_ context: Context) -> String? {
    ResourceResultSemantics.freeState(context)
  }

  private func updateFilterOptions() {
    var options: [String: Set<String>] = [:]
    for context in result {
      for (key, value) in ResourceResultSemantics.fields(context) {
        options[key, default: []].insert(value)
      }
    }
    filterOptions = ResourceResultSemantics.sortedOptions(options.mapValues(Array.init))
  }

  private func computeDisabledOptions(for targetKey: String) -> Set<String> {
    let other = filterForm.filter { $0.key != targetKey }
    let available = Set(result.compactMap { context -> String? in
      let fields = ResourceResultSemantics.fields(context)
      return ResourceResultSemantics.matches(fields, filters: other) ? fields[targetKey] : nil
    })
    return Set(filterOptions[targetKey] ?? []).subtracting(available)
  }

  private func updateFilteredResults() {
    let results = filterForm.isEmpty ? result : result.filter {
      ResourceResultSemantics.matches(ResourceResultSemantics.fields($0), filters: filterForm)
    }
    filteredResults = Self.orderResults(results, by: sortField, type: sortType)
  }

  static func orderResults(_ results: [Context], by sortField: SortField, type sortType: SortType) -> [Context] {
    guard sortType != .default else {
      return results.filter { !$0.isFilteredOut } + results.filter { $0.isFilteredOut }
    }
    let inputs = results.enumerated().map { ResourceFilterInput(context: $0.element, order: $0.offset) }
    return results.indices.sorted { a, b in
      ResourceResultSemantics.before(inputs[a], softRejected: results[a].isFilteredOut,
        inputs[b], softRejected: results[b].isFilteredOut, sortField: sortField.rawValue, sortType: sortType.rawValue)
    }.map { results[$0] }
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
  case `default` = "默认排序"
  case asc = "升序"
  case desc = "降序"

  var id: String { self.rawValue }
}

// MARK: - 子视图

struct TorrentResultCount: View {
  let count: Int

  var body: some View {
    Text("\(count) 个资源")
      .font(.caption)
      .padding(.horizontal, 12)
      .padding(.vertical, 6)
      .background(Color.blue.opacity(0.2))
      .foregroundColor(.blue)
      .cornerRadius(20)
  }
}

struct TorrentFilterBar: View {
  let filterOptions: [String: [String]]
  @Binding var filterForm: [String: Set<String>]
  @Binding var sortField: SortField
  @Binding var sortType: SortType
  @Binding var activeFilter: FilterConfig?

  var onFilterClick: (String) -> Set<String>
  var onSortChange: () -> Void
  var onReapplyRules: (() -> Void)? = nil

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 12) {
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
            if sortType == .asc {
              Image(systemName: "arrow.up")
            } else if sortType == .desc {
              Image(systemName: "arrow.down")
            }
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
        if let onReapplyRules {
          Button("重新应用 TV 过滤", action: onReapplyRules)
            .font(.caption)
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

/// 共用网格和底部焦点重定向，条目身份与卡片动作由各搜索入口提供。
struct TorrentResultsGrid<Item: Identifiable, Card: View>: View {
  let items: [Item]
  var alignment: Alignment = .center
  @ViewBuilder var card: (Item) -> Card
  @FocusState private var focusedItem: Item.ID?
  @FocusState private var bottomFocused: Bool

  var body: some View {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 500, maximum: 600), spacing: 36, alignment: alignment)], spacing: 36) {
      ForEach(items) { item in
        card(item).focused($focusedItem, equals: item.id)
      }
    }
    Color.clear.frame(height: 1).focusable().focused($bottomFocused)
      .onChange(of: bottomFocused) { _, focused in
        if focused { focusedItem = items.last?.id; bottomFocused = false }
      }
  }
}
