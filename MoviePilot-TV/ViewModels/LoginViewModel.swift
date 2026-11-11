import Foundation
import SwiftUI
import Combine

@MainActor
class LoginViewModel: ObservableObject {
  // 显式非隔离析构，避开 tvOS 18 的隔离析构回部署崩溃。
  nonisolated deinit {}

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

    #if DEBUG
    // UI 预览：场景可在登录草稿之外再请求自动提交一次，用于展示「提交中 / 登录失败」。
    // 延迟到首帧渲染后再发请求，确保 LoginView 的 errorMessage onChange 已经挂上。
    if UIPreviewMode.isEnabled(),
      UIPreviewBackend.shared.context(UIPreviewContextKey.loginAutoSubmit) == "1"
    {
      Task { [weak self] in
        try? await Task.sleep(for: .seconds(0.4))
        guard let self else { return }
        _ = await self.login()
      }
    }
    #endif
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
