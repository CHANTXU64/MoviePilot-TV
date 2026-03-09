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
              TorrentDownloadRow(item: item, viewModel: viewModel)
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
