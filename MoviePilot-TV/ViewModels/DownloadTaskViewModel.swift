import Combine
import Foundation
import SwiftUI

@MainActor
class DownloadTaskViewModel: ObservableObject {
  @Published var clients: [DownloaderConf] = []
  @Published var selectedClient: String = ""
  @Published var downloads: [DownloadingInfo] = []

  private let apiService = APIService.shared

  func initialLoad() async {
    if clients.isEmpty {
      do {
        clients = try await apiService.fetchDownloadClients()
        if let first = clients.first(where: { $0.enabled?.value ?? false }) ?? clients.first {
          selectedClient = first.name
        }
      } catch {
        print("Error fetching clients: \(error)")
      }
    }
    await loadDownloads()
  }

  func loadDownloads() async {
    guard !selectedClient.isEmpty else { return }
    do {
      let newDownloads = try await apiService.fetchDownloading(clientName: selectedClient)
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
    } catch {
      print("Error loading downloads: \(error)")
    }
  }

  func stopDownload(hash: String) async -> Bool {
    guard !selectedClient.isEmpty else { return false }
    do {
      let (success, message) = try await apiService.stopDownload(
        clientName: selectedClient, hash: hash)
      if !success {
        print("Failed to stop download: \(message ?? "Unknown error")")
      }
      return success
    } catch {
      print("Error stopping download: \(error)")
      return false
    }
  }

  func startDownload(hash: String) async -> Bool {
    guard !selectedClient.isEmpty else { return false }
    do {
      let (success, message) = try await apiService.startDownload(
        clientName: selectedClient, hash: hash)
      if !success {
        print("Failed to start download: \(message ?? "Unknown error")")
      }
      return success
    } catch {
      print("Error starting download: \(error)")
      return false
    }
  }

  @MainActor
  func deleteDownload(hash: String) async {
    guard !selectedClient.isEmpty else { return }
    do {
      let (success, message) = try await apiService.deleteDownload(
        clientName: selectedClient, hash: hash)
      if success, let index = downloads.firstIndex(where: { $0.hash == hash }) {
        downloads.remove(at: index)
      } else {
        print("Failed to delete download: \(message ?? "Unknown error")")
      }
    } catch {
      print("Error deleting download: \(error)")
    }
  }
}
