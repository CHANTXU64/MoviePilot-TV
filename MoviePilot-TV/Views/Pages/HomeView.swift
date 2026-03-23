import SwiftUI

@MainActor
struct HomeView: View {
  @StateObject private var viewModel: HomeViewModel

  // Sheet 状态
  @State private var selectedSubscribe: Subscribe?

  // 导航状态
  @State private var path = NavigationPath()

  init(viewModel: HomeViewModel? = nil) {
    _viewModel = StateObject(wrappedValue: viewModel ?? HomeViewModel())
  }

  var body: some View {
    NavigationStack(path: $path) {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 30) {
          if viewModel.isLoading {
            ProgressView()
              .frame(maxWidth: .infinity, minHeight: 200)
          } else {
            // 第1节：最近添加
            if !viewModel.latestMedia.isEmpty {
              MediaSectionView(
                title: "最近添加",
                items: viewModel.latestMedia,
                isFirstRow: true,
                viewModel: viewModel
              )
            }

            // 第2节：电影订阅
            if !viewModel.movieSubscriptions.isEmpty {
              SubscribeSectionView(
                title: "电影订阅",
                items: viewModel.movieSubscriptions,
                isFirstRow: viewModel.latestMedia.isEmpty,
                viewModel: viewModel,
                onEdit: presentEditSheet,
                onViewDetail: navigateToDetail
              )
            }

            // 第3节：电视剧订阅
            if !viewModel.tvSubscriptions.isEmpty {
              SubscribeSectionView(
                title: "电视剧订阅",
                items: viewModel.tvSubscriptions,
                isFirstRow: viewModel.latestMedia.isEmpty && viewModel.movieSubscriptions.isEmpty,
                viewModel: viewModel,
                onEdit: presentEditSheet,
                onViewDetail: navigateToDetail
              )
            }

            if viewModel.latestMedia.isEmpty && viewModel.movieSubscriptions.isEmpty
              && viewModel.tvSubscriptions.isEmpty
            {
              Text("暂无内容")
                .font(.headline)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, minHeight: 200)
            }
          }
        }
      }
      .task {
        // TODO: 考虑增加刷新频率限制或检查数据新鲜度，避免频繁进入退出详情页时重复请求首页数据
        // 每次页面出现时都请求刷新，ViewModel 内部会决定是否需要显示全屏 Loading（避免重建视图树导致焦点丢失）
        await viewModel.loadData()
      }
      // 编辑订阅 Sheet
      .sheet(item: $selectedSubscribe) { subscribe in
        SubscribeSheet(subscribe: subscribe)
          .onDisappear {
            // 刷新数据在编辑之后
            Task {
              await viewModel.refreshData()
            }
          }
      }
      // 导航目的地
      .navigationDestination(for: MediaInfo.self) { mediaInfo in
        MediaDetailContainerView(media: mediaInfo, navigationPath: $path)
      }
      .navigationDestination(for: Person.self) { person in
        PersonDetailView(
          person: person,
          navigationPath: $path
        )
      }
      .navigationDestination(for: ResourceSearchRequest.self) { request in
        ResourceResultView(request: request)
      }
      .navigationDestination(for: SubscribeSeasonRequest.self) { request in
        SubscribeSeasonView(mediaInfo: request.mediaInfo, initialSeason: request.initialSeason)
      }
    }
  }

  // MARK: - 动作

  private func presentEditSheet(for subscribe: Subscribe) {
    self.selectedSubscribe = subscribe
  }

  private func navigateToDetail(for subscribe: Subscribe) {
    let mediaInfo = MediaInfo(
      tmdb_id: subscribe.tmdbid,
      douban_id: subscribe.doubanid,
      bangumi_id: subscribe.bangumiid,
      imdb_id: nil,
      tvdb_id: nil,
      source: nil,
      mediaid_prefix: nil,
      media_id: nil,
      title: subscribe.name,
      original_title: nil,
      original_name: nil,
      names: nil,
      type: subscribe.type,
      year: subscribe.year,
      season: subscribe.season,
      // 必须将图像路径设为 nil，以确保导航对象是“干净”的。
      // 如果携带了 poster_path，详情页会先用它作为背景，
      // 然后在加载完完整的 backdrop_path 后再切换，导致闪烁。
      poster_path: nil,
      backdrop_path: nil,
      overview: subscribe.description,
      vote_average: nil,
      popularity: nil,
      season_info: nil,
      collection_id: nil,
      directors: nil,
      actors: nil,
      episode_group: subscribe.episode_group,
      runtime: nil,
      release_date: nil,
      original_language: nil,
      production_countries: nil,
      genres: nil,
      category: nil
    )
    path.append(mediaInfo)
  }
}

// MARK: - 子视图

private struct MediaSectionView: View {
  let title: String
  let items: [MediaServerPlayItem]
  var isFirstRow: Bool = false
  @ObservedObject var viewModel: HomeViewModel

  @Environment(\.openURL) private var openURL
  @FocusState private var focusedItemId: String?
  @FocusState private var isTopRedirectorFocused: Bool
  @State private var hasRedirectedFocus: Bool = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(title)
        .font(.callout)
        .fontWeight(.bold)
        .foregroundStyle(.secondary)
        .padding(.leading, 8)

      if isFirstRow {
        // 顶部焦点重定向器：确保在首次加载时来自标签栏的焦点进入第一个项目，然后禁用自身。
        Color.clear
          .frame(height: 1)
          .focusable(!hasRedirectedFocus)
          .focused($isTopRedirectorFocused)
          .onChange(of: isTopRedirectorFocused) { _, isFocused in
            if isFocused {
              focusedItemId = items.first?.id
              hasRedirectedFocus = true
              isTopRedirectorFocused = false
            }
          }
      }

      ScrollView(.horizontal, showsIndicators: false) {
        LazyHStack(spacing: 40) {
          ForEach(items) { item in
            MediaCard(
              title: item.title,
              posterUrl: item.imageURLs.image,
              typeText: item.type,
              ratingText: nil,
              bottomLeftText: item.server_type?.rawValue.capitalized,
              bottomLeftSecondaryText: nil,
              source: nil,
              action: {
                viewModel.openMediaItem(item, using: openURL)
              }
            )
            .focused($focusedItemId, equals: item.id)
          }
        }
        .padding(.top, 25)
        .padding(.bottom, 30)
      }
      .scrollClipDisabled()
      .focusSection()
    }
  }
}

private struct SubscribeSectionView: View {
  let title: String
  let items: [Subscribe]
  var isFirstRow: Bool = false
  @ObservedObject var viewModel: HomeViewModel
  let onEdit: (Subscribe) -> Void
  let onViewDetail: (Subscribe) -> Void

  @FocusState private var focusedItemId: String?
  @FocusState private var isTopRedirectorFocused: Bool
  @State private var hasRedirectedFocus: Bool = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(title)
        .font(.callout)
        .fontWeight(.bold)
        .foregroundStyle(.secondary)
        .padding(.leading, 8)

      if isFirstRow {
        // 顶部焦点重定向器：确保在首次加载时来自上方的焦点进入第一个项目，然后禁用自身。
        Color.clear
          .frame(height: 1)
          .focusable(!hasRedirectedFocus)
          .focused($isTopRedirectorFocused)
          .onChange(of: isTopRedirectorFocused) { _, isFocused in
            if isFocused {
              focusedItemId = items.first?.id.map { String($0) }
              hasRedirectedFocus = true
              isTopRedirectorFocused = false
            }
          }
      }

      ScrollView(.horizontal, showsIndicators: false) {
        LazyHStack(spacing: 40) {
          ForEach(items) { item in
            SubscribeItemView(
              item: item,
              viewModel: viewModel,
              onEdit: { onEdit(item) },
              onViewDetail: { onViewDetail(item) }
            )
            .focused($focusedItemId, equals: String(describing: item.id))
          }
        }
        .padding(.top, 25)
        .padding(.bottom, 30)
      }
      .scrollClipDisabled()
      .focusSection()
    }
  }
}

private struct SubscribeItemView: View {
  let item: Subscribe
  @ObservedObject var viewModel: HomeViewModel
  let onEdit: () -> Void
  let onViewDetail: () -> Void

  var body: some View {
    MediaCard(
      title: item.name,
      posterUrl: item.imageURLs.poster,
      typeText: formatState(item.state),
      ratingText: nil,
      bottomLeftText: formatProgress(total: item.total_episode, lack: item.lack_episode),
      bottomLeftSecondaryText: item.last_update?.toRelativeDateString() ?? nil,
      source: nil,
      action: {
        onEdit()
      }
    )
    .compositingGroup()
    .contextMenu {
      // 1. 编辑订阅
      Button {
        onEdit()
      } label: {
        Label("编辑订阅", systemImage: "pencil")
      }

      // 2. 详情
      Button {
        onViewDetail()
      } label: {
        Label("详情", systemImage: "info.circle")
      }

      // 3. 搜索订阅
      Button {
        Task {
          _ = await viewModel.searchSubscribe(subscribe: item)
        }
      } label: {
        Label("搜索订阅", systemImage: "magnifyingglass")
      }

      // 4. 启用/暂停
      Button {
        Task {
          _ = await viewModel.toggleSubscribeStatus(subscribe: item)
        }
      } label: {
        if item.state == "S" {
          Label("启用订阅", systemImage: "play.fill")
        } else {
          Label("暂停订阅", systemImage: "pause.fill")
        }
      }

      // 5. 重置订阅
      Button {
        Task {
          _ = await viewModel.resetSubscribe(subscribe: item)
        }
      } label: {
        Label("重置订阅", systemImage: "arrow.counterclockwise")
      }

      Divider()

      // 6. 取消订阅
      Button(role: .destructive) {
        Task {
          _ = await viewModel.deleteSubscribe(subscribe: item)
        }
      } label: {
        Label("取消订阅", systemImage: "trash")
      }
    }
  }

  // 辅助格式化函数
  func formatProgress(total: Int?, lack: Int?) -> String? {
    guard let total = total, total > 0 else { return nil }
    if let lack = lack, lack > 0 {
      return "\(total - lack) / \(total)"
    }
    return "已完结"
  }

  func formatState(_ state: String?) -> String? {
    switch state {
    case "N": return "新"
    case "R": return "阅"
    case "P": return "待"
    case "S": return "停"
    default: return state
    }
  }
}
