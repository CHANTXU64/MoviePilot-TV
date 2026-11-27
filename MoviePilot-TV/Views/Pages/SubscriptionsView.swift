import Combine
import SwiftUI

/// 「订阅」Tab：电影订阅、电视剧订阅两行。按下卡片编辑订阅，长按给详情、搜索、暂停/启用、重置和取消。
@MainActor
struct SubscriptionsView: View {
  private let isSelected: Bool
  @StateObject private var viewModel: SubscriptionsViewModel
  @Environment(\.scenePhase) private var scenePhase

  @State private var selectedSubscribe: Subscribe?
  @StateObject private var navigationCoordinator = ImageNavigationCoordinator()
  @EnvironmentObject private var mediaActionHandler: MediaActionHandler

  init(isSelected: Bool = true, viewModel: SubscriptionsViewModel? = nil) {
    self.isSelected = isSelected
    _viewModel = StateObject(wrappedValue: viewModel ?? SubscriptionsViewModel())
  }

  var body: some View {
    NavigationStack(path: $navigationCoordinator.path) {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 30) {
          if viewModel.showsLoadingPlaceholder {
            // 整页加载的转圈由 ScrollView 外层的 pageLoadingOverlay 居中显示。
            EmptyView()
          } else if viewModel.movieSubscriptions.isEmpty && viewModel.tvSubscriptions.isEmpty {
            emptyState
          } else {
            // 刷新失败：保留旧列表并提示（成功空不算失败）
            if viewModel.subscriptionsLoadFailed {
              HStack {
                Text("订阅加载失败，当前显示的是旧数据")
                  .font(.body)
                  .foregroundColor(.secondary)
                Button("重试") {
                  Task { await viewModel.refreshSubscriptions(forceRefresh: true) }
                }
              }
              .padding(.horizontal)
            }

            if !viewModel.movieSubscriptions.isEmpty {
              SubscribeSectionView(
                title: "电影订阅",
                items: viewModel.movieSubscriptions,
                isFirstRow: true,
                loadsPageImages: true,
                viewModel: viewModel,
                onEdit: presentEditSheet,
                onViewDetail: navigateToDetail
              )
            }

            if !viewModel.tvSubscriptions.isEmpty {
              SubscribeSectionView(
                title: "电视剧订阅",
                items: viewModel.tvSubscriptions,
                isFirstRow: viewModel.movieSubscriptions.isEmpty,
                loadsPageImages: true,
                viewModel: viewModel,
                onEdit: presentEditSheet,
                onViewDetail: navigateToDetail
              )
            }
          }
        }
      }
      .pageLoadingOverlay(viewModel.showsLoadingPlaceholder)
      .task(id: isSelected) {
        // 成为当前 Tab 时加载，之后每 10 秒刷新一次，跟上下载进度和状态变化。切走时任务取消，轮询不再在后台空转。
        guard isSelected else { return }
        await viewModel.loadData()

        while !Task.isCancelled {
          try? await Task.sleep(nanoseconds: 10 * 1_000_000_000)
          guard !Task.isCancelled else { break }
          await viewModel.refreshSubscriptions(forceRefresh: true)
        }
      }
      // 编辑订阅 Sheet
      .onReceive(NotificationCenter.default.publisher(for: .imageNavigationPresentationWillReset, object: APIService.shared)) { _ in selectedSubscribe = nil }
      .sheet(item: $selectedSubscribe) { subscribe in
        SubscribeSheet(subscribe: subscribe)
      }
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

  /// 没有订阅可显示：读失败时给重试，读成功但为空时说明订阅从哪里来。
  @ViewBuilder
  private var emptyState: some View {
    VStack(spacing: 12) {
      if viewModel.subscriptionsLoadFailed {
        Text("订阅加载失败，请重试")
          .font(.headline)
          .foregroundColor(.secondary)
        Button("重试") {
          Task { await viewModel.refreshSubscriptions(forceRefresh: true) }
        }
      } else {
        Text("还没有订阅")
          .font(.headline)
          .foregroundColor(.secondary)
        Text("在影片详情页订阅后，可以在这里查看进度、暂停或取消订阅。")
          .font(.callout)
          .foregroundStyle(.tertiary)
      }
    }
    .frame(maxWidth: .infinity, minHeight: 400)
  }

  // MARK: - 动作

  private func presentEditSheet(for subscribe: Subscribe) {
    selectedSubscribe = subscribe
  }

  private func navigateToDetail(for subscribe: Subscribe) {
    // 订阅列表的 navigationMediaInfo() 不含海报（poster_path 为 nil），
    // 必须显式携带订阅海报，否则冷加载阶段详情背景没有海报兜底。
    Task { @MainActor in
      await mediaActionHandler.openMediaDetail(
        subscribe.navigationMediaInfo(),
        in: navigationCoordinator,
        loadingPosterURL: subscribe.imageURLs.poster
      )
    }
  }

  private func updateStackForeground() {
    navigationCoordinator.setStackPresentation(isSelected: isSelected, scenePhase: scenePhase)
  }
}

/// 订阅卡片的焦点值：直接用订阅编号的十进制字符串，不能带 `Optional(...)` 包装。
enum SubscribeFocusID {
  static func value(for id: Int?) -> String? {
    id.map(String.init)
  }
}

// MARK: - 子视图

private struct SubscribeSectionView: View {
  private var memoryOptimization = MemoryOptimizationSettings()
  let title: String
  let items: [Subscribe]
  var isFirstRow: Bool = false
  let loadsPageImages: Bool
  @ObservedObject var viewModel: SubscriptionsViewModel
  let onEdit: (Subscribe) -> Void
  let onViewDetail: (Subscribe) -> Void

  @FocusState private var focusedItemId: String?
  @FocusState private var isTopRedirectorFocused: Bool
  @State private var hasRedirectedFocus: Bool = false
  @State private var imageAnchorId: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(title)
        .font(.callout)
        .bold()
        .foregroundStyle(.secondary)
        .focusLiftHeaderPart()
        .padding(.leading, 8)

      if isFirstRow {
        // 顶部焦点重定向器：确保在首次加载时来自上方的焦点进入第一个项目，然后禁用自身。
        Color.clear
          .frame(height: 1)
          .focusable(!hasRedirectedFocus)
          .focused($isTopRedirectorFocused)
          .onChange(of: isTopRedirectorFocused) { _, isFocused in
            if isFocused {
              focusedItemId = SubscribeFocusID.value(for: items.first?.id)
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
                    items.firstIndex(where: { SubscribeFocusID.value(for: $0.id) == id })
                  },
                  cardKind: .media,
                  usesFocusWindow: memoryOptimization.isEnabled
                ),
              viewModel: viewModel,
              trials: viewModel.episodeTrials,
              onEdit: { onEdit(item) },
              onViewDetail: { onViewDetail(item) }
            )
            .focused($focusedItemId, equals: SubscribeFocusID.value(for: item.id))
          }
        }
        .padding(.top, 25)
        .padding(.bottom, 30)
        .onChange(of: focusedItemId) { _, newId in
          // Push 或上下文菜单可能暂时清空焦点；保留当前图片窗口锚点。
          guard let newId else { return }
          imageAnchorId = newId
        }
      }
      .scrollClipDisabled()
      .focusSection()
    }
    .focusLiftRow(cardImageSize: MediaCard.defaultPosterSize)
  }
}

private struct SubscribeItemView: View {
  let item: Subscribe
  let loadsImage: Bool
  @ObservedObject var viewModel: SubscriptionsViewModel
  /// 只跟随本机试看订阅的认领、取消和了结，试看进度刷新时不重算整排订阅卡。
  let trials: EpisodeTrialService
  let onEdit: () -> Void
  let onViewDetail: () -> Void
  @EnvironmentObject private var notificationManager: NotificationManager
  @State private var showUnsubscribeConfirm = false
  @State private var showsEpisodeTrialNotice = false
  @State private var trialHolds: Set<EpisodeTrialHold>

  init(
    item: Subscribe, loadsImage: Bool, viewModel: SubscriptionsViewModel, trials: EpisodeTrialService,
    onEdit: @escaping () -> Void, onViewDetail: @escaping () -> Void
  ) {
    self.item = item
    self.loadsImage = loadsImage
    self.viewModel = viewModel
    self.trials = trials
    self.onEdit = onEdit
    self.onViewDetail = onViewDetail
    _trialHolds = State(initialValue: EpisodeTrialHold.holds(in: trials.credentials))
  }

  var body: some View {
    let trialState = EpisodeTrialHold.state(of: item, in: trialHolds)
    let isEpisodeTrial = trialState != nil
    let isCancellingTrial = trialState == .cancelling
    MediaCard(
      title: item.name,
      posterUrl: item.imageURLs.poster,
      typeText: isEpisodeTrial ? "试看" : formatState(item.state),
      ratingText: nil,
      bottomLeftText: isCancellingTrial
        ? "取消试看中"
        : isEpisodeTrial
          ? item.episodeTrialTargetText : formatProgress(total: item.total_episode, lack: item.lack_episode),
      bottomLeftSecondaryText: item.last_update?.toRelativeDateString() ?? nil,
      source: nil,
      loadsImage: loadsImage,
      action: {
        if isEpisodeTrial {
          showsEpisodeTrialNotice = true
        } else {
          onEdit()
        }
      }
    )
    .compositingGroup()
    .contextMenu {
      if isEpisodeTrial {
        Button {
          onViewDetail()
        } label: {
          Label("详情", systemImage: AppSymbol.details)
        }
        if viewModel.canCancelEpisodeTrial, !isCancellingTrial {
          Button(role: .destructive) {
            showsEpisodeTrialNotice = true
          } label: {
            Label(EpisodeTrialHoldNotice.cancelTitle, systemImage: AppSymbol.unsubscribe)
          }
        }
      } else {
        actionMenu
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .imageNavigationPresentationWillReset, object: APIService.shared)) { _ in
      showUnsubscribeConfirm = false
      showsEpisodeTrialNotice = false
    }
    .onReceive(trials.$credentials.map(EpisodeTrialHold.holds(in:)).removeDuplicates()) { holds in
      trialHolds = holds
    }
    .alert(SubscriptionCancelConfirmation.title, isPresented: $showUnsubscribeConfirm) {
      Button("取消", role: .cancel) {}
      Button(SubscriptionCancelConfirmation.confirmButtonTitle, role: .destructive) {
        deleteSubscribe()
      }
    } message: {
      Text(SubscriptionCancelConfirmation.message(for: item))
    }
    .episodeTrialNotice(
      isPresented: $showsEpisodeTrialNotice, context: .manage, isCancelling: isCancellingTrial,
      canCancel: viewModel.canCancelEpisodeTrial
    ) {
      cancelEpisodeTrial()
    }
  }

  private func cancelEpisodeTrial() {
    Task {
      switch await viewModel.cancelEpisodeTrial(subscribe: item) {
      case .done: break
      case .pending: notificationManager.show(message: EpisodeTrialHoldNotice.cancelPending, type: .info)
      case .failed: notificationManager.show(message: EpisodeTrialHoldNotice.cancelFailure, type: .error)
      }
    }
  }

  @ViewBuilder
  private var actionMenu: some View {
    // 1. 编辑订阅
    Button {
      onEdit()
    } label: {
      Label("编辑订阅", systemImage: AppSymbol.editSubscription)
    }

    // 2. 详情
    Button {
      onViewDetail()
    } label: {
      Label("详情", systemImage: AppSymbol.details)
    }

    // 3. 搜索订阅
    Button {
      searchSubscribe()
    } label: {
      Label("搜索订阅", systemImage: AppSymbol.search)
    }

    // 4. 启用/暂停
    Button {
      toggleSubscribeStatus()
    } label: {
      if item.state == "S" {
        Label("启用订阅", systemImage: AppSymbol.resume)
      } else {
        Label("暂停订阅", systemImage: AppSymbol.pause)
      }
    }

    // 5. 重置订阅
    Button {
      resetSubscribe()
    } label: {
      Label("重置订阅", systemImage: AppSymbol.resetSubscription)
    }

    Divider()

    // 6. 取消订阅
    Button(role: .destructive) {
      showUnsubscribeConfirm = true
    } label: {
      Label("取消订阅", systemImage: AppSymbol.unsubscribe)
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
