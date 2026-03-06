import Kingfisher
import SwiftUI

/// 系统状态视图：展示媒体库统计、服务器存储空间以及实时下载器状态
struct StatusView: View {
  @StateObject private var viewModel = StatusViewModel()

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 40) {

        // --- 1. 媒体库统计看板 ---
        Text("系统状态")
          .font(.title2)
          .fontWeight(.bold)

        HStack(spacing: 40) {
          StatCard(title: "电影", value: "\(viewModel.statistic?.movie_count ?? 0)", icon: "film")
          StatCard(title: "电视剧", value: "\(viewModel.statistic?.tv_count ?? 0)", icon: "tv")
          StatCard(
            title: "剧集", value: "\(viewModel.statistic?.episode_count ?? 0)", icon: "film.stack")
        }

        // --- 2. 存储与下载器概览 ---
        HStack(alignment: .top, spacing: 40) {
          // A. 存储空间详情展示
          VStack(alignment: .leading, spacing: 20) {
            Text("存储空间")
              .font(.headline)
            if let storage = viewModel.storage {
              StorageView(storage: storage)
            } else {
              ProgressView()
            }
          }
          .frame(maxWidth: .infinity)

          // B. 下载器全局实时速度与剩余空间
          VStack(alignment: .leading, spacing: 20) {
            Text("下载器")
              .font(.headline)
            if let downloader = viewModel.downloader {
              DownloaderView(info: downloader)
            } else {
              ProgressView()
            }
          }
          .frame(maxWidth: .infinity)
        }

        Divider()

        // --- 3. 实时下载任务列表 ---
        HStack {
          Text("下载任务")
            .font(.title2)
            .fontWeight(.bold)

          Spacer()

          // 如果配置了多个下载器，显示切换选择器
          if viewModel.clients.count > 1 {
            Picker("下载器", selection: $viewModel.selectedClient) {
              ForEach(viewModel.clients, id: \.name) { client in
                Text(client.name).tag(client.name)
              }
            }
            .pickerStyle(.segmented)
            .frame(width: 300)
            .onChange(of: viewModel.selectedClient) { _, _ in
              Task { await viewModel.loadDownloads() }
            }
          }
        }

        if viewModel.downloads.isEmpty {
          Text("暂无下载任务")
            .foregroundColor(.secondary)
            .padding()
            .frame(maxWidth: .infinity, alignment: .center)
        } else {
          LazyVStack(spacing: 15) {
            ForEach(viewModel.downloads) { item in
              DownloadItemView(item: item, viewModel: viewModel)
            }
          }
        }
      }
      .padding(.horizontal)
    }
    .task {
      /// 核心异步刷新逻辑：
      /// 1. 初始加载全部数据。
      /// 2. 进入 while 循环，每隔 3 秒调用一次后端接口刷新状态。
      /// 3. 特点：Task 会在视图销毁（onDisappear）时自动取消，无需手动维护定时器。
      while !Task.isCancelled {
        await viewModel.refreshAllData()
        try? await Task.sleep(nanoseconds: 3 * 1_000_000_000)  // 3秒刷新周期
      }
    }
  }
}

private struct DownloadItemView: View {
  let item: DownloadingInfo
  @ObservedObject var viewModel: StatusViewModel

  @State private var showingDeleteConfirm = false

  // 核心逻辑修正：完全对齐 Vue 的 `isDownloading` 布尔逻辑
  // isDownloading 只在 state 为 "downloading" 时为 true
  @State private var isDownloading: Bool

  init(item: DownloadingInfo, viewModel: StatusViewModel) {
    self.item = item
    self.viewModel = viewModel
    // 对齐 Vue 的 isDownloading 逻辑：仅当 state 为 "downloading" 时
    _isDownloading = State(initialValue: item.state?.lowercased() == "downloading")
  }

  /// 核心交互：对齐 Vue 的 `toggleDownload`
  private func handlePrimaryAction() {
    guard let hash = item.hash else { return }

    // 等待服务器真实响应后再翻转，类似 Vue
    Task {
      let operationSuccess: Bool
      if isDownloading {  // 停止
        operationSuccess = await viewModel.stopDownload(hash: hash)
      } else {  // 开始
        operationSuccess = await viewModel.startDownload(hash: hash)
      }

      // API 调用成功，则翻转 UI 状态
      if operationSuccess {
        isDownloading.toggle()
      }
    }
  }

  var body: some View {
    Button(action: handlePrimaryAction) {
      VStack(alignment: .leading, spacing: 10) {
        // 标题对齐 Vue: media.title || name
        let title = item.media?.title ?? item.name ?? "未知任务"
        // 季集对齐 Vue: (media.season media.episode) || season_episode
        let epParts = [item.media?.season, item.media?.episode].compactMap { $0 }
        let epStr = epParts.isEmpty ? (item.season_episode ?? "") : epParts.joined(separator: " ")

        Text(title + " " + epStr)
          .font(.headline)
          .lineLimit(1)
          .padding(.top, 20)
          .padding(.horizontal)

        Text(item.title ?? " ")
          .font(.caption)
          .foregroundColor(.secondary)
          .lineLimit(1)
          .padding(.horizontal)

        HStack(spacing: 20) {
          StateBadge(state: item.state)
          Text(infoText)
            .font(.caption)
            .lineLimit(1)
            .foregroundColor(.secondary)
        }
        .padding(.horizontal)

        if let progress = item.progress, progress > 0 {
          ProgressView(value: progress, total: 100)
            .progressViewStyle(.linear)
            .tint(.green)
            .padding(.horizontal, -10)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .background {
        // 背景图对齐 Vue: 使用 media.image
        let backdropUrl = item.media.flatMap {
          APIService.shared.getDownloadItemBackdropImageUrl($0)
        }

        ZStack {
          KFImage(backdropUrl)
            .requestModifier(AnyModifier.cookieModifier)
            .setProcessor(BlurImageProcessor(blurRadius: 2))
            .resizing(referenceSize: CGSize(width: 500, height: 160), mode: .aspectFill)
            .resizable()
            .aspectRatio(contentMode: .fill)

          LinearGradient(
            gradient: Gradient(colors: [.black.opacity(0.3), .black.opacity(0.7)]),
            startPoint: .top,
            endPoint: .bottom
          )
        }
      }
      .frame(height: 160)
      .clipped()
    }
    .buttonStyle(.card)
    .contextMenu {
      if item.hash != nil {
        // 交互按钮：根据 `isDownloading` 状态显示 "暂停" 或 "继续"
        let actionText = isDownloading ? "暂停" : "继续"
        let actionIcon = isDownloading ? "pause.fill" : "play.fill"
        Button(action: handlePrimaryAction) {
          Label(actionText, systemImage: actionIcon)
        }

        Button(role: .destructive, action: { showingDeleteConfirm = true }) {
          Label("删除", systemImage: "trash.fill")
        }
      }
    }
    .alert("确认删除?", isPresented: $showingDeleteConfirm) {
      Button("删除", role: .destructive) {
        if let hash = item.hash {
          Task { await viewModel.deleteDownload(hash: hash) }
        }
      }
      Button("取消", role: .cancel) {}
    }
    // 同步刷新
    .onChange(of: item.state) { _, newState in
      isDownloading = newState?.lowercased() == "downloading"
    }
  }

  // --- Computed Properties ---

  private var infoText: String {
    // 严格对应 Vue getSpeedText(): {size} ↑ {upspeed}/s ↓ {dlspeed}/s {left_time}
    var parts: [String] = []
    if let size = item.size {
      parts.append(size.formattedBytes())
    } else {
      parts.append("0 B")
    }

    let up = item.upspeed ?? "0B"
    let down = item.dlspeed ?? "0B"

    parts.append("↑ \(up)/s")
    parts.append("↓ \(down)/s")

    if let left = item.left_time, !left.contains("∞") {
      parts.append(left)
    }

    return parts.joined(separator: "   ")
  }
}

private struct StateBadge: View {
  let state: String?

  var body: some View {
    Text(displayState)
      .font(.caption)
      .fontWeight(.medium)
      .padding(.horizontal, 6)
      .padding(.vertical, 3)
      .background(color.opacity(0.3))
      .foregroundColor(color)
      .cornerRadius(6)
  }

  private var displayState: String {
    guard let state = state?.lowercased() else { return "未知" }
    if state.contains("downloading") { return "下载中" }
    if state.contains("paused") { return "已暂停" }
    if state.contains("stalled") { return "排队中" }
    if state.contains("uploading") { return "做种中" }
    if state.contains("checking") { return "校验中" }
    if state.contains("error") { return "错误" }
    if state.contains("missing") { return "文件丢失" }
    if state.contains("queued") { return "等待中" }
    return state.capitalized
  }

  private var color: Color {
    guard let state = state?.lowercased() else { return .secondary }
    if state.contains("downloading") { return .green }
    if state.contains("paused") { return .yellow }
    if state.contains("stalled") { return .orange }
    if state.contains("uploading") { return .blue }
    if state.contains("error") || state.contains("missing") { return .red }
    return .secondary
  }
}

private struct StatCard: View {
  let title: String
  let value: String
  let icon: String

  var body: some View {
    VStack(spacing: 10) {
      Image(systemName: icon)
        .font(.system(size: 50))
        .foregroundColor(.accentColor)
      Text(value)
        .font(.system(size: 40, weight: .bold))
      Text(title)
        .font(.headline)
        .foregroundColor(.secondary)
    }
    .frame(maxWidth: .infinity)
    .padding(30)
    .background(Color.white.opacity(0.1))
    .cornerRadius(20)
  }
}

private struct StorageView: View {
  let storage: Storage

  var body: some View {
    VStack(alignment: .leading) {
      Text(
        "已用: \(Int64(storage.used_storage).formattedBytes()) / \(Int64(storage.total_storage).formattedBytes())"
      )
      ProgressView(value: storage.percent)
        .progressViewStyle(LinearProgressViewStyle())
    }
    .padding()
    .background(Color.white.opacity(0.05))
    .cornerRadius(15)
  }
}

private struct DownloaderView: View {
  let info: DownloaderInfo

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Label("下载: \(Int64(info.download_speed).formattedBytes())/s", systemImage: "arrow.down")
        Spacer()
        Label("上传: \(Int64(info.upload_speed).formattedBytes())/s", systemImage: "arrow.up")
      }
      Text("剩余空间: \(Int64(info.free_space).formattedBytes())")
        .font(.caption)
        .foregroundColor(.secondary)
    }
    .padding()
    .background(Color.white.opacity(0.05))
    .cornerRadius(15)
  }
}
