import SwiftUI

struct SearchView: View {
  @StateObject private var viewModel = SearchViewModel()
  @State private var path = NavigationPath()
  @StateObject private var subscriptionHandler = SubscriptionHandler()
  @EnvironmentObject private var mediaActionHandler: MediaActionHandler
  @State private var showSiteSelection = false
  @State private var showMediaSourceSelection = false

  // 焦点管理枚举：定义页面内可获得焦点的区域
  enum Field: Hashable {
    case searchType(SearchType)  // 搜索类型切换按钮（聚合/资源）
    case site(Int)  // 站点筛选按钮
    case mediaSource
  }
  @FocusState private var focusedField: Field?
  @State private var lastFocusedField: Field?

  // TV 端特有的焦点重定向器：用于在原生搜索栏和自定义内容之间平滑过渡焦点
  @FocusState private var isTopRedirectorFocused: Bool
  @FocusState private var isBottomRedirectorFocused: Bool

  private var visibleFilterSearchType: SearchType {
    switch focusedField ?? lastFocusedField {
    case .searchType(let type):
      return type
    case .site:
      return .resource
    case .mediaSource:
      return .unified
    case nil:
      return viewModel.searchType
    }
  }

  private var shouldShowSiteFilter: Bool {
    visibleFilterSearchType == .resource
  }

  private var shouldShowMediaSourceFilter: Bool {
    visibleFilterSearchType == .unified
  }

  /// 定义可用的搜索类型
  private var availableSearchTypes: [SearchType] {
    viewModel.availableSearchTypes
  }

  /// 搜索页眉：包含搜索类型切换组和站点过滤器
  @ViewBuilder
  private var searchHeader: some View {
    VStack(spacing: 0) {
      // 焦点重定向：捕获从系统原生搜索栏向下的焦点
      Color.clear
        .frame(height: 1)
        .focusable(focusedField == nil)
        .focused($isTopRedirectorFocused)
        .onChange(of: isTopRedirectorFocused) { _, isFocused in
          if isFocused {
            focusedField = .searchType(viewModel.searchType)
            isTopRedirectorFocused = false
          }
        }

      HStack(spacing: 30) {
        ZStack(alignment: .trailing) {
          // 聚合搜索来源按钮放在左侧，不影响中间搜索类型按钮的位置。
          if shouldShowMediaSourceFilter {
            Button(action: {
              showMediaSourceSelection = true
            }) {
              HStack(spacing: 8) {
                Image(systemName: "server.rack")
                Text("搜索来源：\(viewModel.mediaSourceButtonLabel)")
              }
              .font(.caption)
              .foregroundColor(.primary)
            }
            .controlSize(.small)
            .focused($focusedField, equals: .mediaSource)
            .transition(.move(edge: .trailing).combined(with: .opacity))
          }
        }
        .frame(width: 300, alignment: .trailing)

        // A. 搜索类型按钮组 (聚合 / 资源)
        HStack(spacing: 20) {
          ForEach(availableSearchTypes.indices, id: \.self) { index in
            let type = availableSearchTypes[index]
            Button(action: {
              viewModel.searchType = type
              Task { await viewModel.autoSearch() }
            }) {
              HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                Text(type.rawValue)
              }
            }
            .focused($focusedField, equals: .searchType(type))
            .foregroundColor(.primary)

            if index < availableSearchTypes.count - 1 {
              Divider()
                .frame(height: 36)
            }
          }
        }

        ZStack(alignment: .leading) {
          // B. 站点筛选按钮：仅在资源搜索模式且满足显示条件时可见
          if shouldShowSiteFilter {
            Button(action: {
              showSiteSelection = true
            }) {
              HStack(spacing: 8) {
                Image(systemName: "server.rack")
                Text(viewModel.siteFilter.siteButtonLabel)
              }
              .font(.caption)
              .foregroundColor(.primary)
            }
            .controlSize(.small)
            .focused($focusedField, equals: .site(0))
            .transition(.move(edge: .leading).combined(with: .opacity))
          }
        }
        .frame(width: 300, alignment: .leading)
      }
      .frame(maxWidth: .infinity)
      .animation(.snappy, value: shouldShowSiteFilter)
      .animation(.snappy, value: shouldShowMediaSourceFilter)
      .padding(.vertical, 0)

      // 焦点重定向：捕获从下方结果列表向上的焦点
      Color.clear
        .frame(height: 1)
        .focusable(focusedField == nil)
        .focused($isBottomRedirectorFocused)
        .onChange(of: isBottomRedirectorFocused) { _, isFocused in
          if isFocused {
            focusedField = .searchType(viewModel.searchType)
            isBottomRedirectorFocused = false
          }
        }
    }
  }

  var body: some View {
    NavigationStack(path: $path) {
      Group {
        if viewModel.isLoading {
          VStack {
            searchHeader
            Spacer()
            if viewModel.searchType == .resource {
              VStack(spacing: 20) {
                ProgressView(viewModel.searchProgressText)
                if viewModel.searchProgress > 0 {
                  ProgressView(value: viewModel.searchProgress, total: 100)
                    .progressViewStyle(.linear)
                    .frame(width: 300)
                }
              }
            } else {
              ProgressView()
            }
            Spacer()
          }
        } else {
          switch viewModel.searchType {
          case .resource:
            if viewModel.hasSearched {
              TorrentsResultView(
                result: viewModel.resourceResults,
                emptyDescription: viewModel.resourceErrorMessage,
                header: { searchHeader }
              )
            } else {
              VStack {
                searchHeader
                Spacer()
              }
            }
          case .unified:
            UnifiedSearchResult(
              viewModel: viewModel,
              navigationPath: $path,
              header: { searchHeader },
              onShareTapped: { share in
                guard APIService.shared.canAccess(.subscribe) else { return }
                subscriptionHandler.forkSheetRequest = share
              }
            )
          }
        }
      }
      .navigationDestination(for: MediaInfo.self) { detail in
        if let collectionId = detail.collection_id {
          CollectionDetailView(
            title: detail.title ?? "合集详情",
            collectionId: collectionId,
            navigationPath: $path
          )
        } else {
          MediaDetailContainerView(media: detail, navigationPath: $path)
        }
      }
      .navigationDestination(for: Person.self) { person in
        PersonDetailView(person: person, navigationPath: $path)
      }
      .navigationDestination(for: ResourceSearchRequest.self) { request in
        ResourceResultView(request: request)
      }
      .navigationDestination(for: SubscribeSeasonRequest.self) { request in
        SubscribeSeasonView(
          mediaInfo: request.mediaInfo,
          initialSeason: request.initialSeason,
          initialEpisodeGroup: request.initialEpisodeGroup
        )
      }
      .mediaSubscriptionAlerts(using: subscriptionHandler, navigationPath: $path)
      .sheet(item: $subscriptionHandler.forkSheetRequest) { share in
        ForkSubscribeSheet(
          share: share,
          onFork: { newSubId in
            Task {
              await subscriptionHandler.fetchSubscriptionAndShowEditor(subId: newSubId)
            }
          },
          subscriptionHandler: subscriptionHandler
        )
      }
      .sheet(isPresented: $showSiteSelection) {
        MultiSelectionSheet(
          options: viewModel.siteFilter.availableSites,
          id: \.id,
          selected: $viewModel.siteFilter.selectedSites,
          label: { $0.name }
        )
      }
      .sheet(isPresented: $showMediaSourceSelection) {
        MediaSourceSelectionSheet(selected: $viewModel.mediaSearchSource)
      }
      // 使用原生搜索栏
      .searchable(text: $viewModel.query, placement: .automatic, prompt: "电影、节目、演职人员等")
      .task {
        viewModel.normalizeSearchTypeForPermissions()
        if viewModel.availableSearchTypes.contains(.resource) {
          await viewModel.siteFilter.loadSites()
        }
      }
      .onChange(of: focusedField) { _, newValue in
        if let newValue = newValue {
          lastFocusedField = newValue
        }
      }
    }
    .environmentObject(subscriptionHandler)
  }

}

private struct MediaSourceSelectionSheet: View {
  @Binding var selected: MediaSearchSource?
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack {
          sourceButton("默认", source: nil)
          ForEach(MediaSearchSource.allowed(for: .media)) { source in
            sourceButton(source.title, source: source)
          }
        }
        .applySheetStyles()
        .padding(28)
      }
    }
  }

  private func sourceButton(_ title: String, source: MediaSearchSource?) -> some View {
    Button {
      selected = source
      dismiss()
    } label: {
      HStack {
        Text(title)
        Spacer()
        if selected == source {
          Image(systemName: "checkmark")
        }
      }
    }
  }
}

// MARK: - 聚合搜索结果
struct UnifiedSearchResult<Header: View>: View {
  @ObservedObject var viewModel: SearchViewModel
  @Binding var navigationPath: NavigationPath
  let header: Header
  let onShareTapped: (SubscribeShare) -> Void

  @State private var scrollPosition: String?

  init(
    viewModel: SearchViewModel,
    navigationPath: Binding<NavigationPath>,
    @ViewBuilder header: () -> Header,
    onShareTapped: @escaping (SubscribeShare) -> Void
  ) {
    self.viewModel = viewModel
    self._navigationPath = navigationPath
    self.header = header()
    self.onShareTapped = onShareTapped
  }

  private var hasAnyResults: Bool {
    !(viewModel.moviePaginator?.items.isEmpty ?? true)
      || !(viewModel.tvPaginator?.items.isEmpty ?? true)
      || !(viewModel.collectionPaginator?.items.isEmpty ?? true)
      || !(viewModel.personPaginator?.items.isEmpty ?? true)
      || !(viewModel.subscriptionSharePaginator?.items.isEmpty ?? true)
  }

  @ViewBuilder
  private func mediaResultRow(
    title: String,
    rowId: String,
    items: [MediaInfo],
    paginator: Paginator<MediaInfo>?
  ) -> some View {
    if !items.isEmpty {
      ResultRow(
        title: title,
        rowId: rowId,
        items: items,
        isLoadingMore: paginator?.isLoadingMore ?? false,
        navigationPath: $navigationPath,
        onLoadMore: { focusedId in
          Task { await paginator?.loadMore(focusedId) }
        },
        scrollPosition: $scrollPosition,
        onShareTapped: onShareTapped
      )
      .id(rowId)
    }
  }

  var body: some View {
    ScrollView(.vertical) {
      VStack(spacing: 30) {
        header
          .id("header")

        if !hasAnyResults && viewModel.hasSearched {
          Text("未找到相关结果")
            .font(.callout)
            .foregroundColor(.secondary)
            .padding(.top, 50)
            .focusable()
        } else {
          // 最佳结果
          let bestResults = viewModel.bestResults
          if !bestResults.isEmpty {
            BestResultRow(
              title: "最佳结果",
              items: bestResults,
              navigationPath: $navigationPath,
              scrollPosition: $scrollPosition,
              onShareTapped: onShareTapped
            )
            .id("best")
          }
        }

        // 订阅分享结果行
        mediaResultRow(
          title: "订阅分享",
          rowId: "shares",
          items: viewModel.subscriptionSharePaginator?.items ?? [],
          paginator: viewModel.subscriptionSharePaginator
        )

        // 电影、电视剧、系列结果行
        mediaResultRow(
          title: "电影",
          rowId: "movies",
          items: viewModel.moviePaginator?.items ?? [],
          paginator: viewModel.moviePaginator
        )

        mediaResultRow(
          title: "电视剧",
          rowId: "tv",
          items: viewModel.tvPaginator?.items ?? [],
          paginator: viewModel.tvPaginator
        )

        mediaResultRow(
          title: "系列",
          rowId: "collections",
          items: viewModel.collectionPaginator?.items ?? [],
          paginator: viewModel.collectionPaginator
        )

        // 人物结果行
        let personResults = viewModel.personPaginator?.items ?? []
        if !personResults.isEmpty {
          PersonResultRow(
            title: "演职人员",
            rowId: "persons",
            items: personResults,
            isLoadingMore: viewModel.personPaginator?.isLoadingMore ?? false,
            navigationPath: $navigationPath,
            onLoadMore: { focusedId in
              Task { await viewModel.personPaginator?.loadMore(focusedId) }
            },
            scrollPosition: $scrollPosition
          )
          .id("persons")
        }
      }
      .scrollTargetLayout()
    }
    .scrollPosition(id: $scrollPosition, anchor: .center)
    .animation(.snappy, value: scrollPosition)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .focusSection()
  }
}

// MARK: - 媒体/系列结果行
private struct ResultRow: View {
  let title: String
  let rowId: String
  let items: [MediaInfo]
  let isLoadingMore: Bool
  @Binding var navigationPath: NavigationPath
  let onLoadMore: (MediaInfo.ID?) -> Void
  @Binding var scrollPosition: String?
  let onShareTapped: (SubscribeShare) -> Void
  @EnvironmentObject var subscriptionHandler: SubscriptionHandler

  @FocusState private var focusedItemId: MediaInfo.ID?
  /// 预加载防抖任务：避免快速滚动时触发过多无效请求
  @State private var preloadDebounceTask: Task<Void, Never>?

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(title)
        .font(.callout)
        .fontWeight(.bold)
        .foregroundStyle(.secondary)
        .padding(.leading, 8)

      ScrollView(.horizontal, showsIndicators: false) {
        LazyHStack(spacing: 40) {
          ForEach(items) { item in
            MediaCard(
              title: item.cleanedTitle ?? "",
              posterUrl: item.imageURLs.poster,
              typeText: item.displayTypeText,
              ratingText: item.vote_average.map { String(format: "%.1f", $0) },
              bottomLeftText: nil,
              bottomLeftSecondaryText: nil,
              source: MediaSource.from(mediaInfo: item),
              action: {
                if let share = item.subscribeShare {
                  onShareTapped(share)
                } else {
                  preloadDebounceTask?.cancel()
                  MediaPreloader.shared.preload(for: item)
                  navigationPath.append(item)
                }
              }
            )
            .focused($focusedItemId, equals: item.id)
            .mediaContextMenu(
              item: item,
              navigationPath: $navigationPath
            )
          }

          if isLoadingMore {
            posterCenteredLoadingIndicator(height: 384)
          }
        }
        .padding(.top, 25)
        .padding(.bottom, 30)
        .onChange(of: focusedItemId) { _, newId in
          // 预加载触发：聚焦后延迟 ~300ms，防止快速滚动时浪费请求
          preloadDebounceTask?.cancel()
          if let newId = newId, let item = items.first(where: { $0.id == newId }) {
            // 只有带 collection_id 的合集走 CollectionDetailView，不预加载普通详情。
            // collection-like type 但缺少 collection_id 时仍按普通媒体处理，和 Web 保持一致。
            if item.shouldPreloadDetail {
              preloadDebounceTask = Task {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                MediaPreloader.shared.preload(for: item)
              }
            }
            // 分页加载
            scrollPosition = rowId
            onLoadMore(newId)
          }
        }
      }
      .scrollClipDisabled()
      .focusSection()
    }
  }

  private func posterCenteredLoadingIndicator(height: CGFloat) -> some View {
    VStack(spacing: 10) {
      ProgressView()
        .frame(width: 100, height: height)
      Color.clear
        .frame(width: 100, height: 44)
    }
  }
}

// MARK: - 人物结果行
private struct PersonResultRow: View {
  let title: String
  let rowId: String
  let items: [Person]
  let isLoadingMore: Bool
  @Binding var navigationPath: NavigationPath
  let onLoadMore: (Person.ID?) -> Void
  @Binding var scrollPosition: String?

  @FocusState private var focusedItemId: Person.ID?

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(title)
        .font(.callout)
        .fontWeight(.bold)
        .foregroundStyle(.secondary)
        .padding(.leading, 8)

      ScrollView(.horizontal, showsIndicators: false) {
        LazyHStack(spacing: 40) {
          ForEach(items) { item in
            PersonCard(person: item) {
              navigationPath.append(item)
            }
            .focused($focusedItemId, equals: item.id)
            .compositingGroup()
            .contextMenu {
              Button {
                navigationPath.append(item)
              } label: {
                Label("详情", systemImage: "info.circle")
              }
            }
          }

          if isLoadingMore {
            posterCenteredLoadingIndicator(height: 315)
          }
        }
        .padding(.top, 25)
        .padding(.bottom, 30)
        .onChange(of: focusedItemId) { _, newId in
          if let newId = newId {
            scrollPosition = rowId
            onLoadMore(newId)
          }
        }
      }
      .scrollClipDisabled()
      .focusSection()
    }
  }

  private func posterCenteredLoadingIndicator(height: CGFloat) -> some View {
    VStack(spacing: 10) {
      ProgressView()
        .frame(width: 100, height: height)
      Color.clear
        .frame(width: 100, height: 44)
    }
  }
}

// MARK: - 最佳结果行
private struct BestResultRow: View {
  let title: String
  let items: [BestResultItem]
  @Binding var navigationPath: NavigationPath
  @Binding var scrollPosition: String?
  let onShareTapped: (SubscribeShare) -> Void
  @EnvironmentObject var subscriptionHandler: SubscriptionHandler
  @FocusState private var focusedItemId: String?
  /// 预加载防抖任务：避免快速滚动时触发过多无效请求
  @State private var preloadDebounceTask: Task<Void, Never>?

  private var gridRows: [GridItem] {
    if items.count <= 3 {
      return [GridItem(.fixed(190))]
    } else {
      return [GridItem(.fixed(190), spacing: 26), GridItem(.fixed(190))]
    }
  }

  private func sourceText(for source: String?) -> String {
    switch source {
    case "themoviedb": return "TMDB"
    case "douban": return "豆瓣"
    case "bangumi": return "Bangumi"
    case "anilist": return "AniList"
    default: return source ?? ""
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(title)
        .font(.callout)
        .fontWeight(.bold)
        .foregroundStyle(.secondary)
        .padding(.leading, 8)

      ScrollView(.horizontal, showsIndicators: false) {
        LazyHGrid(rows: gridRows, spacing: 26) {
          ForEach(items) { item in
            switch item {
            case .media(let media):
              let sourceStr = sourceText(for: media.source)
              let typeStr = media.subscribeShare != nil ? "订阅分享" : media.type
              let subtitleParts = [typeStr, media.year, sourceStr].compactMap { $0 }.filter {
                !$0.isEmpty
              }
              let subtitle = subtitleParts.joined(separator: " · ")

              BestResultCard(
                title: media.cleanedTitle ?? "",
                type: media.type,
                posterUrl: media.imageURLs.poster,
                subtitle: subtitle,
                action: {
                  if let share = media.subscribeShare {
                    onShareTapped(share)
                  } else {
                    preloadDebounceTask?.cancel()
                    MediaPreloader.shared.preload(for: media)
                    navigationPath.append(media)
                  }
                }
              )
              .focused($focusedItemId, equals: item.id)
              .mediaContextMenu(
                item: media,
                navigationPath: $navigationPath
              )
            case .person(let person):
              let sourceStr = sourceText(for: person.source)
              let jobOrChar =
                (person.job != nil && !person.job!.isEmpty) ? person.job : person.character
              let subtitleParts = ["人物", jobOrChar, sourceStr].compactMap { $0 }.filter {
                !$0.isEmpty
              }
              let subtitle = subtitleParts.joined(separator: " · ")

              BestResultCard(
                title: person.name ?? "未知",
                type: "人物",
                posterUrl: person.imageURLs.profile,
                subtitle: subtitle,
                action: { navigationPath.append(person) }
              )
              .focused($focusedItemId, equals: item.id)
              .compositingGroup()
              .contextMenu {
                Button {
                  navigationPath.append(person)
                } label: {
                  Label("详情", systemImage: "info.circle")
                }
              }
            }
          }
        }
        .padding(.top, 25)
        .padding(.bottom, 30)
      }
      .scrollClipDisabled()
      .focusSection()
      .onChange(of: focusedItemId) { _, newId in
        // 预加载触发：聚焦后延迟 ~300ms，防止快速滚动时浪费请求
        preloadDebounceTask?.cancel()
        if let newId = newId, let item = items.first(where: { $0.id == newId }) {
          // 仅对媒体类型预加载，人物类型走 PersonDetailView，不需要 MediaPreloader
          if case .media(let media) = item, media.shouldPreloadDetail {
            preloadDebounceTask = Task {
              try? await Task.sleep(for: .milliseconds(300))
              guard !Task.isCancelled else { return }
              MediaPreloader.shared.preload(for: media)
            }
          }
          scrollPosition = "best"
        }
      }
    }
    .padding(.top, 0)
  }
}
