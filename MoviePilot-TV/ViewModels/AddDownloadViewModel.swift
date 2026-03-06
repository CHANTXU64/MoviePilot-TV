import Foundation
import Combine

@MainActor
class AddDownloadViewModel: ObservableObject {
  @Published var downloaders: [DownloaderConf] = []
  @Published var directories: [TransferDirectoryConf] = []
  @Published var selectedDownloader: String?
  @Published var selectedDirectory: String?
  @Published var isLoading = false
  @Published var isSubmitting = false
  @Published var errorMessage: String?

  // 高级选项
  @Published var tmdbId: String = ""

  let torrent: TorrentInfo
  let media: MediaInfo?
  var onSuccess: (() -> Void)?

  init(torrent: TorrentInfo, media: MediaInfo? = nil, onSuccess: (() -> Void)? = nil) {
    self.torrent = torrent
    self.media = media
    self.onSuccess = onSuccess
  }

  // 目标目录的计算属性（URI 格式）
  var targetDirectories: [String] {
    let uris = directories.compactMap { item -> String? in
      guard let path = item.download_path else { return nil }
      if item.storage == "local" {
        return path
      }
      return "\(item.storage):\(path)"
    }
    return Array(Set(uris)).sorted()
  }

  func loadData() async {
    isLoading = true
    defer { isLoading = false }

    do {
      async let downloadersTask = APIService.shared.fetchDownloadClients()
      async let directoriesTask = APIService.shared.fetchDirectories()

      let (fetchedDownloaders, fetchedDirectories) = try await (downloadersTask, directoriesTask)

      self.downloaders = fetchedDownloaders
      self.directories = fetchedDirectories

      // 如果可用，则设置默认值
      if self.selectedDownloader == nil {
        self.selectedDownloader = self.downloaders.first?.name
      }

      // 如果目录为空，则尝试智能选择一个（可选，如果用户手动选择则可能不需要）
    } catch {
      self.errorMessage = "加载配置失败: \(error.localizedDescription)"
    }
  }

  func addDownload() async {
    isSubmitting = true
    defer { isSubmitting = false }

    // 构建请求体
    let tmdbIdInt = Int(tmdbId)

    let payload = AddDownloadRequest(
      torrent_in: torrent,
      downloader: selectedDownloader,
      save_path: selectedDirectory,
      media_in: media,
      tmdbid: tmdbIdInt,
      doubanid: nil
    )

    do {
      let endpoint = media != nil ? "/download/" : "/download/add"
      let _ = try JSONEncoder().encode(payload)

      // APIService 目前还没有一个返回通用 JSON/Success 的通用 post 方法，
      // 但如果我们可以直接使用 makeRequest（如果将其公开或添加一个辅助方法）。
      // 由于 `makeRequest` 是私有的，我们应该向 APIService 添加一个特定的方法。
      // 现在，我将假设我需要向 APIService 添加 `addDownload`。
      let (success, message) = try await APIService.shared.addDownload(payload: payload, endpoint: endpoint)
      if success {
        onSuccess?()
      } else {
        errorMessage = message ?? "添加下载失败"
      }
    } catch {
      errorMessage = "发生错误: \(error.localizedDescription)"
    }
  }
}
