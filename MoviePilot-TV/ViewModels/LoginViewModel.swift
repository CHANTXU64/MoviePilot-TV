import Foundation
import SwiftUI
import Combine

@MainActor
class LoginViewModel: ObservableObject {
  @Published var serverURL: String = ""
  @Published var username: String = ""
  @Published var password: String = ""
  @Published var isLoading = false
  @Published var errorMessage: String?

  private let apiService = APIService.shared

  init() {
    if serverURL.isEmpty {
      serverURL = apiService.baseURL
    }
  }

  func login() async -> Bool {
    isLoading = true
    errorMessage = nil

    apiService.baseURL = serverURL

    do {
      _ = try await apiService.login(username: username, password: password)
      isLoading = false
      return true
    } catch {
      isLoading = false
      errorMessage = "登录失败: \(error.localizedDescription)"
      return false
    }
  }
}
