import Foundation
import SwiftUI
import Combine

@MainActor
class LoginViewModel: ObservableObject {
  @Published var serverURL: String = ""
  @Published var username: String = ""
  @Published var password: String = ""
  @Published private(set) var showsMFAUnsupportedNotice = false
  @Published var isLoading = false
  @Published var errorMessage: String?

  private let apiService: APIService

  init(apiService: APIService = .shared) {
    self.apiService = apiService
    if let draft = apiService.loginDraft {
      serverURL = draft.serverURL
      username = draft.username
      password = draft.password ?? ""
      showsMFAUnsupportedNotice = draft.reason == .mfaUnsupported
    } else {
      serverURL = apiService.baseURL
    }
  }

  func login() async -> Bool {
    guard !isLoading else { return false }
    isLoading = true
    errorMessage = nil
    defer { isLoading = false }
    apiService.updateLoginDraft(
      serverURL: serverURL,
      username: username,
      password: password
    )

    do {
      _ = try await apiService.login(
        username: username,
        password: password,
        serverURL: serverURL
      )
      showsMFAUnsupportedNotice = false
      return true
    } catch APIError.mfaUnsupported {
      apiService.updateLoginDraft(
        serverURL: serverURL,
        username: username,
        password: password,
        reason: .mfaUnsupported
      )
      showsMFAUnsupportedNotice = true
      errorMessage = "当前账号已开启 MFA，TV 端暂不支持，请关闭 MFA 后重试"
      return false
    } catch APIError.credentialsRejected {
      apiService.updateLoginDraft(
        serverURL: serverURL,
        username: username,
        password: password,
        reason: .credentialsRejected
      )
      showsMFAUnsupportedNotice = false
      errorMessage = "用户名或密码错误"
      return false
    } catch {
      errorMessage = "登录失败: \(error.localizedDescription)"
      return false
    }
  }
}
