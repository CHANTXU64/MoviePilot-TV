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
  @Published private(set) var sessionUIIdentity: String

  private let apiService: APIService
  private let memoryOptimizationPolicy: MemoryOptimizationPolicy
  private var cancellables = Set<AnyCancellable>()
  private var didPrepareStartup = false
  private var backendVersionCheckKey: BackendVersionCheckKey?
  private var lastAccountPermissionWarningKey: AccountPermissionWarningKey?
  private var shouldEvaluateMemoryOptimizationAfterSessionChange = false
  private var memoryOptimizationSessionKey: BackendVersionCheckKey?

  init(
    apiService: APIService = .shared,
    memoryOptimizationPolicy: MemoryOptimizationPolicy = .shared
  ) {
    self.apiService = apiService
    self.memoryOptimizationPolicy = memoryOptimizationPolicy
    // 初始状态
    isLoggedIn = apiService.isLoggedIn
    currentUser = apiService.currentUser
    sessionUIIdentity = apiService.uiIdentity
    memoryOptimizationSessionKey = currentBackendVersionCheckKey()
    updateAccountPermissionWarning(for: currentUser)

    // 单一会话权威：登录、登出、换账号、切服与权限变化都从同一原子状态发布。
    apiService.$session
      .sink { [weak self] session in
        guard let self else { return }
        self.isLoggedIn = session.token != nil
        self.currentUser = session.currentUser
        self.sessionUIIdentity = session.uiIdentity
        let profileIdentity = session.currentUser.map {
          Self.accountProfileIdentity(
            for: $0,
            baseURL: session.baseURL,
            profileKey: session.profileKey
          )
        }
        self.updateAccountPermissionWarning(
          for: session.currentUser,
          profileIdentity: profileIdentity
        )
        let sessionKey = self.currentBackendVersionCheckKey()
        if sessionKey != self.memoryOptimizationSessionKey {
          self.memoryOptimizationSessionKey = sessionKey
          self.memoryOptimizationPolicy.invalidateAutomaticDecision()
          self.shouldEvaluateMemoryOptimizationAfterSessionChange = true
        }
        if session.token == nil {
          self.resetBackendVersionCheck()
        }
        if session.token != nil, self.didPrepareStartup, !self.isPreparingStartupSession {
          let shouldEvaluateMemoryOptimization =
            self.shouldEvaluateMemoryOptimizationAfterSessionChange
          self.shouldEvaluateMemoryOptimizationAfterSessionChange = false
          Task { [weak self] in
            guard let self else { return }
            await self.loadGlobalSettings(
              checkBackendVersion: true,
              evaluateMemoryOptimization: shouldEvaluateMemoryOptimization
            )
          }
        }
      }
      .store(in: &cancellables)

    // 监听应用进入前台 -> 如果已登录则刷新设置
    NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
      .sink { [weak self] _ in
        guard let self, self.isLoggedIn, self.didPrepareStartup,
          !self.isPreparingStartupSession
        else { return }
        Task { [weak self] in
          await self?.loadGlobalSettings(
            checkBackendVersion: false,
            evaluateMemoryOptimization: true
          )
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
    if canAccess(.discovery) || canAccess(.search) {
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
      let hadRestoredCurrentUser = apiService.currentUser != nil
      let refreshResult = await apiService.refreshStoredSessionAfterAppUpdateIfNeeded()
      if refreshResult != .refreshed,
        apiService.isLoggedIn,
        hadRestoredCurrentUser || apiService.currentUser == nil
      {
        await apiService.refreshCurrentUserForStartup()
      }
      isPreparingStartupSession = false
      isLoggedIn = apiService.isLoggedIn
    }

    if isLoggedIn {
      await loadGlobalSettings(
        checkBackendVersion: true,
        evaluateMemoryOptimization: true
      )
    }
  }

  private func loadGlobalSettings(
    checkBackendVersion: Bool,
    evaluateMemoryOptimization: Bool = false
  ) async {
    if evaluateMemoryOptimization {
      shouldEvaluateMemoryOptimizationAfterSessionChange = false
    }
    let checkKey = currentBackendVersionCheckKey()
    if checkBackendVersion, backendVersionCheckKey != checkKey {
      backendVersionWarning = nil
    }

    do {
      let settings = try await apiService.fetchSettings()
      let sessionIsCurrent = currentBackendVersionCheckKey() == checkKey
      if checkBackendVersion, backendVersionCheckKey != checkKey, sessionIsCurrent {
        backendVersionCheckKey = checkKey
        backendVersionWarning = Self.backendVersionWarning(for: settings.BACKEND_VERSION)
      }
      if evaluateMemoryOptimization, sessionIsCurrent {
        let sessionSnapshot = apiService.sessionSnapshot()
        let imageCacheAvailable = apiService.useImageCache
        memoryOptimizationPolicy.evaluateAutomatically(
          sessionSnapshot: sessionSnapshot,
          settingsLoaded: true,
          imageCacheAvailable: imageCacheAvailable
        )
      }
    } catch is CancellationError {
      return
    } catch {
      let sessionIsCurrent = currentBackendVersionCheckKey() == checkKey
      if checkBackendVersion, backendVersionCheckKey != checkKey, sessionIsCurrent {
        backendVersionCheckKey = checkKey
        backendVersionWarning = BackendVersionWarning(
          backendVersion: nil,
          requiredVersion: AppVersionInfo.compatibleMoviePilotVersion
        )
      }
      if evaluateMemoryOptimization, sessionIsCurrent {
        memoryOptimizationPolicy.evaluateAutomatically(
          sessionSnapshot: apiService.sessionSnapshot(),
          settingsLoaded: false,
          imageCacheAvailable: false
        )
      }
    }
  }

  private func resetBackendVersionCheck() {
    backendVersionCheckKey = nil
    backendVersionWarning = nil
  }

  private func updateAccountPermissionWarning(
    for token: Token?,
    profileIdentity: String? = nil
  ) {
    guard let token else {
      lastAccountPermissionWarningKey = nil
      accountPermissionWarning = nil
      return
    }
    let profileIdentity = profileIdentity
      ?? Self.accountProfileIdentity(
        for: token,
        baseURL: apiService.baseURL,
        profileKey: apiService.profileKey
      )
    guard
      let warning = AccountPermissionWarning.warning(
        for: token,
        profileIdentity: profileIdentity
      )
    else {
      lastAccountPermissionWarningKey = nil
      accountPermissionWarning = nil
      return
    }

    let warningKey = AccountPermissionWarningKey(
      profileIdentity: profileIdentity,
      missingPermissions: warning.missingPermissions
    )
    guard warningKey != lastAccountPermissionWarningKey else { return }
    lastAccountPermissionWarningKey = warningKey
    accountPermissionWarning = warning
  }

  private static func accountProfileIdentity(
    for token: Token,
    baseURL: String,
    profileKey: String?
  ) -> String {
    profileKey ?? "pending:\(baseURL)|name:\(token.user_name)"
  }

  private func currentBackendVersionCheckKey() -> BackendVersionCheckKey {
    BackendVersionCheckKey(
      baseURL: apiService.baseURL,
      token: apiService.token,
      appVersion: AppVersionInfo.currentAppVersion()
    )
  }

  static func backendVersionWarning(for backendVersion: String?) -> BackendVersionWarning? {
    BackendVersionWarning(
      backendVersion: backendVersion,
      requiredVersion: AppVersionInfo.compatibleMoviePilotVersion
    )
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

  static func warning(
    for token: Token,
    profileIdentity: String? = nil
  ) -> AccountPermissionWarning? {
    let missingPermissions = token.missingRecommendedContentPermissions
    guard !missingPermissions.isEmpty else { return nil }
    let missingText = missingPermissions.map(\.displayName).joined(separator: "、")
    let warningIdentity = profileIdentity
      ?? token.user_id.map { "user:\($0)" }
      ?? "name:\(token.user_name)"
    return AccountPermissionWarning(
      id:
        "account-permission-\(warningIdentity)-\(missingPermissions.map(\.rawValue).joined(separator: "-"))",
      title: "账号权限不足",
      message: "当前账号缺少\(missingText)权限。MoviePilot-TV 兼容验证至少要求账号具备探索、搜索和订阅权限；继续使用时部分入口会隐藏，页面布局或焦点可能不完整。",
      missingPermissions: missingPermissions
    )
  }
}

private struct AccountPermissionWarningKey: Equatable {
  let profileIdentity: String
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
