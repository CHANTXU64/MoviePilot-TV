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
      downloads = try await apiService.fetchDownloading(clientName: selectedClient)
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
      if success {
        downloads.removeAll { $0.hash == hash }
      } else {
        print("Failed to delete download: \(message ?? "Unknown error")")
      }
    } catch {
      print("Error deleting download: \(error)")
    }
  }
}
