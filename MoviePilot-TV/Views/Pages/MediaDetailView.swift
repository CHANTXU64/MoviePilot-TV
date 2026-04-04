import Kingfisher
import SwiftUI

struct MediaDetailView: View {
  @StateObject private var viewModel: MediaDetailViewModel
  @Binding var navigationPath: NavigationPath
  @StateObject private var subscriptionHandler = SubscriptionHandler()
  @EnvironmentObject private var mediaActionHandler: MediaActionHandler
  /// 预加载任务：订阅状态、TMDB 识别、分季信息的唯一数据源
  @ObservedObject var preloadTask: MediaPreloadTask
  /// 由 ContainerView 传入，当第二页首行内容就绪时回写 true，控制 Loading 遮罩显隐
  @Binding var isContentReady: Bool
  @State private var showSiteSelection = false
  @State private var showContentPage = false

  // 订阅相关 UI 状态（弹窗开关，纯 UI 逻辑）
  @State private var sheetSubscribe: Subscribe?
  @State private var showUnsubscribeConfirm = false
  @State private var showSubscribedAlert = false
  /// 推荐区预加载防抖任务
  @State private var recommendPreloadDebounce: Task<Void, Never>?
  /// 相似区预加载防抖任务
  @State private var similarPreloadDebounce: Task<Void, Never>?

  @FocusState private var focusedRecommendId: MediaInfo.ID?
  @FocusState private var focusedSimilarId: MediaInfo.ID?
  @FocusState private var focusedActorId: Person.ID?
  @FocusState private var isHeroFocused: Bool
  @FocusState private var isContentFocused: Bool
  enum ButtonField {
    case subscribe, search, sites, tmdbJump
  }
  @FocusState private var focusedButton: ButtonField?
  @State private var lastFocusedButton: ButtonField?

  private var shouldShowSiteFilter: Bool {
    if focusedButton == .search || focusedButton == .sites {
      return true
    }
    if focusedButton == nil && (lastFocusedButton == .search || lastFocusedButton == .sites) {
      return true
    }
    return false
  }

  private var firstVisibleRow: String {
    if viewModel.detail.type == "电视剧" && viewModel.detail.tmdb_id != nil {
      return "season"
    }
    if !viewModel.actorsPaginator.items.isEmpty {
      return "actors"
    }
    if !viewModel.uniqueDirectors.isEmpty {
      return "directors"
    }
    if !viewModel.recommendPaginator.items.isEmpty {
      return "recommendations"
    }
    if !viewModel.similarPaginator.items.isEmpty {
      return "similar"
    }
    return ""
  }

  /// 从 ViewModel 读取的订阅状态（ViewModel 代理到 preloadTask）
  private var isSubscribed: Bool {
    viewModel.isSubscribed
  }

  init(
    detail: MediaInfo, navigationPath: Binding<NavigationPath>,
    preloadTask: MediaPreloadTask, isContentReady: Binding<Bool>
  ) {
    let vm = MediaDetailViewModel(detail: detail)
    vm.preloadTask = preloadTask
    _viewModel = StateObject(wrappedValue: vm)
    _navigationPath = navigationPath
    self.preloadTask = preloadTask
    _isContentReady = isContentReady
  }

  var body: some View {
    ZStack {
      // 固定背景图
      if let url = viewModel.backgroundUrl {
        let blurRadius =
          viewModel.isUsingPosterAsBackdrop ? 60 : (showContentPage ? 60 : 0)
        let processor: ImageProcessor =
          blurRadius > 0
          ? BlurImageProcessor(blurRadius: CGFloat(blurRadius))
          : DefaultImageProcessor.default

        KFImage(url)
          .requestModifier(AnyModifier.cookieModifier)
          .placeholder {
            EmptyView()
          }
          .setProcessor(processor)
          .resizing(
            referenceSize: UIScreen.main.bounds.size,
            mode: .aspectFill
          )
          .resizable()
          .aspectRatio(contentMode: .fill)
          .frame(
            width: UIScreen.main.bounds.width,
            height: UIScreen.main.bounds.height,
            alignment: viewModel.isUsingPosterAsBackdrop ? .top : .center
          )
          .animation(.easeInOut(duration: 0.5), value: showContentPage)
          .id("\(url.absoluteString)-\(blurRadius)")
          .transition(.opacity)
          .ignoresSafeArea()
      } else {
        Color.gray.opacity(0.3)
          .ignoresSafeArea()
      }

      // Apple TV Style 动态阴影
      ZStack {
        // 1. 顶部很淡的阴影（左边长一点，右边短一点）
        ZStack {
          LinearGradient(
            gradient: Gradient(colors: [.black.opacity(0.2), .black.opacity(0.05), .clear]),
            startPoint: .top,
            endPoint: UnitPoint(x: 0.5, y: 0.1)
          )
          LinearGradient(
            gradient: Gradient(colors: [.black.opacity(0.2), .black.opacity(0.15), .clear]),
            startPoint: .topLeading,
            endPoint: UnitPoint(x: 0.4, y: 0.4)
          )
        }

        // 2. 左下角 1/4 圆形的阴影
        RadialGradient(
          gradient: Gradient(colors: [.black.opacity(0.5), .black.opacity(0.35), .clear]),
          center: .bottomLeading,
          startRadius: 0,
          endRadius: UIScreen.main.bounds.width * 0.5
        )

        // 3. 底部渐变：很黑 -> 到演员变浅 -> 延伸到中心
        LinearGradient(
          gradient: Gradient(stops: [
            .init(color: .black.opacity(1.0), location: 0.0),
            .init(color: .black.opacity(0.8), location: 0.1),
            .init(color: .black.opacity(0.5), location: 0.2),
            .init(color: .black.opacity(0.25), location: 0.3),
            .init(color: .black.opacity(0.15), location: 0.4),
            .init(color: .black.opacity(0.07), location: 0.5),
            .init(color: .black.opacity(0.02), location: 0.6),
            .init(color: .clear, location: 0.7),
          ]),
          startPoint: .bottom,
          endPoint: .top
        )
      }
      .ignoresSafeArea()

      if showContentPage && !viewModel.isUsingPosterAsBackdrop {
        // 第二页模糊时增加浅黑色遮罩，避免白色背景导致文字看不清
        Color.black.opacity(0.18)
          .ignoresSafeArea()
          .transition(.opacity)
      }

      ScrollViewReader { proxy in
        ScrollView {
          VStack(alignment: .leading, spacing: 0) {
            heroSection(scrollProxy: proxy)
              .id("top")

            VStack(alignment: .leading, spacing: 30) {
              // Centered media title — only visible on second page
              if showContentPage {
                Text(viewModel.detail.cleanedTitle ?? "")
                  .font(.largeTitle.bold())
                  .frame(maxWidth: .infinity, alignment: .center)
                  .padding(.bottom, 10)
                  .transition(.opacity)
              }

              seasonSubscriptionSection
              actorsSection
              directorsSection
              recommendationsSection
              similarSection
            }
            .id("contentTop")
            .padding(.top, showContentPage ? 60 : 0)
            .padding(.bottom, 80)
            .focused($isContentFocused)
            .animation(.easeInOut(duration: 0.6), value: showContentPage)
            .onChange(of: isHeroFocused) { _, focused in
              if focused {
                withAnimation(.easeInOut(duration: 0.6)) {
                  showContentPage = false
                  proxy.scrollTo("top", anchor: .top)
                }
              } else if isContentFocused {
                withAnimation(.easeInOut(duration: 0.6)) {
                  showContentPage = true
                  proxy.scrollTo("contentTop", anchor: .top)
                }
              }
            }
          }
        }
      }
    }
    .environmentObject(subscriptionHandler)
    .defaultFocus($focusedButton, .subscribe)
    .ignoresSafeArea()
    .onDisappear {
      // 取消防抖任务，防止视图消失后仍发起无意义的预加载请求
      recommendPreloadDebounce?.cancel()
      similarPreloadDebounce?.cancel()
    }
    .task {
      focusedButton = .subscribe
      // 如果 fullDetail 已经就绪（预加载命中），立即应用（网络加载自动在后台启动）
      if let fullDetail = preloadTask.fullDetail {
        viewModel.applyFullDetail(fullDetail)
      }
      await viewModel.siteFilter.loadSites()
    }
    // 焦点恢复关键：当 fullDetail 加载完成后，应用完整详情。
    // MediaDetailView 从第一帧就存在于视图树中（用 partialMedia 初始化），
    // 在 fullDetail 就绪前不配置任何内容，仅由 Loading 遮罩覆盖。
    .onChange(of: preloadTask.isDetailLoaded) { _, isLoaded in
      if isLoaded, let fullDetail = preloadTask.fullDetail {
        viewModel.applyFullDetail(fullDetail)
      }
    }
    // 当 ViewModel 的 isFirstRowReady 变为 true 时，回写给 ContainerView 控制 Loading 遮罩
    .onChange(of: viewModel.isFirstRowReady) { _, ready in
      if ready {
        isContentReady = true
      }
    }
    // 电视剧首行是 season，由 preloadTask 异步加载，
    // 当分季数据实际加载完毕时通知 ViewModel（applyFullDetail 时可能尚未就绪）
    .onChange(of: preloadTask.isSeasonDataLoaded) { _, isLoaded in
      if isLoaded && !viewModel.isFirstRowReady
        && viewModel.detail.type == "电视剧" && viewModel.detail.tmdb_id != nil
      {
        viewModel.isFirstRowReady = true
      }
    }
    .sheet(item: $sheetSubscribe) { subscribe in
      SubscribeSheet(subscribe: subscribe, isNewSubscription: true)
        .onDisappear {
          // 订阅完成后刷新订阅状态（通过 ViewModel 代理到 preloadTask）
          Task {
            await viewModel.refreshSubscriptionStatus()
          }
        }
    }
    .alert("取消订阅", isPresented: $showUnsubscribeConfirm) {
      Button("取消", role: .cancel) {}
      Button("确认取消订阅", role: .destructive) {
        Task {
          await viewModel.cancelSubscription()
        }
      }
    } message: {
      Text("确定要取消订阅「\(viewModel.detail.title ?? "")」吗？")
    }
    .alert("提示", isPresented: $showSubscribedAlert) {
      Button("确定", role: .cancel) {}
    } message: {
      Text("该内容已在订阅中")
    }
    .mediaSubscriptionAlerts(using: subscriptionHandler, navigationPath: $navigationPath)
    .sheet(isPresented: $showSiteSelection) {
      MultiSelectionSheet(
        options: viewModel.siteFilter.availableSites,
        id: \.id,
        selected: $viewModel.siteFilter.selectedSites,
        label: { $0.name }
      )
    }
    .onChange(of: focusedButton) { _, newValue in
      if let newValue = newValue {
        lastFocusedButton = newValue
      }
    }
  }

  // MARK: - 订阅 UI 操作（业务逻辑委托给 ViewModel）

  private func handleHeaderSubscribe() {
    if isSubscribed {
      showSubscribedAlert = true
    } else {
      sheetSubscribe = viewModel.buildSubscribeRequest()
    }
  }

  @ViewBuilder
  private func heroSection(scrollProxy: ScrollViewProxy) -> some View {
    let detail = viewModel.detail
    ZStack(alignment: .bottom) {
      // Content
      HStack(alignment: .bottom, spacing: 0) {
        // Left Side: Title, Metadata, Overview, Buttons
        VStack(alignment: .leading, spacing: 20) {
          // Title
          Text(detail.cleanedTitle ?? "Unknown")
            .font(.largeTitle.bold())
            .lineLimit(3)
            .multilineTextAlignment(.leading)
            .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 740, alignment: .leading)

          let metadataTexts1: [String] = {
            var items: [String] = []
            if let category = detail.category, !category.isEmpty {
              items.append(category)
            } else if let type = detail.type, !type.isEmpty {
              items.append(type)
            }
            if let genres = detail.genres, !genres.isEmpty {
              items.append(
                genres
                  .compactMap { $0.name }
                  .map { TranslationHelper.translateGenre(for: $0) }
                  .joined(separator: " · ")
              )
            }
            return items
          }()

          if !metadataTexts1.isEmpty {
            Text(metadataTexts1.joined(separator: " · "))
              .font(.caption)
              .lineLimit(2)
              .foregroundColor(.primary)
              .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 2)
              .frame(maxWidth: 740, alignment: .leading)
          }

          // Overview
          if let overview = detail.overview, !overview.isEmpty {
            let cleanedOverview =
              overview
              .components(separatedBy: .newlines)
              .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
              .filter { !$0.isEmpty }
              .joined(separator: " ")
            Text(cleanedOverview)
              .font(.caption)
              .lineLimit(5)
              .frame(maxWidth: 740, alignment: .leading)
              .foregroundColor(.primary.opacity(0.8))
              .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 2)
          }

          // Detailed metadata line
          let metadataTexts2: [String] = {
            var items: [String] = []
            if let releaseDate = detail.release_date {
              items.append("\(releaseDate)")
            } else if let year = detail.year {
              items.append(year)
            }
            if let runtime = detail.runtime {
              items.append("\(runtime) 分钟")
            }
            if let vote = detail.vote_average, vote > 0 {
              items.append("评分 \(vote)")
            }
            if let countries = detail.production_countries, !countries.isEmpty {
              items.append(
                countries.map { TranslationHelper.countryName(for: $0) }.joined(separator: " / "))
            }
            if let language = detail.original_language {
              items.append(TranslationHelper.languageName(for: language))
            }
            return items
          }()

          if !metadataTexts2.isEmpty {
            Text(metadataTexts2.joined(separator: " · "))
              .font(.caption)
              .lineLimit(2)
              .foregroundColor(.primary)
              .frame(maxWidth: 740, alignment: .leading)
          }

          // Action Buttons — Apple TV style: primary + icon buttons
          HStack(spacing: 20) {
            // TMDB Jump Button — 复用 MediaActionHandler 逻辑，传入预加载的 tmdbId
            if viewModel.detail.douban_id != nil || viewModel.detail.bangumi_id != nil {
              let targetTmdbId = preloadTask.tmdbId ?? viewModel.detail.tmdb_id
              let isButtonLoading = targetTmdbId == nil

              Button(action: {
                Task {
                  if let target = await mediaActionHandler.getTMDBJumpTarget(
                    for: viewModel.detail, targetTmdbId: targetTmdbId)
                  {
                    navigationPath.append(target)
                  }
                }
              }) {
                Label(
                  title: { Text("TMDB详情页") },
                  icon: {
                    if isButtonLoading {
                      ProgressView().controlSize(.small)
                    } else {
                      Image(systemName: "link")
                    }
                  }
                )
                .foregroundColor(.primary)
              }
              .focused($focusedButton, equals: .tmdbJump)
              .disabled(isButtonLoading)
            }

            // Primary subscribe button — 使用预加载的订阅状态
            Button(action: {
              if detail.canDirectlySubscribe {
                handleHeaderSubscribe()
              } else if detail.type == "电视剧" && detail.tmdb_id != nil {
                isContentFocused = true
              }
            }) {
              if viewModel.isUnsubscribing {
                ProgressView()
              } else {
                let isDirect = detail.canDirectlySubscribe
                let label = isDirect ? (isSubscribed ? "已订阅" : "订阅") : "分季订阅"
                let icon =
                  isDirect
                  ? (isSubscribed ? "checkmark.circle.fill" : "plus.circle")
                  : "list.bullet.circle"

                Label(label, systemImage: icon)
                  .foregroundColor(.primary)
              }
            }
            .focused($focusedButton, equals: .subscribe)
            .disabled(viewModel.isUnsubscribing)

            // Search resources icon button
            Button(action: {
              let request = mediaActionHandler.searchResourcesTarget(
                for: viewModel.detail,
                sites: viewModel.siteFilter.sitesString
              )
              navigationPath.append(request)
            }) {
              Label("搜索资源", systemImage: "magnifyingglass")
                .foregroundColor(.primary)
            }
            .focused($focusedButton, equals: .search)

            // Site selection button
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
              .focused($focusedButton, equals: .sites)
              .transition(.move(edge: .leading).combined(with: .opacity))
            }
          }
          .animation(.snappy, value: shouldShowSiteFilter)
        }
        .padding(.bottom, 40)
        .frame(maxWidth: UIScreen.main.bounds.width * 0.62, alignment: .leading)

        Spacer()

        // Right Side: Cast & Director — Apple TV style
        VStack(alignment: .leading, spacing: 12) {
          let topActors = viewModel.heroTopActors
          let topStaff = viewModel.heroTopStaff

          if !topActors.isEmpty {
            (Text("主演  ")
              .foregroundColor(.primary.opacity(0.8))
              + Text(topActors.compactMap { $0.name }.joined(separator: ", "))
              .foregroundColor(.primary))
              .font(.caption)
              .lineLimit(2)
          }

          if !topStaff.isEmpty {
            ForEach(topStaff) { staff in
              (Text("\(staff.job)  ")
                .foregroundColor(.primary.opacity(0.8))
                + Text(staff.names.joined(separator: ", "))
                .foregroundColor(.primary))
                .font(.caption)
                .lineLimit(2)
            }
          }
        }
        .padding(.bottom, 40)
        .frame(width: 480, alignment: .leading)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
      .focused($isHeroFocused)
    }
    .focusSection()
    .padding(.horizontal, 81)
    .frame(height: UIScreen.main.bounds.height * 0.94)
  }

  // MARK: - 分季订阅（使用预加载的 SubscribeSeasonViewModel）

  @ViewBuilder
  private var seasonSubscriptionSection: some View {
    if viewModel.detail.type == "电视剧" && viewModel.detail.tmdb_id != nil {
      VStack(alignment: .leading, spacing: 0) {
        if let seasonVM = preloadTask.seasonViewModel {
          // 使用预加载的 SubscribeSeasonViewModel
          SubscribeSeasonContentView(
            viewModel: seasonVM,
            layout: .shelf,
            title: showContentPage ? "分季订阅" : nil,
            showBadges: showContentPage,
            onSeasonTap: { season in
              let request = SubscribeSeasonRequest(
                mediaInfo: viewModel.detail,
                initialSeason: season.season_number
              )
              navigationPath.append(request)
            },
            onMoreTapped: {
              let request = SubscribeSeasonRequest(
                mediaInfo: viewModel.detail,
                initialSeason: nil
              )
              navigationPath.append(request)
            }
          )
        } else {
          // 分季信息尚在加载中
          HStack {
            Spacer()
            ProgressView()
              .padding()
            Spacer()
          }
        }
      }
      .id("seasonSubscriptionSection")
    }
  }

  @ViewBuilder
  private var directorsSection: some View {
    let directors = viewModel.uniqueDirectors
    if !directors.isEmpty {
      VStack(alignment: .leading, spacing: 0) {
        if showContentPage || firstVisibleRow != "directors" {
          Text("职员")
            .font(.callout)
            .fontWeight(.bold)
            .foregroundStyle(.secondary)
            .padding(.leading, 89)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }

        ScrollView(.horizontal, showsIndicators: false) {
          LazyHStack(spacing: 40) {
            ForEach(directors) { director in
              PersonCard(
                person: director,
                staffImageUrl: director.imageURLs.profile
              ) {
                navigationPath.append(director)
              }
              .compositingGroup()
              .contextMenu {
                Button {
                  navigationPath.append(director)
                } label: {
                  Label("详情", systemImage: "info.circle")
                }
              }
            }
          }
          .padding(.horizontal, 81)
          .padding(.top, 25)
          .padding(.bottom, 30)
        }
        .scrollClipDisabled()
        .focusSection()
      }
    }
  }

  @ViewBuilder
  private var actorsSection: some View {
    let actors = viewModel.actorsPaginator.items
    if !actors.isEmpty {
      VStack(alignment: .leading, spacing: 0) {
        if showContentPage || firstVisibleRow != "actors" {
          Text("演员")
            .font(.callout)
            .fontWeight(.bold)
            .foregroundStyle(.secondary)
            .padding(.leading, 89)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }

        ScrollView(.horizontal, showsIndicators: false) {
          LazyHStack(spacing: 40) {
            ForEach(actors) { actor in
              PersonCard(person: actor) {
                navigationPath.append(actor)
              }
              .focused($focusedActorId, equals: actor.id)
              .compositingGroup()
              .contextMenu {
                Button {
                  navigationPath.append(actor)
                } label: {
                  Label("详情", systemImage: "info.circle")
                }
              }
            }
            if viewModel.actorsPaginator.isLoadingMore {
              ProgressView()
                .padding(.horizontal)
            }
          }
          .padding(.horizontal, 81)
          .padding(.top, 25)
          .padding(.bottom, 30)
          .onChange(of: focusedActorId) { _, newId in
            Task {
              await viewModel.actorsPaginator.loadMore(newId)
            }
          }
        }
        .scrollClipDisabled()
        .focusSection()
      }
    }
  }

  @ViewBuilder
  private var recommendationsSection: some View {
    if !viewModel.recommendPaginator.items.isEmpty {
      VStack(alignment: .leading, spacing: 0) {
        if showContentPage || firstVisibleRow != "recommendations" {
          Text("推荐")
            .font(.callout)
            .fontWeight(.bold)
            .foregroundStyle(.secondary)
            .padding(.leading, 89)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }

        ScrollView(.horizontal, showsIndicators: false) {
          LazyHStack(spacing: 40) {
            let badges = showContentPage || firstVisibleRow != "recommendations"
            ForEach(viewModel.recommendPaginator.items) { media in
              DetailCardView(
                item: media,
                showBadges: badges,
                onTap: {
                  MediaPreloader.shared.preload(for: media)
                  navigationPath.append(media)
                }
              )
              .equatable()
              .focused($focusedRecommendId, equals: media.id)
              .mediaContextMenu(
                item: media,
                navigationPath: $navigationPath
              )
            }
            if viewModel.recommendPaginator.isLoadingMore {
              ProgressView()
                .padding(.horizontal)
            }
          }
          .padding(.horizontal, 81)
          .padding(.top, 25)
          .padding(.bottom, 30)
          .onChange(of: focusedRecommendId) { _, newId in
            // 聚焦时触发预加载（带 300ms 防抖，避免快速滚动时浪费请求）
            recommendPreloadDebounce?.cancel()
            if let newId = newId,
              let item = viewModel.recommendPaginator.items.first(where: { $0.id == newId })
            {
              recommendPreloadDebounce = Task {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                MediaPreloader.shared.preload(for: item)
              }
            }
            // 分页加载
            Task {
              await viewModel.recommendPaginator.loadMore(newId)
            }
          }
        }
        .scrollClipDisabled()
        .focusSection()
      }
    }
  }

  @ViewBuilder
  private var similarSection: some View {
    if !viewModel.similarPaginator.items.isEmpty {
      VStack(alignment: .leading, spacing: 0) {
        if showContentPage || firstVisibleRow != "similar" {
          Text("类似")
            .font(.callout)
            .fontWeight(.bold)
            .foregroundStyle(.secondary)
            .padding(.leading, 89)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }

        ScrollView(.horizontal, showsIndicators: false) {
          LazyHStack(spacing: 40) {
            let badges = showContentPage || firstVisibleRow != "similar"
            ForEach(viewModel.similarPaginator.items) { media in
              DetailCardView(
                item: media,
                showBadges: badges,
                onTap: {
                  MediaPreloader.shared.preload(for: media)
                  navigationPath.append(media)
                }
              )
              .equatable()
              .focused($focusedSimilarId, equals: media.id)
              .mediaContextMenu(
                item: media,
                navigationPath: $navigationPath
              )
            }
            if viewModel.similarPaginator.isLoadingMore {
              ProgressView()
                .padding(.horizontal)
            }
          }
          .padding(.horizontal, 81)
          .padding(.top, 25)
          .padding(.bottom, 30)
          .onChange(of: focusedSimilarId) { _, newId in
            // 聚焦时触发预加载（带 300ms 防抖）
            similarPreloadDebounce?.cancel()
            if let newId = newId,
              let item = viewModel.similarPaginator.items.first(where: { $0.id == newId })
            {
              similarPreloadDebounce = Task {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                MediaPreloader.shared.preload(for: item)
              }
            }
            // 分页加载
            Task {
              await viewModel.similarPaginator.loadMore(newId)
            }
          }
        }
        .scrollClipDisabled()
        .focusSection()
      }
    }
  }
}
