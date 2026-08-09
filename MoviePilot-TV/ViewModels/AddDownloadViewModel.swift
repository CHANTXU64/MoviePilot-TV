import Combine
import Foundation

@MainActor
class AddDownloadViewModel: ObservableObject {
  @Published var downloaders: [DownloaderConf] = []
  @Published var directories: [TransferDirectoryConf] = []
  @Published var selectedDownloader: String?
  @Published var selectedDirectory: String?
  @Published var isLoading = false
  @Published var isSubmitting = false
  @Published var loadErrorMessage: String?
  @Published var errorMessage: String?

  // 高级选项
  @Published var mediaSource: MediaSearchSource
  @Published var mediaId: String = ""

  let torrent: TorrentInfo
  let media: MediaInfo?
  var onSuccess: (() -> Void)?

  init(torrent: TorrentInfo, media: MediaInfo? = nil, onSuccess: (() -> Void)? = nil) {
    self.torrent = torrent
    self.media = media
    self.onSuccess = onSuccess
    self.mediaSource =
      MediaSearchSource(
        rawValue: APIService.shared.settings?.RECOGNIZE_SOURCE ?? ""
      ) ?? .themoviedb
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
    var seen = Set<String>()
    return uris.filter { seen.insert($0).inserted }
  }

  var isMediaIdValid: Bool {
    MediaIdentifier.isValidManualMediaId(mediaId)
  }

  func loadData() async {
    loadErrorMessage = nil
    guard APIService.shared.canAccess(.search) else {
      clearLoadedOptions()
      return
    }

    let sessionSnapshot = APIService.shared.sessionSnapshot()
    isLoading = true
    defer { isLoading = false }

    do {
      async let downloadersTask = APIService.shared.fetchDownloadClients()
      async let directoriesTask = APIService.shared.fetchDirectories()
      let (fetchedDownloaders, fetchedDirectories) = try await (
        downloadersTask, directoriesTask
      )
      guard APIService.shared.isSessionUnchanged(from: sessionSnapshot),
        APIService.shared.canAccess(.search)
      else {
        clearLoadedOptions()
        return
      }

      downloaders = fetchedDownloaders
      directories = fetchedDirectories
    } catch {
      Logger.error("Failed to load add-download options: \(error)")
      loadErrorMessage = "下载设置没有加载完成，请重试。"
    }
  }

  private func clearLoadedOptions() {
    downloaders = []
    directories = []
    selectedDownloader = nil
    selectedDirectory = nil
  }

  func addDownload() async {
    errorMessage = nil
    guard isMediaIdValid else {
      errorMessage = "媒体 ID 只能包含数字。"
      return
    }
    isSubmitting = true
    defer { isSubmitting = false }

    // 构建请求体
    let normalizedMediaId = mediaId.trimmingCharacters(in: .whitespacesAndNewlines)

    let payload = AddDownloadRequest(
      torrent_in: torrent,
      downloader: selectedDownloader,
      save_path: selectedDirectory,
      media_in: media,
      tmdbid: nil,
      doubanid: nil,
      bangumiid: nil,
      anilistid: nil,
      media_source: normalizedMediaId.isEmpty ? nil : mediaSource.rawValue,
      media_id: normalizedMediaId.isEmpty ? nil : normalizedMediaId
    )
    do {
      let (success, message) = try await APIService.shared.addDownload(payload: payload)
      if success {
        onSuccess?()
      } else {
        Logger.error("Add-download request returned false: \(message ?? "no backend message")")
        if let message = message?.trimmingCharacters(in: .whitespacesAndNewlines),
          !message.isEmpty
        {
          errorMessage = message
        } else {
          errorMessage = "暂时无法添加下载，请稍后重试。"
        }
      }
    } catch is CancellationError {
      return
    } catch {
      Logger.error("Failed to add download: \(error)")
      errorMessage = "暂时无法添加下载，请稍后重试。"
    }
  }
}
