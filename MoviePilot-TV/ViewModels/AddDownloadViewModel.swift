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
  private let apiService: APIService

  init(
    torrent: TorrentInfo,
    media: MediaInfo? = nil,
    onSuccess: (() -> Void)? = nil,
    apiService: APIService = .shared
  ) {
    self.torrent = torrent
    self.media = media
    self.onSuccess = onSuccess
    self.apiService = apiService
    self.mediaSource =
      MediaSearchSource(
        rawValue: apiService.settings?.RECOGNIZE_SOURCE ?? ""
      ) ?? .themoviedb
  }

  // 目标目录的计算属性（URI 格式）
  //
  // F-135：内建「自动」选项的 value 就是空串，所以空目录不能进这个列表 ——
  // 本地空目录会和「自动」撞成同一个 ID，远程空目录则会生成 `"qb:"` 这种并不存在的路径
  // （用户选中后提交会被后端拒绝）。因此必须**先 trim、再丢空、最后去重**：顺序反过来的话
  // 纯空白路径会活下来变成选项。这样处理后「自动」在结果中天然唯一，无需额外占位。
  // `storage` 缺省即本地目录，与 Web `convertToUri` 的 undefined/null/local 三态一致。
  var targetDirectories: [String] {
    let uris = directories.compactMap { item -> String? in
      guard
        let path = item.download_path?.trimmingCharacters(in: .whitespacesAndNewlines),
        !path.isEmpty
      else { return nil }
      guard let storage = item.storage, storage != "local" else { return path }
      return "\(storage):\(path)"
    }
    var seen = Set<String>()
    return uris.filter { seen.insert($0).inserted }
  }

  var isMediaIdValid: Bool {
    MediaIdentifier.isValidManualMediaId(mediaId)
  }

  func loadData() async {
    loadErrorMessage = nil
    guard apiService.canAccess(.search) else {
      clearLoadedOptions()
      return
    }

    let sessionSnapshot = apiService.sessionSnapshot()
    isLoading = true
    defer { isLoading = false }

    do {
      async let downloadersTask = apiService.fetchDownloadClients()
      async let directoriesTask = apiService.fetchDirectories()
      let (fetchedDownloaders, fetchedDirectories) = try await (
        downloadersTask, directoriesTask
      )
      guard apiService.isSessionUnchanged(from: sessionSnapshot),
        apiService.canAccess(.search)
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
    guard !isSubmitting else { return }
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
      let (success, message) = try await apiService.addDownload(payload: payload)
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
