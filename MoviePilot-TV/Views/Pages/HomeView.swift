import SwiftUI

@MainActor
struct HomeView: View {
  private let isSelected: Bool
  @StateObject private var viewModel: HomeViewModel
  @ObservedObject private var apiService = APIService.shared
  @Environment(\.scenePhase) private var scenePhase

  // Sheet 状态
  @State private var selectedSubscribe: Subscribe?

  // 导航状态
  @StateObject private var navigationCoordinator = ImageNavigationCoordinator()

  init(isSelected: Bool = true, viewModel: HomeViewModel? = nil) {
    self.isSelected = isSelected
    _viewModel = StateObject(wrappedValue: viewModel ?? HomeViewModel())
  }

  var body: some View {
    NavigationStack(path: $navigationCoordinator.path) {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 30) {
          if viewModel.isLoading {
            ProgressView()
              .frame(maxWidth: .infinity, minHeight: 200)
          } else {
            // 部分数据失败：保留旧快照并提示（成功空不算失败）
            if viewModel.latestLoadFailed || viewModel.subscriptionsLoadFailed {
              HStack {
                Text("部分数据加载失败，当前显示的是旧数据")
                  .font(.footnote)
                  .foregroundColor(.secondary)
                Button("重试") {
                  Task { await viewModel.refreshData() }
                }
              }
              .padding(.horizontal)
            }

            // 第1节：最近添加
            if !viewModel.latestMediaServers.isEmpty {
              MediaSectionView(
                title: "最近添加",
                items: viewModel.latestMedia,
                servers: viewModel.latestMediaServers,
                selectedServer: $viewModel.selectedLatestMediaServer,
                isFirstRow: true,
                loadsPageImages: true,
                viewModel: viewModel
              )
            }

            // 第2节：电影订阅
            if !viewModel.movieSubscriptions.isEmpty {
              SubscribeSectionView(
                title: "电影订阅",
                items: viewModel.movieSubscriptions,
                isFirstRow: viewModel.latestMediaServers.isEmpty,
                loadsPageImages: true,
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
                isFirstRow: viewModel.latestMediaServers.isEmpty
                  && viewModel.movieSubscriptions.isEmpty,
                loadsPageImages: true,
                viewModel: viewModel,
                onEdit: presentEditSheet,
                onViewDetail: navigateToDetail
              )
            }

            if viewModel.latestMediaServers.isEmpty && viewModel.movieSubscriptions.isEmpty
              && viewModel.tvSubscriptions.isEmpty
            {
              if viewModel.latestLoadFailed || viewModel.subscriptionsLoadFailed {
                VStack(spacing: 12) {
                  Text("加载失败，请重试")
                    .font(.headline)
                    .foregroundColor(.secondary)
                  Button("重试") {
                    Task { await viewModel.refreshData() }
                  }
                }
                .frame(maxWidth: .infinity, minHeight: 200)
              } else {
                Text("暂无内容")
                  .font(.headline)
                  .foregroundColor(.secondary)
                  .frame(maxWidth: .infinity, minHeight: 200)
              }
            }
          }
        }
      }
      .task {
        // 每次页面出现时都会先加载一次（内部有 hasLoaded 控制全屏 Loading）
        await viewModel.loadData()

        // 定期刷新数据（类似 Status 页面的下载器/整理信息）
        while !Task.isCancelled {
          try? await Task.sleep(nanoseconds: 10 * 1_000_000_000)
          guard !Task.isCancelled else { break }
          await viewModel.refreshData()
        }
      }
      // 编辑订阅 Sheet
      .sheet(item: $selectedSubscribe) { subscribe in
        SubscribeSheet(subscribe: subscribe)
      }
      // 导航目的地
      .navigationDestination(for: ImageNavigationEntry.self) { entry in
        ImageNavigationDestination(entry: entry)
      }
    }
    .environment(\.pageImageLifecycle, navigationCoordinator.rootLifecycle)
    .environmentObject(navigationCoordinator)
    .onAppear {
      updateStackForeground()
    }
    .onChange(of: isSelected) { _, _ in
      updateStackForeground()
    }
    .onChange(of: scenePhase) { _, _ in
      updateStackForeground()
    }
  }

  // MARK: - 动作

  private func presentEditSheet(for subscribe: Subscribe) {
    self.selectedSubscribe = subscribe
  }

  private func navigateToDetail(for subscribe: Subscribe) {
    // 订阅列表的 navigationMediaInfo() 不含海报（poster_path 为 nil），
    // 必须显式携带订阅海报，否则详情页加载遮罩的海报区域会显示空白。
    navigationCoordinator.push(
      subscribe.navigationMediaInfo(),
      loadingPosterURL: subscribe.imageURLs.poster
    )
  }

  private func updateStackForeground() {
    navigationCoordinator.setStackPresentation(isSelected: isSelected, scenePhase: scenePhase)
  }
}

enum HomeSubscribeFocusID {
  static func value(for id: Int?) -> String? {
    id.map(String.init)
  }
}

// MARK: - 子视图

private struct MediaSectionView: View {
  let title: String
  let items: [MediaServerPlayItem]
  let servers: [String]
  @Binding var selectedServer: String
  var isFirstRow: Bool = false
  let loadsPageImages: Bool
  @ObservedObject var viewModel: HomeViewModel

  @Environment(\.openURL) private var openURL
  @EnvironmentObject private var mediaActionHandler: MediaActionHandler
  @EnvironmentObject private var notificationManager: NotificationManager
  @EnvironmentObject private var navigationCoordinator: ImageNavigationCoordinator
  @FocusState private var focusedItemId: String?
  @FocusState private var isTopRedirectorFocused: Bool
  @State private var hasRedirectedFocus: Bool = false
  @State private var imageAnchorId: String?
  @State private var posterWarmTask: Task<Void, Never>?

  private var canSearchResources: Bool {
    APIService.shared.canAccess(.search)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 12) {
        Text(title)
          .font(.callout)
          .fontWeight(.bold)
          .foregroundStyle(.secondary)

        Spacer()

        if servers.count > 1 {
          Picker("服务器", selection: $selectedServer) {
            ForEach(servers, id: \.self) { server in
              Text(server).tag(server)
            }
          }
          .pickerStyle(.menu)
        }
      }
      .padding(.horizontal, 8)
      .focusSection()

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

      if items.isEmpty {
        Text("该服务器暂无最近内容")
          .font(.headline)
          .foregroundColor(.secondary)
          .frame(maxWidth: .infinity, minHeight: 120)
          .padding(.top, 25)
      } else {
        ScrollView(.horizontal, showsIndicators: false) {
          LazyHStack(spacing: 40) {
            ForEach(Array(items.enumerated()), id: \.element.id) { entry in
              let index = entry.offset
              let item = entry.element
              MediaCard(
                title: item.title,
                posterUrl: item.imageURLs.image,
                typeText: item.type,
                ratingText: nil,
                bottomLeftText: nil,
                bottomLeftSecondaryText: nil,
                source: nil,
                loadsImage: loadsPageImages
                  && ImageLoadWindow.containsHorizontalItem(
                    at: index,
                    itemCount: items.count,
                    anchorIndex: imageAnchorId.flatMap { id in
                      items.firstIndex(where: { $0.id == id })
                    },
                    cardKind: .media
                  ),
                action: canOpenMediaLibrary(item)
                  ? { openMediaItem(item) }
                  : nil
              )
              .focused($focusedItemId, equals: item.id)
              .compositingGroup()
              .contextMenu {
                if canOpenMediaLibrary(item) {
                  Button {
                    openMediaItem(item)
                  } label: {
                    Label("跳转媒体库", systemImage: "arrow.up.right.square")
                  }
                }
                Button {
                  let navigationSource = navigationCoordinator.sourceToken()
                  let loadingPosterURL = item.imageURLs.image
                  Task {
                    // 使用实际的标题、年份和类型进行识别
                    let info = MediaInfo(title: item.title, type: item.type, year: item.subtitle)
                    if let target = await mediaActionHandler.getTMDBJumpTarget(for: info) {
                      navigationCoordinator.push(
                        target,
                        loadingPosterURL: loadingPosterURL,
                        ifCurrent: navigationSource
                      )
                    }
                  }
                } label: {
                  Label("TMDB详情页", systemImage: "link")
                }
                if canSearchResources {
                  Button {
                    let navigationSource = navigationCoordinator.sourceToken()
                    Task {
                      guard APIService.shared.canAccess(.search) else { return }
                      let sessionSnapshot = APIService.shared.sessionSnapshot()
                      let info = MediaInfo(title: item.title, type: item.type, year: item.subtitle)
                      if let target = await mediaActionHandler.getTMDBJumpTarget(for: info) {
                        if let request =
                          await mediaActionHandler.searchResourcesTargetUsingDefaultSites(
                            for: target)
                        {
                          navigationCoordinator.push(request, ifCurrent: navigationSource)
                        }
                      } else {
                        guard APIService.shared.isSessionUnchanged(from: sessionSnapshot) else {
                          return
                        }
                        let sites = await SystemViewModel.normalizedDefaultSearchSitesString()
                        guard APIService.shared.isSessionUnchanged(from: sessionSnapshot) else {
                          return
                        }
                        let request = ResourceSearchRequest(
                          keyword: item.title, type: item.type, area: nil, title: nil, year: nil,
                          season: nil, mediaInfo: nil, sites: sites)
                        navigationCoordinator.push(request, ifCurrent: navigationSource)
                      }
                    }
                  } label: {
                    Label("搜索资源", systemImage: "magnifyingglass")
                  }
                }
              }
            }
          }
          .padding(.top, 25)
          .padding(.bottom, 30)
          .onChange(of: focusedItemId) { _, newId in
            guard let newId else { return }
            imageAnchorId = newId
            // 聚焦停留后预热详情加载遮罩海报：媒体服务器图经后端代理转发较慢，
            // push 时才开始下载会赶不上转场，聚焦时提前下载磁盘即可命中。
            posterWarmTask?.cancel()
            guard let item = items.first(where: { $0.id == newId }) else { return }
            posterWarmTask = Task {
              try? await Task.sleep(for: .milliseconds(300))
              guard !Task.isCancelled else { return }
              MediaPreloader.shared.warmLoadingPoster(item.imageURLs.image)
            }
          }
        }
        .scrollClipDisabled()
        .focusSection()
      }
    }
  }

  private func canOpenMediaLibrary(_ item: MediaServerPlayItem) -> Bool {
    HomeViewModel.supportsMediaLibraryDeepLink(serverType: item.server_type)
  }

  private func openMediaItem(_ item: MediaServerPlayItem) {
    viewModel.openMediaItem(item, using: openURL) { message in
      notificationManager.show(message: message, type: .error)
    }
  }
}

private struct SubscribeSectionView: View {
  let title: String
  let items: [Subscribe]
  var isFirstRow: Bool = false
  let loadsPageImages: Bool
  @ObservedObject var viewModel: HomeViewModel
  let onEdit: (Subscribe) -> Void
  let onViewDetail: (Subscribe) -> Void

  @FocusState private var focusedItemId: String?
  @FocusState private var isTopRedirectorFocused: Bool
  @State private var hasRedirectedFocus: Bool = false
  @State private var imageAnchorId: String?
  @State private var posterWarmTask: Task<Void, Never>?

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
              focusedItemId = HomeSubscribeFocusID.value(for: items.first?.id)
              hasRedirectedFocus = true
              isTopRedirectorFocused = false
            }
          }
      }

      ScrollView(.horizontal, showsIndicators: false) {
        LazyHStack(spacing: 40) {
          ForEach(Array(items.enumerated()), id: \.element.id) { entry in
            let index = entry.offset
            let item = entry.element
            SubscribeItemView(
              item: item,
              loadsImage: loadsPageImages
                && ImageLoadWindow.containsHorizontalItem(
                  at: index,
                  itemCount: items.count,
                  anchorIndex: imageAnchorId.flatMap { id in
                    items.firstIndex(where: { HomeSubscribeFocusID.value(for: $0.id) == id })
                  },
                  cardKind: .media
                ),
              viewModel: viewModel,
              onEdit: { onEdit(item) },
              onViewDetail: { onViewDetail(item) }
            )
            .focused($focusedItemId, equals: HomeSubscribeFocusID.value(for: item.id))
          }
        }
        .padding(.top, 25)
        .padding(.bottom, 30)
        .onChange(of: focusedItemId) { _, newId in
          guard let newId else { return }
          imageAnchorId = newId
          // 聚焦停留后预热详情加载遮罩海报（与“最近添加”一致），
          // 订阅卡片从菜单进详情时转场海报磁盘已命中。
          posterWarmTask?.cancel()
          guard
            let item = items.first(where: {
              HomeSubscribeFocusID.value(for: $0.id) == newId
            })
          else { return }
          posterWarmTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            MediaPreloader.shared.warmLoadingPoster(item.imageURLs.poster)
          }
        }
      }
      .scrollClipDisabled()
      .focusSection()
    }
  }
}

private struct SubscribeItemView: View {
  let item: Subscribe
  let loadsImage: Bool
  @ObservedObject var viewModel: HomeViewModel
  let onEdit: () -> Void
  let onViewDetail: () -> Void
  @EnvironmentObject private var notificationManager: NotificationManager
  @State private var showUnsubscribeConfirm = false

  var body: some View {
    MediaCard(
      title: item.name,
      posterUrl: item.imageURLs.poster,
      typeText: formatState(item.state),
      ratingText: nil,
      bottomLeftText: formatProgress(total: item.total_episode, lack: item.lack_episode),
      bottomLeftSecondaryText: item.last_update?.toRelativeDateString() ?? nil,
      source: nil,
      loadsImage: loadsImage,
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
        searchSubscribe()
      } label: {
        Label("搜索订阅", systemImage: "magnifyingglass")
      }

      // 4. 启用/暂停
      Button {
        toggleSubscribeStatus()
      } label: {
        if item.state == "S" {
          Label("启用订阅", systemImage: "play.fill")
        } else {
          Label("暂停订阅", systemImage: "pause.fill")
        }
      }

      // 5. 重置订阅
      Button {
        resetSubscribe()
      } label: {
        Label("重置订阅", systemImage: "arrow.counterclockwise")
      }

      Divider()

      // 6. 取消订阅
      Button(role: .destructive) {
        showUnsubscribeConfirm = true
      } label: {
        Label("取消订阅", systemImage: "trash")
      }
    }
    .alert(SubscriptionCancelConfirmation.title, isPresented: $showUnsubscribeConfirm) {
      Button("取消", role: .cancel) {}
      Button(SubscriptionCancelConfirmation.confirmButtonTitle, role: .destructive) {
        deleteSubscribe()
      }
    } message: {
      Text(SubscriptionCancelConfirmation.message(for: item))
    }
  }

  private func searchSubscribe() {
    Task {
      do {
        guard try await viewModel.searchSubscribe(subscribe: item) else {
          showRequestFailure()
          return
        }
      } catch {
        showRequestFailure()
      }
    }
  }

  private func toggleSubscribeStatus() {
    Task {
      do {
        let result = try await viewModel.toggleSubscribeStatus(subscribe: item)
        guard result.success else {
          showActionFailure(
            "\(item.state == "S" ? "启用" : "暂停")订阅失败",
            detail: result.message
          )
          return
        }
      } catch {
        showRequestFailure()
      }
    }
  }

  private func resetSubscribe() {
    Task {
      do {
        let result = try await viewModel.resetSubscribe(subscribe: item)
        guard result.success else {
          showActionFailure("重置订阅失败", detail: result.message)
          return
        }
      } catch {
        showRequestFailure()
      }
    }
  }

  private func deleteSubscribe() {
    Task {
      do {
        guard try await viewModel.deleteSubscribe(subscribe: item) else {
          showUnsubscribeFailure()
          return
        }
      } catch is CancellationError {
        return
      } catch {
        showUnsubscribeFailure()
      }
    }
  }

  private func showUnsubscribeFailure() {
    notificationManager.show(
      message: SubscriptionCancelConfirmation.failureMessage,
      type: .error
    )
  }

  private func showActionFailure(_ action: String, detail: String?) {
    let message = "《\(item.name)》\(action)"
    notificationManager.show(
      message: MediaIdentifier.normalizedString(detail).map { "\(message)：\($0)" } ?? "\(message)。",
      type: .error
    )
  }

  private func showRequestFailure() {
    notificationManager.show(message: "订阅请求失败，请稍后重试。", type: .error)
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
