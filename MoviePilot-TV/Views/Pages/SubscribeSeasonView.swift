import Kingfisher
import SwiftUI

struct SubscribeSeasonView: View {
  @StateObject private var viewModel: SubscribeSeasonViewModel

  init(mediaInfo: MediaInfo, initialSeason: Int? = nil) {
    _viewModel = StateObject(
      wrappedValue: SubscribeSeasonViewModel(
        mediaInfo: mediaInfo, initialSeason: initialSeason))
  }

  var body: some View {
    ScrollView {
      SubscribeSeasonContentView(viewModel: viewModel, layout: .grid)
    }
    .focusSection()
    .task {
      await viewModel.loadData()
    }
  }
}

/// Shared content view used both in standalone SubscribeSeasonView and embedded in MediaDetailView
enum SeasonLayout {
  case shelf
  case grid
}

struct SubscribeSeasonContentView: View {
  @ObservedObject var viewModel: SubscribeSeasonViewModel
  var layout: SeasonLayout = .shelf
  var title: String? = nil
  var showBadges: Bool = true
  var onSeasonTap: ((TmdbSeason) -> Void)? = nil
  var onMoreTapped: (() -> Void)? = nil

  @State private var selectedSeasonDetail: TmdbSeason?
  @FocusState private var focusedSeasonId: Int?
  @FocusState private var isTopRedirectorFocused: Bool
  @FocusState private var isBottomRedirectorFocused: Bool

  var body: some View {
    VStack(spacing: 0) {
      // Error Banner
      if let error = viewModel.errorMessage {
        HStack {
          Image(systemName: "exclamationmark.triangle.fill")
          Text(error)
          Spacer()
          Button {
            viewModel.errorMessage = nil
          } label: {
            Image(systemName: "xmark")
          }
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .foregroundColor(.red)
      }

      // Header Section (Title + Picker)
      VStack(spacing: 0) {
        if layout == .grid {
          Text("订阅   \(viewModel.mediaInfo.title ?? "")")
            .font(.largeTitle.bold())
            .foregroundColor(.secondary)
        }
        headerSection
      }
      .padding(.bottom, layout == .grid ? 20 : 0)

      if viewModel.isLoading {
        ProgressView("加载中...")
          .frame(maxWidth: .infinity, minHeight: 200)
      } else if viewModel.seasonInfos.isEmpty {
        VStack(spacing: 16) {
          Image(systemName: "doc.text.magnifyingglass")
            .font(.system(size: 48))
            .foregroundColor(.gray)
          Text("未查询到季集信息")
            .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
      } else {
        switch layout {
        case .shelf:
          ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 40) {
              let displayCount = min(10, viewModel.seasonInfos.count)
              ForEach(viewModel.seasonInfos.prefix(displayCount), id: \.self) { season in
                seasonCard(season)
                  .focused($focusedSeasonId, equals: season.season_number)
              }
              if viewModel.seasonInfos.count > 10 {
                let nextSeason = viewModel.seasonInfos[displayCount]
                viewAllCard(nextSeason: nextSeason)
                  .focused($focusedSeasonId, equals: -1)
              }
            }
            .padding(.horizontal, 81)
            .padding(.top, 25)
            .padding(.bottom, 30)
          }
          .scrollClipDisabled()
          .focusSection()
        case .grid:
          VStack(spacing: 0) {
            // Top Focus Redirector: Catches focus when navigating down from header
            Color.clear
              .frame(height: 1)
              .focusable(focusedSeasonId == nil)
              .focused($isTopRedirectorFocused)
              .onChange(of: isTopRedirectorFocused) { _, isFocused in
                if isFocused {
                  focusedSeasonId = viewModel.seasonInfos.first?.season_number
                  isTopRedirectorFocused = false
                }
              }

            LazyVGrid(columns: MediaCard.defaultGridColumns, spacing: 40) {
              ForEach(viewModel.seasonInfos, id: \.self) { season in
                seasonCard(season)
                  .focused($focusedSeasonId, equals: season.season_number)
              }
            }
            .padding()

            // Focus Redirector: Catches focus when navigating down from an incomplete row
            Color.clear
              .frame(height: 1)
              .focusable()
              .focused($isBottomRedirectorFocused)
              .onChange(of: isBottomRedirectorFocused) { _, isFocused in
                if isFocused {
                  focusedSeasonId = viewModel.seasonInfos.last?.season_number
                  isBottomRedirectorFocused = false
                }
              }
          }
        }
      }
    }
    .sheet(item: $selectedSeasonDetail) { season in
      SeasonDetailSheet(season: season, mediaInfo: viewModel.mediaInfo)
    }
    .sheet(item: $viewModel.sheetSubscribe) { subscribe in
      SubscribeSheet(subscribe: subscribe, isNewSubscription: true)
        .onDisappear {
          Task {
            await viewModel.checkSeasonsStatus()
            await viewModel.checkSubscriptionStatus()
          }
        }
    }
    .alert(
      "取消订阅",
      isPresented: Binding(
        get: { viewModel.showUnsubscribeConfirm != nil },
        set: { if !$0 { viewModel.showUnsubscribeConfirm = nil } }
      )
    ) {
      Button("取消", role: .cancel) {}
      Button("确认取消订阅", role: .destructive) {
        if let season = viewModel.showUnsubscribeConfirm {
          Task { await viewModel.unsubscribeSeason(season) }
        }
      }
    } message: {
      if let season = viewModel.showUnsubscribeConfirm {
        Text("确定要取消第 \(season) 季的订阅吗？")
      }
    }
  }

  @ViewBuilder
  private var episodeGroupPicker: some View {
    if !viewModel.episodeGroups.isEmpty {
      Picker("剧集组", selection: $viewModel.selectedGroupId) {
        Text("剧集组：默认").tag("")
        ForEach(viewModel.episodeGroups) { group in
          Text("剧集组：\(group.name)").tag(group.id)
        }
      }
      .pickerStyle(.menu)
      .onChange(of: viewModel.selectedGroupId) { _, _ in
        Task { await viewModel.fetchSeasons() }
      }
    }
  }

  @ViewBuilder
  private var headerSection: some View {
    if let title = title {
      let content = HStack {
        Text(title)
          .font(.callout)
          .fontWeight(.bold)
          .foregroundStyle(.secondary)

        Spacer()

        HStack(spacing: 20) {
          episodeGroupPicker

          if layout == .shelf, viewModel.seasonInfos.count > 10 {
            Button("展开") {
              onMoreTapped?()
            }
          }
        }
      }
      .padding(.horizontal, 89)
      .padding(.vertical, 0)

      if !viewModel.episodeGroups.isEmpty || (layout == .shelf && viewModel.seasonInfos.count > 10) {
        content.focusSection()
      } else {
        content
      }
    } else if layout == .grid && !viewModel.episodeGroups.isEmpty {
      HStack {
        Spacer()
        episodeGroupPicker
      }
      .padding(.vertical, 0)
      .focusSection()
    }
  }

  @ViewBuilder
  private func seasonCard(_ season: TmdbSeason) -> some View {
    let seasonNumber = season.season_number ?? 0
    let isSubscribed = viewModel.isSeasonSubscribed(seasonNumber)

    let seasonName =
      (seasonNumber == 0 && !(season.name?.isEmpty ?? true))
      ? season.name! : "第 \(seasonNumber) 季"
    let title =
      "\(seasonName)\(season.air_date != nil ? " · " + (season.air_date?.prefix(4) ?? "") : "")"
    let statusText = viewModel.getStatusText(season: seasonNumber)
    let episodeCount = season.episode_count ?? 0
    let bottomLeft = "\(episodeCount) 集 · \(statusText)"

    MediaCard(
      title: title,
      posterUrl: APIService.shared.getSeasonPosterURL(
        posterPath: season.poster_path,
        mediaPosterPath: viewModel.mediaInfo.poster_path
      ),
      typeText: nil,
      ratingText: (season.vote_average ?? 0) > 0
        ? String(format: "%.1f", season.vote_average!) : nil,
      bottomLeftText: bottomLeft,
      bottomLeftSecondaryText: nil,
      source: nil,
      showBadges: showBadges,
      footerLabel: (
        icon: isSubscribed ? "minus.circle" : "plus.circle",
        text: isSubscribed ? "取消订阅" : "订阅"
      ),
      action: {
        if isSubscribed {
          viewModel.showUnsubscribeConfirm = seasonNumber
        } else {
          viewModel.prepareSubscription(seasonNumber: seasonNumber)
        }
      }
    )
    .compositingGroup()
    .contextMenu {
      if isSubscribed {
        Button(role: .destructive) {
          viewModel.showUnsubscribeConfirm = seasonNumber
        } label: {
          Label("取消订阅", systemImage: "minus.circle")
        }
      } else {
        Button {
          viewModel.prepareSubscription(seasonNumber: seasonNumber)
        } label: {
          Label("订阅", systemImage: "plus.circle")
        }
      }

      Button {
        selectedSeasonDetail = season
      } label: {
        Label("详情", systemImage: "info.circle")
      }
    }
  }

  @ViewBuilder
  private func viewAllCard(nextSeason: TmdbSeason) -> some View {
    MoreCard(
      titleText: "查看全部",
      posterUrl: APIService.shared.getSeasonPosterURL(
        posterPath: nextSeason.poster_path,
        mediaPosterPath: viewModel.mediaInfo.poster_path
      ),
      action: {
        onMoreTapped?()
      }
    )
  }
}

struct SeasonDetailSheet: View {
  let season: TmdbSeason
  let mediaInfo: MediaInfo
  @State private var isImageFailed = false

  var body: some View {
    HStack(alignment: .top, spacing: 60) {
      // Poster
      ZStack {
        Rectangle()
          .fill(Color(white: 0.12))
          .overlay(
            Image(systemName: "film")
              .font(.title2)
              .foregroundColor(.gray)
          )

        if !isImageFailed,
          let posterUrl = APIService.shared.getSeasonPosterURL(
            posterPath: season.poster_path,
            mediaPosterPath: mediaInfo.poster_path
          )
        {
          KFImage(posterUrl)
            .requestModifier(AnyModifier.cookieModifier)
            .onFailure { _ in
              isImageFailed = true
            }
            .placeholder {
              Rectangle()
                .fill(Color(white: 0.12))
                .overlay(ProgressView().tint(.gray))
            }
            .resizing(referenceSize: CGSize(width: 360, height: 540), mode: .aspectFill)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: 360)
            .clipped()
        }
      }
      .frame(width: 360)
      .cornerRadius(20)

      // Info
      VStack(alignment: .leading, spacing: 30) {
        VStack(alignment: .leading, spacing: 10) {
          Text(mediaInfo.title ?? "")
            .font(.title3)
            .foregroundColor(.secondary)
          Text(season.name ?? "第 \(season.season_number ?? 0) 季")
            .font(.headline)
        }

        HStack(spacing: 30) {
          if let date = season.air_date {
            Label(date, systemImage: "calendar")
          }
          if let count = season.episode_count {
            Label("共 \(count) 集", systemImage: "play.circle")
          }
          if let vote = season.vote_average, vote > 0 {
            Label(String(format: "%.1f", vote), systemImage: "star.fill")
              .foregroundColor(.yellow)
          }
        }
        .font(.body)

        if let overview = season.overview, !overview.isEmpty {
          Text(overview)
            .font(.body)
            .foregroundColor(.secondary)
        }
      }
      .frame(width: 900, alignment: .leading)
    }
    .padding(50)
  }
}
