import SwiftUI

/// 系统状态视图：展示媒体库统计、服务器存储空间以及实时下载器状态
struct StatusView: View {
  @StateObject private var viewModel = StatusViewModel()
  @StateObject private var transferHistoryViewModel = TransferHistoryViewModel()

  var body: some View {
    ScrollView {
      VStack(spacing: 0) {
        // --- 1. 系统状态 ---
        // --- 2. 媒体库统计 ---
        if let statistic = viewModel.statistic {
          MediaStatCard(statistic: statistic)
            .padding(.bottom, 20)
        } else {
          EmptyDataView(title: "暂无媒体库统计", description: "")
            .padding(.bottom, 20)
        }

        // --- 3. 存储与下载器概览 ---
        HStack(alignment: .top, spacing: 20) {
          if let storage = viewModel.storage {
            StorageView(storage: storage, downloader: viewModel.downloader)
          } else {
            EmptyDataView(title: "暂无存储空间信息", description: "")
          }

          if let downloader = viewModel.downloader {
            DownloaderCard(info: downloader)
          } else {
            EmptyDataView(title: "暂无下载器信息", description: "")
          }
        }
        .padding(.bottom, 20)

        Divider()

        DownloadTaskView()
          .padding(.vertical, 20)

        Divider()

        // --- 4. 媒体整理历史 ---
        TransferHistoryView(viewModel: transferHistoryViewModel)
          .padding(.vertical, 20)

      }
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

private struct MiniStat: View {
  let title: String
  let value: String
  let icon: String

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: icon)
      Text(title)
      Text(value)
        .foregroundColor(.primary)
    }
    .font(.headline.bold())
    .foregroundColor(.secondary)
  }
}

private struct MediaStatCard: View {
  let statistic: Statistic

  var body: some View {
    HStack(spacing: 20) {
      MiniStat(title: "电影", value: "\(statistic.movie_count)", icon: "film")
        .frame(maxWidth: .infinity)
      MiniStat(title: "电视剧", value: "\(statistic.tv_count)", icon: "tv")
        .frame(maxWidth: .infinity)
      MiniStat(title: "剧集", value: "\(statistic.episode_count ?? 0)", icon: "film.stack")
        .frame(maxWidth: .infinity)
    }
    .padding()
    .background(Color.white.opacity(0.1))
    .cornerRadius(20)
  }
}

private struct DownloaderCard: View {
  let info: DownloaderInfo

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Label("下载", systemImage: "arrow.down")
        Spacer()
        Text("\(Int64(info.download_speed).formattedBytes())/s")
      }
      HStack {
        Label("上传", systemImage: "arrow.up")
        Spacer()
        Text("\(Int64(info.upload_speed).formattedBytes())/s")
      }
      HStack {
        Label("总量", systemImage: "arrow.up.arrow.down")
          .lineLimit(1)
        Spacer()
        Text(
          "↑ \(Int64(info.upload_size).formattedBytes()) / ↓ \(Int64(info.download_size).formattedBytes())"
        )
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
  let storage: Storage
  let downloader: DownloaderInfo?

  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      Text(
        "存储空间已用：\(Int64(storage.used_storage).formattedBytes()) / \(Int64(storage.total_storage).formattedBytes())"
      )
      ProgressView(value: storage.percent)
        .progressViewStyle(LinearProgressViewStyle())
      if let downloader {
        Text("下载器剩余空间：\(Int64(downloader.free_space).formattedBytes())")
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
