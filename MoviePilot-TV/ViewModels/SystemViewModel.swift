import Combine
import Foundation

/// 默认站点在发起搜索时读取，只有聚合搜索来源需要通知已打开的页面。
struct SearchDefaultsChange {
  let profileKey: String
  let defaultMediaSearchSource: MediaSearchSource?

  @MainActor
  static func post(apiService: APIService) {
    guard let profileKey = apiService.profileKey else { return }
    NotificationCenter.default.post(
      name: .searchDefaultsDidChange,
      object: SearchDefaultsChange(
        profileKey: profileKey,
        defaultMediaSearchSource: SystemViewModel.currentDefaultMediaSearchSource(
          apiService: apiService
        )
      )
    )
  }
}

@MainActor
class SystemViewModel: ObservableObject {
  // 显式非隔离析构，避开 tvOS 18 的隔离析构回部署崩溃。
  nonisolated deinit {}

  enum StorageMechanism {
    case keychain
    case userDefaults
    case none
  }

  @Published var storageMechanism: StorageMechanism = .none
  @Published var storageDescription: String = "正在检查..."

  @Published var isRefreshing: Bool = false
  @Published var refreshMessage: String? = nil

  // MARK: - 系统信息
  @Published var serverURL: String = ""
  @Published var username: String = ""
  @Published var backendVersion: String? = nil
  private let apiService: APIService
  private var cancellables = Set<AnyCancellable>()

  var appVersion: String {
    AppVersionInfo.currentAppVersion()
  }

  var latestCompatibleMoviePilotVersion: String {
    AppVersionInfo.latestCompatibleMoviePilotVersion
  }

  // MARK: - 详情页设置

  private static let waitMediaDetailBackgroundImageKey = "waitMediaDetailBackgroundImage"
  private static let preloadTMDBDetailsKey = "preloadTMDBDetails"
  private static let autoSearchNewSubscriptionsKey = "autoSearchNewSubscriptions"

  /// 是否在 MediaDetail 首屏等待背景/海报预加载完成。默认开启。
  @Published var waitMediaDetailBackgroundImage: Bool = true {
    didSet {
      UserDefaults.standard.set(waitMediaDetailBackgroundImage, forKey: Self.waitMediaDetailBackgroundImageKey)
    }
  }

  /// 是否在豆瓣/Bangumi 详情识别完成后预加载对应 TMDB 详情。默认开启。
  @Published var preloadTMDBDetails: Bool = true {
    didSet {
      UserDefaults.standard.set(preloadTMDBDetails, forKey: Self.preloadTMDBDetailsKey)
    }
  }

  /// 新增订阅保存后是否立即触发一次手动搜索。默认开启，保持现有 TV 行为。
  @Published var autoSearchNewSubscriptions: Bool = true {
    didSet {
      UserDefaults.standard.set(autoSearchNewSubscriptions, forKey: Self.autoSearchNewSubscriptionsKey)
    }
  }

  // MARK: - 站点设置
  @Published var availableSites: [Site] = []
  @Published var isLoadingSites: Bool = false
  @Published private(set) var hasLoadedSites: Bool = false
  /// 是否拿到了权威搜索站点域（/site/）。降级为订阅域（/site/rss）时不能用来裁剪默认搜索站点（F-210）。
  @Published private(set) var loadedSitesAuthoritative: Bool = false
  @Published private(set) var siteLoadError: String?

  /// 资源搜索默认站点（绑定服务器 + 稳定用户 ID）
  var defaultSearchSites: Set<Int> {
    get { storedSiteIDs(prefix: "defaultSearchSites") }
    set { updateStoredSiteIDs(newValue, prefix: "defaultSearchSites") }
  }

  /// 字幕搜索默认站点。和资源搜索分开保存，避免资源站点把字幕搜索带空。
  var defaultSubtitleSearchSites: Set<Int> {
    get { storedSiteIDs(prefix: "defaultSubtitleSearchSites") }
    set { updateStoredSiteIDs(newValue, prefix: "defaultSubtitleSearchSites") }
  }

  /// 聚合搜索默认来源（绑定服务器 + 稳定用户 ID）；nil 表示沿用后端设置。
  var defaultMediaSearchSource: MediaSearchSource? {
    get {
      guard let key = defaultMediaSearchSourceUserDefaultsKey else { return nil }
      return UserDefaults.standard.string(forKey: key)
        .flatMap(MediaSearchSource.init(rawValue:))
    }
    set {
      guard let key = defaultMediaSearchSourceUserDefaultsKey else { return }
      if let newValue {
        UserDefaults.standard.set(newValue.rawValue, forKey: key)
      } else {
        UserDefaults.standard.removeObject(forKey: key)
      }
      objectWillChange.send()
      SearchDefaultsChange.post(apiService: apiService)
    }
  }

  // MARK: - 自定义过滤规则
  @Published var customFilterRules: [CustomRule] = []
  @Published var isLoadingRules: Bool = false
  /// 规则加载失败标记（成功空视为有效结果；失败保留旧数组并置位）
  @Published var rulesLoadFailed = false

  /// 当前选中的硬过滤规则 ID（绑定服务器 + 稳定用户 ID）
  var selectedHardFilterRuleId: String? {
    get {
      hardFilterRuleUserDefaultsKey.flatMap { UserDefaults.standard.string(forKey: $0) }
    }
    set {
      guard let key = hardFilterRuleUserDefaultsKey else { return }
      if let value = newValue {
        UserDefaults.standard.set(value, forKey: key)
      } else {
        UserDefaults.standard.removeObject(forKey: key)
      }
      objectWillChange.send()
    }
  }

  /// 当前选中的软过滤规则 ID（绑定服务器 + 稳定用户 ID）
  var selectedSoftFilterRuleId: String? {
    get {
      softFilterRuleUserDefaultsKey.flatMap { UserDefaults.standard.string(forKey: $0) }
    }
    set {
      guard let key = softFilterRuleUserDefaultsKey else { return }
      if let value = newValue {
        UserDefaults.standard.set(value, forKey: key)
      } else {
        UserDefaults.standard.removeObject(forKey: key)
      }
      objectWillChange.send()
    }
  }

  /// 当前选中的自定义硬过滤规则
  var selectedHardFilterRule: CustomRule? {
    guard let ruleId = selectedHardFilterRuleId else { return nil }
    return customFilterRules.first { $0.id == ruleId }
  }

  /// 当前选中的自定义软过滤规则
  var selectedSoftFilterRule: CustomRule? {
    guard let ruleId = selectedSoftFilterRuleId else { return nil }
    return customFilterRules.first { $0.id == ruleId }
  }

  /// 构建绑定服务器与稳定用户 ID 的 UserDefaults key，并一次性迁移旧的用户名键。
  private static func userDefaultsKey(
    _ prefix: String,
    apiService: APIService = .shared
  ) -> String? {
    let service = apiService
    guard let profileKey = service.profileKey else { return nil }
    let key = "\(prefix)_\(profileKey)"
    let defaults = UserDefaults.standard
    if defaults.object(forKey: key) == nil,
      let username = service.currentUser?.user_name,
      !username.isEmpty
    {
      let legacyKey = "\(prefix)_\(service.baseURL)_\(username)"
      if let legacyValue = defaults.object(forKey: legacyKey) {
        defaults.set(legacyValue, forKey: key)
        defaults.removeObject(forKey: legacyKey)
      }
    }
    return key
  }

  private var hardFilterRuleUserDefaultsKey: String? {
    Self.userDefaultsKey("selectedCustomFilterRuleId", apiService: apiService)
  }

  private var softFilterRuleUserDefaultsKey: String? {
    Self.userDefaultsKey("selectedSoftFilterRuleId", apiService: apiService)
  }

  private var defaultMediaSearchSourceUserDefaultsKey: String? {
    Self.userDefaultsKey("defaultMediaSearchSource", apiService: apiService)
  }

  init(apiService: APIService = .shared) {
    self.apiService = apiService
    waitMediaDetailBackgroundImage = Self.shouldWaitMediaDetailBackgroundImage
    preloadTMDBDetails = Self.shouldPreloadTMDBDetails
    autoSearchNewSubscriptions = Self.shouldAutoSearchNewSubscriptions
    checkKeychainStatus()
    apiService.$session
      .sink { [weak self] session in
        self?.updateStorageStatus(for: session)
      }
      .store(in: &cancellables)
  }

  /// 手动刷新登录凭据（解决服务器重启或 Token 失效问题）
  func relogin() async {
    guard !isRefreshing else { return }

    isRefreshing = true
    refreshMessage = nil
    defer {
      isRefreshing = false
    }

    do {
      _ = try await apiService.reloginStoredSession()
      // 同账号重登不会改变 sessionUIIdentity，SystemView 不会因此重建；成功后主动刷新连接信息。
      await loadSystemInfo()
      refreshMessage = "刷新成功"
      checkKeychainStatus()
    } catch {
      refreshMessage = "刷新失败: \(error.localizedDescription)"
    }
  }

  func logout() {
    apiService.logout()
    checkKeychainStatus()
  }

  /// 检查凭证的实际存储方式 (Keychain 或降级的 UserDefaults)
  func checkKeychainStatus() {
    updateStorageStatus(for: apiService.session)
  }

  private func updateStorageStatus(for session: APIServiceSessionState) {
    // 从单一事实来源 APIService 获取当前 App 生效的 token
    guard let activeToken = session.token, !activeToken.isEmpty else {
      // 如果没有生效的 token，则当前无任何凭证在使用
      self.storageMechanism = .none
      self.storageDescription = "未登录"
      return
    }

    // 尝试从 Keychain 中读取 token
    if apiService.isSessionStoredInKeychain == true {
      self.storageMechanism = .keychain
      self.storageDescription = "已登录（Apple 钥匙串安全存储）"
    } else {
      // 否则，虽然 App 已登录（有 activeToken），但凭证并非来自 Keychain，
      // 这说明程序已降级到使用 UserDefaults。
      self.storageMechanism = .userDefaults
      self.storageDescription = "已登录（密码明文非安全存储）"
    }
  }

  // MARK: - 系统信息加载

  /// 从后端加载系统环境和用户信息
  func loadSystemInfo() async {
    let sessionSnapshot = apiService.sessionSnapshot()
    self.serverURL = apiService.baseURL
    self.username = apiService.currentUser?.user_name ?? "未知"
    let cachedBackendVersion = normalizedBackendVersion(apiService.settings?.BACKEND_VERSION)
    self.backendVersion = cachedBackendVersion

    if apiService.isLoggedIn && apiService.canRequestSuperUserEndpoints {
      do {
        let env = try await apiService.fetchSystemEnv()
        guard apiService.isSessionUnchanged(from: sessionSnapshot) else { return }
        if let envVersion = normalizedBackendVersion(env.VERSION) {
          self.backendVersion = envVersion
          return
        }
      } catch {
        Logger.error("[SystemViewModel] 获取后端版本号失败: \(error)")
      }
    }

    guard apiService.isSessionUnchanged(from: sessionSnapshot) else { return }
    do {
      let settings = try await apiService.fetchSettings()
      guard apiService.isSessionUnchanged(from: sessionSnapshot) else { return }
      self.backendVersion = normalizedBackendVersion(settings.BACKEND_VERSION) ?? backendVersion
    } catch {
      Logger.error("[SystemViewModel] 获取公开后端版本号失败: \(error)")
    }
  }

  private func normalizedBackendVersion(_ version: String?) -> String? {
    guard let trimmed = version?.trimmingCharacters(in: .whitespacesAndNewlines),
      !trimmed.isEmpty
    else {
      return nil
    }
    return trimmed
  }

  // MARK: - 站点加载

  /// 从后端加载站点列表
  func loadSites() async {
    guard apiService.canAccess(.search) else {
      availableSites = []
      siteLoadError = nil
      return
    }
    guard !isLoadingSites else { return }
    isLoadingSites = true
    siteLoadError = nil
    defer {
      isLoadingSites = false
    }
    do {
      let (sites, authoritative) = try await apiService.fetchSearchableSites()
      availableSites = sites
      loadedSitesAuthoritative = authoritative
      hasLoadedSites = true
      defaultSearchSites = defaultSearchSites
      defaultSubtitleSearchSites = defaultSubtitleSearchSites
      Logger.info("[SystemViewModel] 加载到 \(availableSites.count) 个站点\(authoritative ? "" : "（订阅域）")")
    } catch is CancellationError {
      return
    } catch {
      siteLoadError = "站点加载失败，请重试"
      Logger.error("[SystemViewModel] 加载站点失败: \(error)")
    }
  }

  // MARK: - 自定义过滤规则加载

  /// 从后端加载自定义过滤规则
  func loadCustomFilterRules() async {
    guard apiService.canRequestSuperUserEndpoints else {
      customFilterRules = []
      rulesLoadFailed = false
      return
    }
    guard !isLoadingRules else { return }
    isLoadingRules = true
    defer {
      isLoadingRules = false
    }
    do {
      let rules = try await apiService.fetchCustomFilterRules()
      customFilterRules = rules
      rulesLoadFailed = false
      Logger.info("[SystemViewModel] 加载到 \(customFilterRules.count) 个自定义过滤规则")
      // 如果选中的规则 ID 不在列表中，清除选择
      if let selectedHardId = selectedHardFilterRuleId,
        !customFilterRules.contains(where: { $0.id == selectedHardId })
      {
        Logger.warning("[SystemViewModel] 选中的硬规则 \(selectedHardId) 已不存在，清除选择")
        selectedHardFilterRuleId = nil
      }
      if let selectedSoftId = selectedSoftFilterRuleId,
        !customFilterRules.contains(where: { $0.id == selectedSoftId })
      {
        Logger.warning("[SystemViewModel] 选中的软规则 \(selectedSoftId) 已不存在，清除选择")
        selectedSoftFilterRuleId = nil
      }
    } catch is CancellationError {
      return
    } catch {
      rulesLoadFailed = true
      Logger.error("[SystemViewModel] 加载自定义过滤规则失败: \(error)")
    }
  }

  // MARK: - 静态方法：供 ViewModel 层读取当前选中规则

  /// 获取当前用户+服务器绑定的硬过滤规则 ID
  static func currentSelectedHardFilterRuleId(apiService: APIService = .shared) -> String? {
    userDefaultsKey("selectedCustomFilterRuleId", apiService: apiService)
      .flatMap { UserDefaults.standard.string(forKey: $0) }
  }

  /// 获取当前用户+服务器绑定的软过滤规则 ID
  static func currentSelectedSoftFilterRuleId(apiService: APIService = .shared) -> String? {
    userDefaultsKey("selectedSoftFilterRuleId", apiService: apiService)
      .flatMap { UserDefaults.standard.string(forKey: $0) }
  }

  /// 获取当前用户+服务器绑定的资源搜索默认站点
  static func currentDefaultSearchSites(apiService: APIService = .shared) -> Set<Int> {
    storedSiteIDs(prefix: "defaultSearchSites", apiService: apiService)
  }

  /// 获取当前用户+服务器绑定的字幕搜索默认站点
  static func currentDefaultSubtitleSearchSites(apiService: APIService = .shared) -> Set<Int> {
    storedSiteIDs(prefix: "defaultSubtitleSearchSites", apiService: apiService)
  }

  /// 获取当前用户+服务器绑定的聚合搜索默认来源；nil 表示沿用后端设置。
  static func currentDefaultMediaSearchSource(apiService: APIService = .shared) -> MediaSearchSource? {
    userDefaultsKey("defaultMediaSearchSource", apiService: apiService)
      .flatMap { UserDefaults.standard.string(forKey: $0) }
      .flatMap(MediaSearchSource.init(rawValue:))
  }

  /// 获取已按当前可用站点清理后的资源搜索默认站点字符串。
  static func normalizedDefaultSearchSitesString(
    apiService: APIService = .shared
  ) async -> String? {
    await resolvedDefaultSearchSitesString(prefix: "defaultSearchSites", apiService: apiService)
  }

  /// 获取已按当前可用站点清理后的字幕搜索默认站点字符串。
  static func normalizedDefaultSubtitleSearchSitesString(
    apiService: APIService = .shared
  ) async -> String? {
    await resolvedDefaultSearchSitesString(prefix: "defaultSubtitleSearchSites", apiService: apiService)
  }

  private static func resolvedDefaultSearchSitesString(prefix: String, apiService: APIService) async -> String? {
    guard apiService.canAccess(.search) else { return nil }
    let snapshot = apiService.sessionSnapshot()
    let selection = storedSiteIDs(prefix: prefix, apiService: apiService)
    do {
      let (sites, authoritative) = try await apiService.fetchSearchableSites()
      guard apiService.isSessionUnchanged(from: snapshot), !Task.isCancelled else { return nil }
      let scope = SearchSiteScope(sites: sites, authoritative: authoritative)
      return scope.query(for: scope.normalized(selection))
    } catch is CancellationError {
      return nil
    } catch {
      guard apiService.isSessionUnchanged(from: snapshot), !Task.isCancelled else { return nil }
      Logger.error("[SystemViewModel] 加载默认搜索站点失败: \(error)")
      return SearchSiteScope(sites: [], authoritative: false).query(for: selection)
    }
  }

  /// 当前是否等待 MediaDetail 背景/海报预加载完成。
  static var shouldWaitMediaDetailBackgroundImage: Bool {
    guard UserDefaults.standard.object(forKey: waitMediaDetailBackgroundImageKey) != nil else {
      return true
    }
    return UserDefaults.standard.bool(forKey: waitMediaDetailBackgroundImageKey)
  }

  static var shouldPreloadTMDBDetails: Bool {
    guard UserDefaults.standard.object(forKey: preloadTMDBDetailsKey) != nil else {
      return true
    }
    return UserDefaults.standard.bool(forKey: preloadTMDBDetailsKey)
  }

  static var shouldAutoSearchNewSubscriptions: Bool {
    guard UserDefaults.standard.object(forKey: autoSearchNewSubscriptionsKey) != nil else {
      return true
    }
    return UserDefaults.standard.bool(forKey: autoSearchNewSubscriptionsKey)
  }

  private func storedSiteIDs(prefix: String) -> Set<Int> {
    Self.storedSiteIDs(prefix: prefix, apiService: apiService)
  }

  private func updateStoredSiteIDs(_ sites: Set<Int>, prefix: String) {
    guard let key = Self.userDefaultsKey(prefix, apiService: apiService) else { return }
    let array = normalizeDefaultSearchSites(sites).sorted()
    if array.isEmpty {
      UserDefaults.standard.removeObject(forKey: key)
    } else {
      UserDefaults.standard.set(array, forKey: key)
    }
    objectWillChange.send()
  }

  private func normalizeDefaultSearchSites(_ sites: Set<Int>) -> Set<Int> {
    SearchSiteScope(sites: availableSites, authoritative: hasLoadedSites && loadedSitesAuthoritative)
      .normalized(sites)
  }

  private static func storedSiteIDs(prefix: String, apiService: APIService) -> Set<Int> {
    guard let key = userDefaultsKey(prefix, apiService: apiService) else { return [] }
    let array = UserDefaults.standard.array(forKey: key) as? [Int] ?? []
    return Set(array)
  }
}
