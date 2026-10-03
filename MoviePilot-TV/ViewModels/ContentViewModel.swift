import Combine
import Foundation
import SwiftUI

@MainActor
class ContentViewModel: ObservableObject {
  // 显式非隔离析构，避开 tvOS 18 的隔离析构回部署崩溃。
  nonisolated deinit {}

  private static let backendVersionAcknowledgementsKey = "acknowledgedBackendVersionWarnings"

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
  @Published private(set) var pendingBackendVersionWarning: BackendVersionWarningPresentation?
  @Published var accountPermissionWarning: AccountPermissionWarning?
  @Published private(set) var currentUser: Token?
  @Published private(set) var sessionUIIdentity: String
  @Published private(set) var topShelfRoute: PendingTopShelfRoute?
  @Published private(set) var isOpeningTopShelf = false
  @Published private(set) var recommendNavigation: ImageNavigationCoordinator
  @Published private(set) var exploreNavigation: ImageNavigationCoordinator
  @Published var selectedTab: Tab = .home

  private let apiService: APIService
  private let warningDefaults: UserDefaults
  private let appVersion: String
  private let compatibilityRegistry: BackendCompatibilityRegistry
  private var cancellables = Set<AnyCancellable>()
  private var didPrepareStartup = false
  private var isRefreshingStartupSession = false
  private var backendVersionCheckKey: BackendVersionCheckKey?
  private var backendVersionWarningBaseURL: String?
  private var lastAccountPermissionWarningKey: AccountPermissionWarningKey?

  init(
    apiService: APIService = .shared,
    warningDefaults: UserDefaults = .standard,
    appVersion: String = AppVersionInfo.currentAppVersion(),
    compatibilityRegistry: BackendCompatibilityRegistry = .current
  ) {
    self.apiService = apiService
    self.warningDefaults = warningDefaults
    self.appVersion = appVersion
    self.compatibilityRegistry = compatibilityRegistry
    recommendNavigation = ImageNavigationCoordinator(apiService: apiService)
    exploreNavigation = ImageNavigationCoordinator(apiService: apiService)
    // 初始状态
    isLoggedIn = apiService.isLoggedIn
    // 已有持久化会话时，首帧先挡住主界面，等待权威用户信息恢复完成。
    isPreparingStartupSession = apiService.isLoggedIn
    currentUser = apiService.currentUser
    sessionUIIdentity = apiService.uiIdentity
    updateAccountPermissionWarning(for: currentUser)

    // 单一会话权威：登录、登出、换账号、切服与权限变化都从同一原子状态发布。
    apiService.$session
      .sink { [weak self] session in
        guard let self else { return }
        let sessionChanged = self.sessionUIIdentity != session.uiIdentity
        self.isLoggedIn = session.token != nil
        self.currentUser = session.currentUser
        self.sessionUIIdentity = session.uiIdentity
        if let route = self.topShelfRoute,
          route.payload.sessionID != session.imageNamespace
            || session.token == nil
            || (!self.isPreparingStartupSession && session.currentUser?.canAccess(.discovery) != true)
        {
          self.topShelfRoute = nil
          self.isOpeningTopShelf = false
        }
        if sessionChanged {
          self.recommendNavigation.retire()
          self.exploreNavigation.retire()
          self.recommendNavigation = ImageNavigationCoordinator(apiService: self.apiService)
          self.exploreNavigation = ImageNavigationCoordinator(apiService: self.apiService)
        }
        self.selectedTab = Self.resolvedSelectedTab(
          sessionChanged ? (self.topShelfRoute?.targetTab ?? .home) : self.selectedTab,
          visibleTabs: self.visibleTabs
        )
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
        if session.token == nil {
          self.resetBackendVersionCheck()
        }
        if session.token != nil, self.didPrepareStartup, !self.isRefreshingStartupSession {
          Task { [weak self] in
            guard let self else { return }
            await self.loadGlobalSettings(checkBackendVersion: true)
          }
        }
      }
      .store(in: &cancellables)

    // 监听应用进入前台 -> 如果已登录则刷新设置
    NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
      .sink { [weak self] _ in
        guard let self, self.isLoggedIn, self.didPrepareStartup,
          !self.isRefreshingStartupSession
        else { return }
        Task { [weak self] in
          await self?.loadGlobalSettings(checkBackendVersion: false)
        }
      }
      .store(in: &cancellables)
  }

  func logout() {
    apiService.logout()
  }

  var backendVersionWarningPresentation: BackendVersionWarningPresentation? {
    backendVersionWarning.map {
      BackendVersionWarningPresentation(warning: $0, baseURL: backendVersionWarningBaseURL)
    }
  }

  func acknowledgeBackendVersionWarning(_ presentation: BackendVersionWarningPresentation) {
    if let baseURL = presentation.baseURL {
      var acknowledgements = backendVersionAcknowledgements()
      var warningIDs = Set(acknowledgements[baseURL] ?? [])
      warningIDs.insert(presentation.warning.id)
      acknowledgements[baseURL] = warningIDs.sorted()
      warningDefaults.set(acknowledgements, forKey: Self.backendVersionAcknowledgementsKey)
    }
    if backendVersionWarning == presentation.warning,
      backendVersionWarningBaseURL == presentation.baseURL
    {
      clearPresentedBackendVersionWarning()
    }
  }

  private func clearPresentedBackendVersionWarning() {
    backendVersionWarning = nil
    backendVersionWarningBaseURL = nil
  }

  func presentPendingBackendVersionWarning() {
    guard backendVersionWarning == nil, let pending = pendingBackendVersionWarning else { return }
    pendingBackendVersionWarning = nil
    guard let baseURL = pending.baseURL,
      currentBackendVersionCheckKey().baseURL == baseURL,
      isLoggedIn
    else { return }
    presentBackendVersionWarning(pending.warning, baseURL: baseURL)
  }

  var canPresentContent: Bool {
    isLoggedIn && (!isPreparingStartupSession || topShelfRoute.map {
      navigation(for: $0.targetTab).topEntryID == $0.id
    } == true)
  }

  func disposition(for route: PendingTopShelfRoute) -> TopShelfNavigationDisposition {
    TopShelfNavigationPolicy.disposition(
      for: route,
      isPreparingStartupSession: isPreparingStartupSession,
      isLoggedIn: isLoggedIn,
      currentSessionID: apiService.session.imageNamespace,
      visibleTabs: visibleTabs
    )
  }

  /// 有效外部入口先遮住根页并取消旧弹窗；UIKit 关闭呈现后再交接导航。
  func prepareTopShelfRoute(_ route: PendingTopShelfRoute) {
    guard disposition(for: route) != .discard, topShelfRoute?.id != route.id else { return }
    topShelfRoute = route
    isOpeningTopShelf = true
    clearBackendVersionWarning()
    accountPermissionWarning = nil
    NotificationCenter.default.post(
      name: .imageNavigationPresentationWillReset, object: apiService)
  }

  /// 先准备目标栈，再发布 Tab 选择；目标 View 首次挂载时路径已经包含详情。
  func acceptTopShelfRoute(_ route: PendingTopShelfRoute) -> TopShelfNavigationDisposition {
    let disposition = disposition(for: route)
    if disposition == .open || disposition == .preview {
      prepareTopShelfRoute(route)
      navigation(for: route.targetTab).openExternal(
        route.navigationEntry, startsMediaLoad: !isPreparingStartupSession)
      selectedTab = route.targetTab
    } else if disposition == .discard, topShelfRoute?.id == route.id {
      cancelTopShelfOpening()
    }
    return disposition
  }

  func navigation(for tab: Tab) -> ImageNavigationCoordinator {
    precondition(tab == .recommend || tab == .explore)
    return tab == .explore ? exploreNavigation : recommendNavigation
  }

  func finishTopShelfOpening(id: UUID) {
    guard topShelfRoute?.id == id else { return }
    isOpeningTopShelf = false
  }

  func cancelTopShelfOpening() {
    if let route = topShelfRoute {
      let navigation = navigation(for: route.targetTab)
      if navigation.topEntryID == route.id { navigation.resetDetailHistory() }
    }
    endTopShelfPresentation()
  }

  func endTopShelfPresentation(id: UUID? = nil) {
    if let id, topShelfRoute?.id != id { return }
    topShelfRoute = nil
    isOpeningTopShelf = false
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
      // 有持久化会话时先占住启动门，避免旧权限状态先构造主界面。
      isRefreshingStartupSession = true
      isPreparingStartupSession = true
      await apiService.refreshCurrentUserForStartup()
      isPreparingStartupSession = false
      isRefreshingStartupSession = false
      isLoggedIn = apiService.isLoggedIn
      if let route = topShelfRoute, disposition(for: route) == .discard {
        cancelTopShelfOpening()
      }
    } else {
      isPreparingStartupSession = false
    }

    if isLoggedIn {
      await loadGlobalSettings(checkBackendVersion: true)
    }
  }

  private func loadGlobalSettings(checkBackendVersion: Bool) async {
    let checkKey = currentBackendVersionCheckKey()
    if checkBackendVersion, backendVersionCheckKey != checkKey,
      backendVersionWarningBaseURL != checkKey.baseURL
    {
      clearBackendVersionWarning()
    }

    do {
      let settings = try await apiService.fetchSettings()
      guard currentBackendVersionCheckKey() == checkKey else { return }
      // 每次刷新重新评估精确版本；同一服务器、同一后端版本的已确认提示由持久化记录去重。
      presentBackendVersionWarning(
        Self.backendVersionWarning(for: settings.BACKEND_VERSION, registry: compatibilityRegistry),
        baseURL: checkKey.baseURL
      )
      if checkBackendVersion {
        backendVersionCheckKey = checkKey
      }
    } catch is CancellationError {
      return
    } catch {
      let sessionIsCurrent = currentBackendVersionCheckKey() == checkKey
      guard checkBackendVersion, backendVersionCheckKey != checkKey else { return }
      guard sessionIsCurrent else { return }
      presentBackendVersionWarning(
        BackendVersionWarning(
          backendVersion: nil,
          registry: compatibilityRegistry
        ),
        baseURL: checkKey.baseURL
      )
    }
  }

  private func resetBackendVersionCheck() {
    backendVersionCheckKey = nil
    clearBackendVersionWarning()
  }

  private func presentBackendVersionWarning(_ warning: BackendVersionWarning?, baseURL: String) {
    guard let warning,
      backendVersionAcknowledgements()[baseURL]?.contains(warning.id) != true
    else {
      clearBackendVersionWarning()
      return
    }
    let presentation = BackendVersionWarningPresentation(warning: warning, baseURL: baseURL)
    if let displayed = backendVersionWarning,
      displayed != warning || backendVersionWarningBaseURL != baseURL
    {
      pendingBackendVersionWarning = presentation
      return
    }
    if pendingBackendVersionWarning != nil, backendVersionWarning == nil {
      pendingBackendVersionWarning = presentation
      return
    }
    pendingBackendVersionWarning = nil
    backendVersionWarningBaseURL = baseURL
    backendVersionWarning = warning
  }

  private func clearBackendVersionWarning() {
    clearPresentedBackendVersionWarning()
    pendingBackendVersionWarning = nil
  }

  private func backendVersionAcknowledgements() -> [String: [String]] {
    warningDefaults.dictionary(forKey: Self.backendVersionAcknowledgementsKey) as? [String: [String]]
      ?? [:]
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
    backendVersionCheckKey(for: apiService.session)
  }

  private func backendVersionCheckKey(
    for session: APIServiceSessionState
  ) -> BackendVersionCheckKey {
    BackendVersionCheckKey(
      baseURL: session.baseURL,
      token: session.token,
      appVersion: appVersion
    )
  }

  static func backendVersionWarning(
    for backendVersion: String?,
    registry: BackendCompatibilityRegistry = .current
  ) -> BackendVersionWarning? {
    BackendVersionWarning(
      backendVersion: backendVersion,
      registry: registry
    )
  }
}

struct BackendVersionWarningPresentation {
  let warning: BackendVersionWarning
  let baseURL: String?
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
