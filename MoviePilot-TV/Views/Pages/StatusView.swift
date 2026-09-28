import SwiftUI

/// 系统状态视图：展示媒体库统计、服务器存储空间以及实时下载器状态
struct StatusView: View {
  /// 剧集统计投影：后端 nil 表示所有媒体服务均未提供，显示“未获取”；真实 0/正数原样显示。
  static func episodeCountText(_ count: Int?) -> String {
    count.map(String.init) ?? "未获取"
  }

  private let isSelected: Bool
  @StateObject private var viewModel = StatusViewModel()
  @StateObject private var transferHistoryViewModel = TransferHistoryViewModel()
  @StateObject private var imageLifecycleCoordinator = ImageNavigationCoordinator()
  @Environment(\.scenePhase) private var scenePhase

  init(isSelected: Bool = true) {
    self.isSelected = isSelected
  }

  var body: some View {
    ScrollView {
      VStack(spacing: 0) {
        // 媒体库统计、存储空间与下载器概览仅对 superuser 展示；
        // manage-only 不请求这些 Dashboard 数据，隐藏整组。
        if viewModel.canRequestSuperUserEndpoints {
          MediaStatCard(
            statistic: viewModel.statistic,
            unavailableValueText: viewModel.unavailableValueText
          )
          .padding(.bottom, 20)

          HStack(alignment: .top, spacing: 20) {
            StorageView(
              storage: viewModel.storage,
              downloader: viewModel.downloader,
              unavailableValueText: viewModel.unavailableValueText
            )
            DownloaderCard(
              info: viewModel.downloader,
              unavailableValueText: viewModel.unavailableValueText
            )
          }
          .padding(.bottom, 20)

          Divider()
        }

        DownloadTaskView(isSelected: isSelected)
          .padding(.vertical, 20)

        Divider()

        // --- 4. 媒体整理历史 ---
        TransferHistoryView(
          viewModel: transferHistoryViewModel,
          isSelected: isSelected,
          keepsRowsMounted: TransferHistoryView.shouldMountRows(
            isSelected: isSelected,
            isStackForeground: imageLifecycleCoordinator.rootLifecycle.isStackForeground
          )
        )
          .padding(.vertical, 20)

      }
    }
    .task(id: isSelected) {
      guard isSelected else { return }
      /// 核心异步刷新逻辑：
      /// 1. 初始加载全部数据。
      /// 2. 进入 while 循环，每隔 3 秒调用一次后端接口刷新状态。
      /// 3. 特点：Task 会在视图销毁（onDisappear）时自动取消，无需手动维护定时器。
      while !Task.isCancelled {
        await viewModel.refreshAllData()
        try? await Task.sleep(nanoseconds: 3 * 1_000_000_000)  // 3秒刷新周期
      }
    }
    .environment(\.pageImageLifecycle, imageLifecycleCoordinator.rootLifecycle)
    .onAppear { updateImageLifecycle() }
    .onChange(of: isSelected) { _, _ in updateImageLifecycle() }
    .onChange(of: scenePhase) { _, _ in updateImageLifecycle() }
  }

  private func updateImageLifecycle() {
    imageLifecycleCoordinator.setStackPresentation(
      isSelected: isSelected,
      scenePhase: scenePhase
    )
  }
}

private struct MiniStat: View {
  let title: String
  let value: String
  let icon: String

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: icon)
      Text(title)
      Spacer(minLength: 10)
      Text(value)
        .foregroundColor(.primary)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
    .font(.headline.bold())
    .foregroundColor(.secondary)
  }
}

private struct MediaStatCard: View {
  let statistic: Statistic?
  let unavailableValueText: String

  var body: some View {
    HStack(spacing: 20) {
      MiniStat(
        title: "电影",
        value: statistic.map { String($0.movie_count) } ?? unavailableValueText,
        icon: "film"
      )
        .frame(maxWidth: .infinity)
      MiniStat(
        title: "电视剧",
        value: statistic.map { String($0.tv_count) } ?? unavailableValueText,
        icon: "tv"
      )
        .frame(maxWidth: .infinity)
      MiniStat(
        title: "剧集",
        value: statistic.map { StatusView.episodeCountText($0.episode_count) }
          ?? unavailableValueText,
        icon: "film.stack"
      )
        .frame(maxWidth: .infinity)
    }
    .padding()
    .background(Color.white.opacity(0.1))
    .cornerRadius(20)
  }
}

private struct DownloaderCard: View {
  let info: DownloaderInfo?
  let unavailableValueText: String

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Label("下载", systemImage: "arrow.down")
        Spacer()
        Text(info.map { "\(Int64($0.download_speed).formattedBytes())/s" }
          ?? unavailableValueText)
      }
      HStack {
        Label("上传", systemImage: "arrow.up")
        Spacer()
        Text(info.map { "\(Int64($0.upload_speed).formattedBytes())/s" }
          ?? unavailableValueText)
      }
      HStack {
        Label("总量", systemImage: "arrow.up.arrow.down")
          .lineLimit(1)
        Spacer()
        Text(info.map {
          "↑ \(Int64($0.upload_size).formattedBytes()) / ↓ \(Int64($0.download_size).formattedBytes())"
        } ?? unavailableValueText)
        .lineLimit(1)
      }
    }
    .font(.callout)
    .foregroundColor(.secondary)
    .padding()
    .frame(maxWidth: .infinity)
    .background(Color.white.opacity(0.1))
    .cornerRadius(20)
  }
}

private struct StorageView: View {
  let storage: Storage?
  let downloader: DownloaderInfo?
  let unavailableValueText: String

  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      HStack {
        Text("存储空间已用")
        Spacer()
        Text(storage.map {
          "\(Int64($0.used_storage).formattedBytes()) / \(Int64($0.total_storage).formattedBytes())"
        } ?? unavailableValueText)
          .lineLimit(1)
      }
      ProgressView(value: storage?.percent ?? 0)
        .progressViewStyle(LinearProgressViewStyle())
        .accessibilityHidden(storage == nil)
      HStack {
        Text("下载器剩余空间")
        Spacer()
        Text(downloader.map { Int64($0.free_space).formattedBytes() }
          ?? unavailableValueText)
          .lineLimit(1)
      }
    }
    .font(.callout)
    .foregroundColor(.secondary)
    .padding()
    .frame(maxWidth: .infinity)
    .background(Color.white.opacity(0.1))
    .cornerRadius(20)
  }
}
