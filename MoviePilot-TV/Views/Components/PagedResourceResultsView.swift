import SwiftUI

struct PagedResourceResultsView<Header: View>: View {
  @Environment(\.scenePhase) private var scenePhase
  @ObservedObject var search: ResourceSearchSession
  var overrideMediaInfo: MediaInfo? = nil
  var onCancel: () -> Void
  @ViewBuilder var header: () -> Header
  @State private var activeFilter: FilterConfig?
  @State private var selection = Set<String>()
  @State private var downloadPresented = false

  var body: some View {
    Group {
      if search.isBusy { loadingContent }
      else { resultsContent }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .sheet(item: $activeFilter) { config in
      PagedResourceFilterSheet(search: search, config: config, selection: $selection)
        .onDisappear {
          search.filterForm[config.id] = selection.isEmpty ? nil : selection
          search.updateProjection()
        }
    }
    .onChange(of: search.isCollecting) { _, collecting in
      if collecting { activeFilter = nil }
    }
    .onAppear { search.refreshRuleAvailability() }
    .onChange(of: scenePhase) { _, phase in
      if phase != .active { search.deactivate() }
      else { search.refreshRuleAvailability() }
    }
    .onReceive(NotificationCenter.default.publisher(for: .imageNavigationPresentationWillReset, object: APIService.shared)) { _ in
      activeFilter = nil
      search.deactivate()
    }
  }

  private var loadingContent: some View {
    VStack(spacing: 20) {
      header()
      Spacer()
      ProgressView(search.progressText)
      if search.isCollecting && search.progress > 0 {
        ProgressView(value: search.progress, total: 100).frame(width: 360)
      }
      Text("已保留 \(search.retainedCount) 条 · 本次新增 \(search.newCount) 条")
        .font(.caption).foregroundColor(.secondary)
      Button(loadingAction.title) { loadingAction.perform() }
      Spacer()
    }
  }

  var loadingAction: (title: String, perform: () -> Void) {
    if search.canStopAndView { return ("停止并查看", { search.stop() }) }
    if !search.isCollecting && search.rulePending {
      return ("查看已有结果（本次搜索不应用 TV 过滤）", { search.bypassPendingRules() })
    }
    return ("取消", onCancel)
  }

  private var resultsContent: some View {
    ScrollView(.vertical) {
      VStack(spacing: 24) {
        header()
        if search.retainedCount > 0 || search.canContinue || search.canRestart { controls }
        if search.retainedCount > 0 { filterBar }
        if let notice = search.ruleNotice { Text(notice).font(.caption).foregroundColor(.orange) }
        if let error = search.resultErrorMessage, !search.rows.isEmpty {
          Text(error).font(.caption).foregroundColor(.orange)
        }
        if search.rows.isEmpty {
          EmptyDataView(title: "未找到相关资源", systemImage: "magnifyingglass", description: search.emptyDescription)
            .padding(.top, 50)
        } else { resourceGrid }
      }
    }
    .focusSection()
  }

  private var controls: some View {
    HStack(spacing: 24) {
      TorrentResultCount(count: search.rows.count)
      if search.canContinue {
        Button(action: continueSearch) { Label(search.continueTitle, systemImage: "magnifyingglass") }
          .disabled(downloadPresented)
      } else if search.canRestart {
        Button("重新搜索") { search.restart() }.disabled(downloadPresented)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .focusSection()
  }

  private var filterBar: some View {
    TorrentFilterBar(
      filterOptions: search.filterOptions, filterForm: $search.filterForm,
      sortField: $search.sortField, sortType: $search.sortType, activeFilter: $activeFilter,
      onFilterClick: { key in selection = search.filterForm[key] ?? []; return [] },
      onSortChange: { search.updateProjection() },
      onReapplyRules: search.canReapplyRules ? { search.reapplyRules() } : nil
    )
    .disabled(downloadPresented)
  }

  private var resourceGrid: some View {
    VStack {
      TorrentResultsGrid(items: search.rows) { row in card(row) }
    }
  }

  private func card(_ row: ResourceSearchRow) -> some View {
    let continuation: (() -> Void)? = search.canContinue ? { continueSearch() } : nil
    return TorrentCard(context: row.context, overrideMediaInfo: row.downloadMedia(override: overrideMediaInfo),
      isCandidate: row.isCandidate, onContinueSearch: continuation,
      onDownloadPresentationChange: { downloadPresented = $0 })
  }

  private func continueSearch() {
    guard !downloadPresented else { return }
    activeFilter = nil
    search.continueSearch()
  }
}

private struct PagedResourceFilterSheet: View {
  @ObservedObject var search: ResourceSearchSession
  let config: FilterConfig
  @Binding var selection: Set<String>
  @State private var disabled = Set<String>()

  var body: some View {
    MultiSelectionSheet(options: config.options, id: \.self, selected: $selection,
      label: { $0 }, disabledOptions: disabled, disabledOptionsTitle: "已被其他条件筛选")
      .task { disabled = await search.disabledOptions(for: config.id) }
  }
}
