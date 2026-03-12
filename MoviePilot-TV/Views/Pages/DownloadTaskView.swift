import Kingfisher
import SwiftUI

struct DownloadTaskView: View {
  @StateObject private var viewModel = DownloadTaskViewModel()
  @State private var isExpanded = true

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      HStack {
        Text("下载任务")
          .font(.body)
          .fontWeight(.bold)
          .foregroundStyle(.secondary)
          .padding(.leading, 8)

        Spacer()

        HStack(spacing: 20) {
          if viewModel.clients.count > 1 {
            Picker("下载器", selection: $viewModel.selectedClient) {
              ForEach(viewModel.clients, id: \.name) { client in
                Text("下载器：" + client.name).tag(client.name)
              }
            }
            .pickerStyle(.menu)
            .onChange(of: viewModel.selectedClient) { _, _ in
              Task { await viewModel.loadDownloads() }
            }
          }
          Button(isExpanded ? "收起" : "展开") {
            withAnimation {
              isExpanded.toggle()
            }
          }
        }
      }
      .focusSection()

      if isExpanded {
        if viewModel.downloads.isEmpty {
          Text("暂无下载任务")
            .foregroundColor(.secondary)
            .padding()
            .frame(maxWidth: .infinity, alignment: .center)
        } else {
          LazyVStack(spacing: 15) {
            ForEach(viewModel.downloads) { item in
              DownloadTaskRow(item: item, viewModel: viewModel)
            }
          }
        }
      }
    }
    .task {
      await viewModel.initialLoad()
      while !Task.isCancelled {
        await viewModel.loadDownloads()
        try? await Task.sleep(nanoseconds: 3 * 1_000_000_000)  // 3 seconds
      }
    }
  }
}

/// 显示一个下载任务（种子）的行视图，包含封面、信息、进度和可交互的操作按钮。
private struct DownloadTaskRow: View {
  @ObservedObject var item: DownloadingInfo
  let viewModel: DownloadTaskViewModel

  @State private var showingDeleteConfirm = false

  // 核心逻辑修正：完全对齐 Vue 的 `isDownloading` 布尔逻辑
  // 仅当 state 为 "downloading" 时为 true，用于控制“暂停/继续”按钮的状态。
  @State private var isDownloading: Bool

  init(item: DownloadingInfo, viewModel: DownloadTaskViewModel) {
    self.item = item
    self.viewModel = viewModel
    _isDownloading = State(initialValue: item.state?.lowercased() == "downloading")
  }

  /// 核心交互：对齐 Vue 的 `toggleDownload`
  /// 切换下载状态（暂停/继续）。
  private func toggleDownload() {
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

  /// 根据当前状态生成的操作按钮描述。
  private var actionDescriptors: [ActionDescriptor] {
    let toggleActionTitle = isDownloading ? "暂停" : "继续"
    let toggleActionIcon = isDownloading ? "pause.fill" : "play.fill"

    return [
      ActionDescriptor(
        id: "toggle",
        title: toggleActionTitle,
        icon: toggleActionIcon,
        role: .normal,
        action: toggleDownload
      ),
      ActionDescriptor(
        id: "delete",
        title: "删除",
        icon: "trash.fill",
        role: .destructive,
        action: { showingDeleteConfirm = true }
      ),
    ]
  }

  var body: some View {
    ActionRow(
      actions: actionDescriptors
    ) { isFocused in
      // MARK: - 主内容
      VStack(alignment: .leading, spacing: 10) {
        // 标题对齐 Vue: media.title || name
        let title = item.media?.title ?? item.name ?? "未知任务"
        // 季集对齐 Vue: (media.season media.episode) || season_episode
        let epInfo = [item.media?.season, item.media?.episode].compactMap { $0 }.joined(separator: " ")

        HStack(spacing: 20) {
          Text(title)
            .foregroundColor(isFocused ? .primary : .primary.opacity(0.6))
          Text("\(epInfo.isEmpty ? (item.season_episode ?? "") : epInfo)")
            .foregroundColor(.secondary)
        }
        .font(.headline)
        .lineLimit(1)

        Text(item.title ?? " ")
          .font(.caption)
          .foregroundColor(.secondary)
          .lineLimit(1)

        HStack(spacing: 20) {
          StateBadge(stateString: item.state)
          Text(downloadStatsText)
            .font(.caption)
            .lineLimit(1)
            .foregroundColor(.secondary)
        }
      }
      .padding()
      .frame(maxWidth: .infinity, alignment: .topLeading)
    } background: {
      // MARK: - 背景
      let backdropUrl = item.media.flatMap(APIService.shared.getDownloadItemBackdropImageUrl)
      ZStack {
        KFImage(backdropUrl)
          .requestModifier(AnyModifier.cookieModifier)
          .setProcessor(BlurImageProcessor(blurRadius: 2))
          .resizing(referenceSize: CGSize(width: 500, height: 180), mode: .aspectFill)
          .resizable()
          .aspectRatio(contentMode: .fill)

        Color.black.opacity(0.6)
      }
    } progressBar: {
      // MARK: - 进度条
      if let progress = item.progress, progress > 0 {
        ProgressView(value: progress, total: 100)
          .progressViewStyle(.linear)
          .tint(.green)
          .padding(.bottom, -7)  // 微调使进度条紧贴底部
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
    .onChange(of: item.state) { _, newState in
      // 实时同步来自服务器的状态变更
      isDownloading = newState?.lowercased() == "downloading"
    }
  }

  /// 格式化用于显示的下载统计信息文本。
  private var downloadStatsText: String {
    // 格式: {size} ↑ {upspeed}/s ↓ {dlspeed}/s {left_time}
    var parts: [String] = []

    parts.append(item.size?.formattedBytes() ?? "0 B")
    parts.append("↑ \((item.upspeed ?? "0B"))/s")
    parts.append("↓ \((item.dlspeed ?? "0B"))/s")

    if let timeLeft = item.left_time, !timeLeft.contains("∞") {
      parts.append(timeLeft)
    }

    return parts.joined(separator: "   ")
  }
}

// MARK: - 下载状态徽章 (StateBadge)

/// 表示下载状态的枚举，提供类型安全的替代方案来替代基于字符串的检查。
private enum DownloadState {
  case downloading
  case paused
  case stalled
  case uploading
  case checking
  case error
  case missing
  case queued
  case unknown(String)

  init(stateString: String?) {
    guard let state = stateString?.lowercased() else {
      self = .unknown("未知")
      return
    }

    if state.contains("downloading") {
      self = .downloading
    } else if state.contains("paused") {
      self = .paused
    } else if state.contains("stalled") {
      self = .stalled
    } else if state.contains("uploading") {
      self = .uploading
    } else if state.contains("checking") {
      self = .checking
    } else if state.contains("error") {
      self = .error
    } else if state.contains("missing") {
      self = .missing
    } else if state.contains("queued") {
      self = .queued
    } else {
      self = .unknown(state.capitalized)
    }
  }

  /// 用于UI上显示的本地化状态文本。
  var displayText: String {
    switch self {
    case .downloading: "下载中"
    case .paused: "已暂停"
    case .stalled: "排队中"
    case .uploading: "做种中"
    case .checking: "校验中"
    case .error: "错误"
    case .missing: "文件丢失"
    case .queued: "等待中"
    case .unknown(let str): str
    }
  }

  /// 与每个状态关联的颜色。
  var color: Color {
    switch self {
    case .downloading: .green
    case .paused: .yellow
    case .stalled: .orange
    case .uploading: .blue
    case .error, .missing: .red
    case .checking, .queued, .unknown: .secondary
    }
  }
}

/// 一个根据下载状态显示不同颜色和文本的徽章视图。
private struct StateBadge: View {
  let state: DownloadState

  init(stateString: String?) {
    self.state = DownloadState(stateString: stateString)
  }

  var body: some View {
    Text(state.displayText)
      .font(.caption)
      .fontWeight(.medium)
      .padding(.horizontal, 10)
      .padding(.vertical, 3)
      .background(state.color.opacity(0.3))
      .foregroundColor(state.color)
      .cornerRadius(6)
  }
}
