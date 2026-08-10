import Combine
import Foundation
import SwiftUI

@MainActor
class DownloadTaskViewModel: ObservableObject {
  @Published var clients: [DownloaderConf] = []
  @Published var selectedClient: String = ""
  @Published var downloads: [DownloadingInfo] = []
  @Published private(set) var loadedClient: String = ""

  var canOperateDownloads: Bool {
    !loadedClient.isEmpty && loadedClient == selectedClient
  }

  private let apiService: APIService
  private var downloadLoadGeneration = 0

  init(apiService: APIService = .shared) {
    self.apiService = apiService
  }

  func initialLoad() async {
    guard apiService.canAccess(.manage) else {
      clearForRestrictedUser()
      return
    }
    let sessionSnapshot = apiService.sessionSnapshot()
    if clients.isEmpty {
      do {
        let loadedClients = try await apiService.fetchDownloadClients()
        guard apiService.isSessionUnchanged(from: sessionSnapshot) else { return }
        clients = loadedClients
        if let first = loadedClients.first(where: { $0.enabled?.value ?? false })
          ?? loadedClients.first
        {
          selectedClient = first.name
        }
      } catch is CancellationError {
        return
      } catch {
        print("Error fetching clients: \(error)")
      }
    }
    guard apiService.isSessionUnchanged(from: sessionSnapshot) else { return }
    await loadDownloads()
  }

  func loadDownloads() async {
    guard apiService.canAccess(.manage) else {
      clearForRestrictedUser()
      return
    }
    downloadLoadGeneration += 1
    let currentGeneration = downloadLoadGeneration
    let clientName = selectedClient
    guard !clientName.isEmpty else { return }
    do {
      let newDownloads = try await apiService.fetchDownloading(clientName: clientName)
      guard selectedClient == clientName,
        currentGeneration == downloadLoadGeneration
      else {
        return
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
    } catch is CancellationError {
      return
    } catch {
      print("Error loading downloads: \(error)")
    }
  }

  private func clearForRestrictedUser() {
    downloadLoadGeneration += 1
    clients = []
    selectedClient = ""
    downloads = []
    loadedClient = ""
  }

  func stopDownload(clientName: String, hash: String) async -> Bool {
    guard apiService.canAccess(.manage) else { return false }
    guard canOperateDownloads, loadedClient == clientName else { return false }
    do {
      let (success, message) = try await apiService.stopDownload(
        clientName: clientName, hash: hash)
      guard canOperateDownloads, loadedClient == clientName else { return false }
      if !success {
        print("Failed to stop download: \(message ?? "Unknown error")")
      }
      return success
    } catch is CancellationError {
      return false
    } catch {
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
        print("Failed to start download: \(message ?? "Unknown error")")
      }
      return success
    } catch is CancellationError {
      return false
    } catch {
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
        print("Failed to delete download: \(message ?? "Unknown error")")
      }
    } catch is CancellationError {
      return
    } catch {
      print("Error deleting download: \(error)")
    }
  }
}
