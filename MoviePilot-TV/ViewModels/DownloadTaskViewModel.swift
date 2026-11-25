import Combine
import Foundation
import SwiftUI

@MainActor
class DownloadTaskViewModel: ObservableObject {
  // 显式非隔离析构，避开 tvOS 18 的隔离析构回部署崩溃。
  nonisolated deinit {}

  @Published var clients: [DownloaderConf] = []
  @Published var selectedClient: String = ""
  @Published var downloads: [DownloadingInfo] = []
  @Published private(set) var loadedClient: String = ""
  @Published private(set) var clientsLoadFailed = false
  /// 第一次结果之前任务列表请求失败的下载器。绑定下载器：切到别的下载器后不沿用失败文字。
  @Published private(set) var downloadsLoadFailedClient: String?
  /// `/download/` 返回 403：当前账号没有下载管理权限。保留区块，只显示权限提示并停止重试。
  @Published private(set) var downloadsPermissionDenied = false
  @Published var errorMessage: String?

  var canOperateDownloads: Bool {
    !loadedClient.isEmpty && loadedClient == selectedClient
  }

  private let apiService: APIService
  private var downloadLoadGeneration = 0
  private var presentationGeneration = 0
  private var isPresentationActive = true
  private var hasLoadedClients = false
  private var consecutiveClientsFailures = 0
  private var consecutiveDownloadsFailures = 0

  private static let pollingFailureNotificationThreshold = 5

  /// 下载管理权限的 403 语义从 v3.2.11 起才成立：此前 `/download/` 只要求全局 manage，
  /// 读到 403 不能说明 `manage.downloading` 被关闭。
  nonisolated static let downloadPermissionMinimumBackendVersion = "v3.2.11"

  nonisolated static func supportsDownloadPermissionState(backendVersion: String?) -> Bool {
    BackendVersionGate.isAvailable(
      since: downloadPermissionMinimumBackendVersion,
      backendVersion: backendVersion
    )
  }

  init(apiService: APIService = .shared) {
    self.apiService = apiService
  }

  /// 当前选中的下载器还没拿到任务列表时（首次进入或刚切换下载器），列表区域显示什么。
  /// 拿到后为 nil，按实际列表显示；下载器列表失败、没有下载器或无权限时也为 nil，沿用各自原有的文字。
  enum PendingLoadState: Equatable {
    /// 还在等这个下载器的第一次结果：转圈，不能先说「暂无下载任务」，也不显示上一个下载器的任务。
    case loading
    /// 这个下载器在拿到结果前请求失败：轮询继续自动重试，同时一直显示失败文字。
    case failed
  }

  var pendingLoadState: PendingLoadState? {
    guard apiService.canAccess(.manage), !clientsLoadFailed, !downloadsPermissionDenied else {
      return nil
    }
    if hasLoadedClients && selectedClient.isEmpty { return nil }
    guard !canOperateDownloads else { return nil }
    return downloadsLoadFailedClient == selectedClient ? .failed : .loading
  }

  /// 主 Tab 生命周期门禁。generation 让“切走后又快速切回”的旧独立 Task 也无法写回。
  func setPresentationActive(_ isActive: Bool) {
    guard isPresentationActive != isActive else { return }
    isPresentationActive = isActive
    if isActive {
      // 重新进入状态页时再试一次；管理员可能已经补开下载管理权限。
      downloadsPermissionDenied = false
    }
    presentationGeneration &+= 1
    downloadLoadGeneration &+= 1
  }

  func initialLoad() async {
    let currentPresentationGeneration = presentationGeneration
    guard isPresentationActive, !Task.isCancelled else { return }
    guard apiService.canAccess(.manage) else {
      clearForRestrictedUser()
      return
    }
    let sessionSnapshot = apiService.sessionSnapshot()
    await loadClientsIfNeeded()
    guard isPresentationActive,
      currentPresentationGeneration == presentationGeneration,
      !Task.isCancelled,
      apiService.isSessionUnchanged(from: sessionSnapshot)
    else { return }
    await loadDownloads()
  }

  func loadClientsIfNeeded() async {
    let currentPresentationGeneration = presentationGeneration
    guard isPresentationActive, !Task.isCancelled, !hasLoadedClients else { return }
    let sessionSnapshot = apiService.sessionSnapshot()
    do {
      let loadedClients = try await apiService.fetchDownloadClients()
      guard isPresentationActive,
        currentPresentationGeneration == presentationGeneration,
        !Task.isCancelled,
        apiService.isSessionUnchanged(from: sessionSnapshot)
      else { return }
      hasLoadedClients = true
      clientsLoadFailed = false
      consecutiveClientsFailures = 0
      clients = loadedClients
      if let first = loadedClients.first(where: { $0.enabled?.value ?? false })
        ?? loadedClients.first
      {
        selectedClient = first.name
      }
    } catch is CancellationError {
      return
    } catch {
      guard isPresentationActive,
        currentPresentationGeneration == presentationGeneration,
        !Task.isCancelled
      else { return }
      clientsLoadFailed = true
      consecutiveClientsFailures += 1
      reportPollingFailureIfNeeded(
        &consecutiveClientsFailures,
        message: "下载器列表加载失败，正在自动重试。"
      )
      Logger.error("Error fetching clients: \(error)")
    }
  }

  func loadDownloads() async {
    let currentPresentationGeneration = presentationGeneration
    guard isPresentationActive, !Task.isCancelled else { return }
    guard apiService.canAccess(.manage) else {
      clearForRestrictedUser()
      return
    }
    guard !downloadsPermissionDenied else { return }
    await loadClientsIfNeeded()
    guard isPresentationActive,
      currentPresentationGeneration == presentationGeneration,
      !Task.isCancelled
    else { return }
    downloadLoadGeneration += 1
    let currentGeneration = downloadLoadGeneration
    let clientName = selectedClient
    guard !clientName.isEmpty else { return }
    do {
      var newDownloads = try await apiService.fetchDownloading(clientName: clientName)
      guard isPresentationActive,
        currentPresentationGeneration == presentationGeneration,
        !Task.isCancelled,
        selectedClient == clientName,
        currentGeneration == downloadLoadGeneration
      else {
        return
      }

      if !apiService.canRequestSuperUserEndpoints {
        if let userName = apiService.currentUser?.user_name {
          newDownloads = newDownloads.filter {
            $0.userid == userName || $0.username == userName
          }
        } else {
          newDownloads = []
        }
      }

      let newDownloadIds = Set(newDownloads.map { $0.id })
      let existingDownloadsById = Dictionary(uniqueKeysWithValues: downloads.map { ($0.id, $0) })

      // 1. 更新现有下载项（通过对象自身的 @Published 属性，不直接修改数组）
      for newDownload in newDownloads {
        existingDownloadsById[newDownload.id]?.update(with: newDownload)
      }

      // 2. 仅在有项目添加或删除时才修改数组
      let hasRemovals = downloads.contains { !newDownloadIds.contains($0.id) }
      let newItems = newDownloads.filter { existingDownloadsById[$0.id] == nil }

      if hasRemovals || !newItems.isEmpty {
        downloads.removeAll { !newDownloadIds.contains($0.id) }
        for newDownload in newItems.reversed() {
          downloads.insert(newDownload, at: 0)
        }
      }
      if loadedClient != clientName {
        loadedClient = clientName
      }
      downloadsLoadFailedClient = nil
      consecutiveDownloadsFailures = 0
    } catch is CancellationError {
      return
    } catch {
      if Self.supportsDownloadPermissionState(
        backendVersion: apiService.settings?.BACKEND_VERSION
      ), Self.isDownloadPermissionDenied(error) {
        guard isPresentationActive,
          currentPresentationGeneration == presentationGeneration,
          !Task.isCancelled,
          selectedClient == clientName,
          currentGeneration == downloadLoadGeneration
        else { return }
        downloadsPermissionDenied = true
        downloadLoadGeneration += 1
        downloadsLoadFailedClient = nil
        consecutiveDownloadsFailures = 0
        downloads = []
        loadedClient = ""
        return
      }
      // 和成功路径同一套校验：切换下载器或有更新的请求后，旧请求的失败既不显示到当前下载器上，
      // 也不计入连续失败次数。
      guard isPresentationActive,
        currentPresentationGeneration == presentationGeneration,
        !Task.isCancelled,
        selectedClient == clientName,
        currentGeneration == downloadLoadGeneration
      else { return }
      downloadsLoadFailedClient = clientName
      consecutiveDownloadsFailures += 1
      reportPollingFailureIfNeeded(
        &consecutiveDownloadsFailures,
        message: "下载任务刷新失败，正在自动重试。"
      )
      Logger.error("Error loading downloads: \(error)")
    }
  }

  private func clearForRestrictedUser() {
    downloadLoadGeneration += 1
    hasLoadedClients = false
    clientsLoadFailed = false
    downloadsPermissionDenied = false
    downloadsLoadFailedClient = nil
    clients = []
    selectedClient = ""
    downloads = []
    loadedClient = ""
  }

  private static func isDownloadPermissionDenied(_ error: Error) -> Bool {
    guard let apiError = error as? APIError else { return false }
    switch apiError {
    case .authenticationChallenge(let statusCode, _):
      return statusCode == 403
    case .serverMessage(let message):
      return APIService.httpStatusCode(fromServerMessage: message) == 403
    default:
      return false
    }
  }

  private func reportPollingFailureIfNeeded(
    _ consecutiveFailures: inout Int,
    message: String
  ) {
    guard consecutiveFailures > Self.pollingFailureNotificationThreshold else { return }
    consecutiveFailures = 0
    errorMessage = message
  }

  func stopDownload(clientName: String, hash: String) async -> Bool {
    guard apiService.canAccess(.manage) else { return false }
    guard canOperateDownloads, loadedClient == clientName else { return false }
    do {
      let (success, message) = try await apiService.stopDownload(
        clientName: clientName, hash: hash)
      guard canOperateDownloads, loadedClient == clientName else { return false }
      if !success {
        errorMessage = message ?? "暂停下载失败，请稍后重试。"
        Logger.error("Failed to stop download: \(message ?? "Unknown error")")
      }
      return success
    } catch is CancellationError {
      return false
    } catch {
      errorMessage = "暂停下载失败，请稍后重试。"
      Logger.error("Error stopping download: \(error)")
      return false
    }
  }

  func startDownload(clientName: String, hash: String) async -> Bool {
    guard apiService.canAccess(.manage) else { return false }
    guard canOperateDownloads, loadedClient == clientName else { return false }
    do {
      let (success, message) = try await apiService.startDownload(
        clientName: clientName, hash: hash)
      guard canOperateDownloads, loadedClient == clientName else { return false }
      if !success {
        errorMessage = message ?? "启动下载失败，请稍后重试。"
        Logger.error("Failed to start download: \(message ?? "Unknown error")")
      }
      return success
    } catch is CancellationError {
      return false
    } catch {
      errorMessage = "启动下载失败，请稍后重试。"
      Logger.error("Error starting download: \(error)")
      return false
    }
  }

  @MainActor
  func deleteDownload(clientName: String, hash: String) async {
    guard apiService.canAccess(.manage) else { return }
    guard canOperateDownloads, loadedClient == clientName else { return }
    do {
      let (success, message) = try await apiService.deleteDownload(
        clientName: clientName, hash: hash)
      guard canOperateDownloads, loadedClient == clientName else { return }

      if success, let index = downloads.firstIndex(where: { $0.hash == hash }) {
        downloads.remove(at: index)
      } else {
        errorMessage = message ?? "删除下载失败，请稍后重试。"
        Logger.error("Failed to delete download: \(message ?? "Unknown error")")
      }
    } catch is CancellationError {
      return
    } catch {
      errorMessage = "删除下载失败，请稍后重试。"
      Logger.error("Error deleting download: \(error)")
    }
  }
}
