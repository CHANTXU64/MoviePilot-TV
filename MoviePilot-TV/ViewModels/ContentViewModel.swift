import Combine
import Foundation
import SwiftUI

@MainActor
class ContentViewModel: ObservableObject {
  enum Tab: Int, Equatable, Hashable {
    case home = 0
    case recommend = 1
    case explore = 2
    case search = 3
    case status = 4
    case system = 5
  }

  @Published var isLoggedIn = false
  @Published var isPreparingStartupSession = false
  @Published var backendVersionWarning: BackendVersionWarning?
  @Published var accountPermissionWarning: AccountPermissionWarning?
  @Published private(set) var currentUser: Token?

  private let apiService = APIService.shared
  private var cancellables = Set<AnyCancellable>()
  private var didPrepareStartup = false
  private var backendVersionCheckKey: BackendVersionCheckKey?
  private var lastAccountPermissionWarningKey: AccountPermissionWarningKey?

  init() {
    // 初始状态
    isLoggedIn = apiService.isLoggedIn
    currentUser = apiService.currentUser

    // 监听令牌变化 -> 在登录或令牌更新时触发设置获取
    apiService.$token
      .receive(on: RunLoop.main)
      .sink { [weak self] token in
        guard let self else { return }
        self.isLoggedIn = (token != nil)
        if token == nil {
          self.resetBackendVersionCheck()
        }
        if token != nil {
          Task { [weak self] in
            guard let self else { return }
            await self.loadGlobalSettings(checkBackendVersion: self.didPrepareStartup)
          }
        }
      }
      .store(in: &cancellables)

    apiService.$currentUser
      .dropFirst()
      .receive(on: RunLoop.main)
      .sink { [weak self] user in
        guard let self else { return }
        self.currentUser = user
        self.updateAccountPermissionWarning(for: user)
      }
      .store(in: &cancellables)

    apiService.$baseURL
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in
        self?.resetBackendVersionCheck()
      }
      .store(in: &cancellables)

    // 监听应用进入前台 -> 如果已登录则刷新设置
    NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
      .sink { [weak self] _ in
        guard let self = self, self.isLoggedIn else { return }
        Task { [weak self] in
          await self?.loadGlobalSettings(checkBackendVersion: false)
        }
      }
      .store(in: &cancellables)
  }

  func logout() {
    apiService.logout()
  }

  var visibleTabs: [Tab] {
    Self.visibleTabs(for: currentUser)
  }

  static func visibleTabs(for token: Token?) -> [Tab] {
    var tabs: [Tab] = [.home]
    let canAccess: (UserPermissionKey) -> Bool = { permission in
      token?.canAccess(permission) ?? false
    }

    if canAccess(.discovery) {
      tabs.append(.recommend)
      tabs.append(.explore)
    }
    if canAccess(.search) {
      tabs.append(.search)
    }
    if canAccess(.manage) {
      tabs.append(.status)
    }
    tabs.append(.system)
    return tabs
  }

  static func resolvedSelectedTab(_ selectedTab: Tab, visibleTabs: [Tab]) -> Tab {
    visibleTabs.contains(selectedTab) ? selectedTab : (visibleTabs.first ?? .home)
  }

  func prepareStartupIfNeeded() async {
    guard !didPrepareStartup else { return }
    didPrepareStartup = true

    if apiService.isLoggedIn {
      isPreparingStartupSession = true
      _ = await apiService.refreshStoredSessionAfterAppUpdateIfNeeded()
      isPreparingStartupSession = false
      isLoggedIn = apiService.isLoggedIn
    }

    if isLoggedIn {
      await loadGlobalSettings(checkBackendVersion: true)
    }
  }

  private func loadGlobalSettings(checkBackendVersion: Bool) async {
    let checkKey = currentBackendVersionCheckKey()
    if checkBackendVersion, backendVersionCheckKey != checkKey {
      backendVersionWarning = nil
    }

    do {
      let settings = try await apiService.fetchSettings()
      guard checkBackendVersion, backendVersionCheckKey != checkKey else { return }
      guard currentBackendVersionCheckKey() == checkKey else { return }
      backendVersionCheckKey = checkKey
      backendVersionWarning = Self.backendVersionWarning(for: settings.BACKEND_VERSION)
    } catch {
      guard checkBackendVersion, backendVersionCheckKey != checkKey else { return }
      guard currentBackendVersionCheckKey() == checkKey else { return }
      backendVersionCheckKey = checkKey
      backendVersionWarning = BackendVersionWarning(
        backendVersion: nil,
        requiredVersion: AppVersionInfo.compatibleMoviePilotVersion
      )
    }
  }

  private func resetBackendVersionCheck() {
    backendVersionCheckKey = nil
    backendVersionWarning = nil
  }

  private func updateAccountPermissionWarning(for token: Token?) {
    guard let token else {
      lastAccountPermissionWarningKey = nil
      accountPermissionWarning = nil
      return
    }
    guard let warning = AccountPermissionWarning.warning(for: token) else {
      lastAccountPermissionWarningKey = nil
      accountPermissionWarning = nil
      return
    }

    let warningKey = AccountPermissionWarningKey(
      baseURL: apiService.baseURL,
      userName: token.user_name,
      missingPermissions: warning.missingPermissions
    )
    guard warningKey != lastAccountPermissionWarningKey else { return }
    lastAccountPermissionWarningKey = warningKey
    accountPermissionWarning = warning
  }

  private func currentBackendVersionCheckKey() -> BackendVersionCheckKey {
    BackendVersionCheckKey(
      baseURL: apiService.baseURL,
      token: apiService.token,
      appVersion: AppVersionInfo.currentAppVersion()
    )
  }

  private static func backendVersionWarning(for backendVersion: String?) -> BackendVersionWarning? {
    switch AppVersionInfo.supportsMoviePilotVersion(backendVersion) {
    case .some(true):
      return nil
    case .some(false), .none:
      return BackendVersionWarning(
        backendVersion: backendVersion,
        requiredVersion: AppVersionInfo.compatibleMoviePilotVersion
      )
    }
  }
}

private struct BackendVersionCheckKey: Equatable {
  let baseURL: String
  let token: String?
  let appVersion: String
}

struct AccountPermissionWarning: Identifiable, Equatable {
  let id: String
  let title: String
  let message: String
  let missingPermissions: [UserPermissionKey]

  static func warning(for token: Token) -> AccountPermissionWarning? {
    let missingPermissions = token.missingRecommendedContentPermissions
    guard !missingPermissions.isEmpty else { return nil }
    let missingText = missingPermissions.map(\.displayName).joined(separator: "、")
    return AccountPermissionWarning(
      id: "account-permission-\(token.user_name)-\(missingPermissions.map(\.rawValue).joined(separator: "-"))",
      title: "账号权限不足",
      message: "当前账号缺少\(missingText)权限。MoviePilot-TV 兼容验证至少要求账号具备探索、搜索和订阅权限；继续使用时部分入口会隐藏，页面布局或焦点可能不完整。",
      missingPermissions: missingPermissions
    )
  }
}

private struct AccountPermissionWarningKey: Equatable {
  let baseURL: String
  let userName: String
  let missingPermissions: [UserPermissionKey]
}

private extension UserPermissionKey {
  var displayName: String {
    switch self {
    case .discovery:
      return "探索"
    case .search:
      return "搜索"
    case .subscribe:
      return "订阅"
    case .manage:
      return "管理"
    }
  }
}
