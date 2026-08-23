import Combine
import Foundation
import SwiftUI

@MainActor
class DownloadTaskViewModel: ObservableObject {
  @Published var clients: [DownloaderConf] = []
  @Published var selectedClient: String = ""
  @Published var downloads: [DownloadingInfo] = []
  @Published private(set) var loadedClient: String = ""
  @Published private(set) var clientsLoadFailed = false
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

  init(apiService: APIService = .shared) {
    self.apiService = apiService
  }

  /// 主 Tab 生命周期门禁。generation 让“切走后又快速切回”的旧独立 Task 也无法写回。
  func setPresentationActive(_ isActive: Bool) {
    guard isPresentationActive != isActive else { return }
    isPresentationActive = isActive
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
      print("Error fetching clients: \(error)")
    }
  }

  func loadDownloads() async {
    let currentPresentationGeneration = presentationGeneration
    guard isPresentationActive, !Task.isCancelled else { return }
    guard apiService.canAccess(.manage) else {
      clearForRestrictedUser()
      return
    }
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
      consecutiveDownloadsFailures = 0
    } catch is CancellationError {
      return
    } catch {
      guard isPresentationActive,
        currentPresentationGeneration == presentationGeneration,
        !Task.isCancelled
      else { return }
      consecutiveDownloadsFailures += 1
      reportPollingFailureIfNeeded(
        &consecutiveDownloadsFailures,
        message: "下载任务刷新失败，正在自动重试。"
      )
      print("Error loading downloads: \(error)")
    }
  }

  private func clearForRestrictedUser() {
    downloadLoadGeneration += 1
    hasLoadedClients = false
    clientsLoadFailed = false
    clients = []
    selectedClient = ""
    downloads = []
    loadedClient = ""
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
        print("Failed to stop download: \(message ?? "Unknown error")")
      }
      return success
    } catch is CancellationError {
      return false
    } catch {
      errorMessage = "暂停下载失败，请稍后重试。"
      print("Error stopping download: \(error)")
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
        print("Failed to start download: \(message ?? "Unknown error")")
      }
      return success
    } catch is CancellationError {
      return false
    } catch {
      errorMessage = "启动下载失败，请稍后重试。"
      print("Error starting download: \(error)")
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
        print("Failed to delete download: \(message ?? "Unknown error")")
      }
    } catch is CancellationError {
      return
    } catch {
      errorMessage = "删除下载失败，请稍后重试。"
      print("Error deleting download: \(error)")
    }
  }
}
