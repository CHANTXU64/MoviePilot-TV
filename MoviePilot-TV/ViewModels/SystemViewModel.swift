import Combine
import Foundation

@MainActor
class SystemViewModel: ObservableObject {
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

  var appVersion: String {
    AppVersionInfo.currentAppVersion()
  }

  var compatibleMoviePilotVersion: String {
    AppVersionInfo.compatibleMoviePilotVersion
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
  @Published private(set) var siteLoadError: String?

  /// 默认搜索站点（绑定服务器 + 稳定用户 ID）
  var defaultSearchSites: Set<Int> {
    get {
      guard let key = defaultSearchSitesUserDefaultsKey else { return [] }
      let array = UserDefaults.standard.array(forKey: key) as? [Int] ?? []
      return Set(array)
    }
    set {
      guard let key = defaultSearchSitesUserDefaultsKey else { return }
      let normalizedSites = normalizeDefaultSearchSites(newValue)
      let array = normalizedSites.sorted()
      if array.isEmpty {
        UserDefaults.standard.removeObject(forKey: key)
      } else {
        UserDefaults.standard.set(array, forKey: key)
      }
      objectWillChange.send()
    }
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
    }
  }

  // MARK: - 自定义过滤规则
  @Published var customFilterRules: [CustomRule] = []
  @Published var isLoadingRules: Bool = false

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

  private var defaultSearchSitesUserDefaultsKey: String? {
    Self.userDefaultsKey("defaultSearchSites", apiService: apiService)
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
    // 从单一事实来源 APIService 获取当前 App 生效的 token
    guard let activeToken = apiService.token, !activeToken.isEmpty else {
      // 如果没有生效的 token，则当前无任何凭证在使用
      self.storageMechanism = .none
      self.storageDescription = "未登录"
      return
    }

    // 尝试从 Keychain 中读取 token
    if apiService.isSessionStoredInKeychain == true {
      self.storageMechanism = .keychain
      self.storageDescription = "已登录 (安全存储)"
    } else {
      // 否则，虽然 App 已登录（有 activeToken），但凭证并非来自 Keychain，
      // 这说明程序已降级到使用 UserDefaults。
      self.storageMechanism = .userDefaults
      self.storageDescription = "已登录 (非安全模式)"
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
        print("❌ [SystemViewModel] 获取后端版本号失败: \(error)")
      }
    }

    guard apiService.isSessionUnchanged(from: sessionSnapshot) else { return }
    do {
      let settings = try await apiService.fetchSettings()
      guard apiService.isSessionUnchanged(from: sessionSnapshot) else { return }
      self.backendVersion = normalizedBackendVersion(settings.BACKEND_VERSION) ?? backendVersion
    } catch {
      print("❌ [SystemViewModel] 获取公开后端版本号失败: \(error)")
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
      let sites = try await apiService.fetchSites()
      availableSites = sites
      hasLoadedSites = true
      defaultSearchSites = defaultSearchSites
      print("✅ [SystemViewModel] 加载到 \(availableSites.count) 个站点")
    } catch is CancellationError {
      return
    } catch {
      siteLoadError = "站点加载失败，请重试"
      print("❌ [SystemViewModel] 加载站点失败: \(error)")
    }
  }

  // MARK: - 自定义过滤规则加载

  /// 从后端加载自定义过滤规则
  func loadCustomFilterRules() async {
    guard apiService.canRequestSuperUserEndpoints else {
      customFilterRules = []
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
      print("✅ [SystemViewModel] 加载到 \(customFilterRules.count) 个自定义过滤规则")
      // 如果选中的规则 ID 不在列表中，清除选择
      if let selectedHardId = selectedHardFilterRuleId,
        !customFilterRules.contains(where: { $0.id == selectedHardId })
      {
        print("⚠️ [SystemViewModel] 选中的硬规则 \(selectedHardId) 已不存在，清除选择")
        selectedHardFilterRuleId = nil
      }
      if let selectedSoftId = selectedSoftFilterRuleId,
        !customFilterRules.contains(where: { $0.id == selectedSoftId })
      {
        print("⚠️ [SystemViewModel] 选中的软规则 \(selectedSoftId) 已不存在，清除选择")
        selectedSoftFilterRuleId = nil
      }
    } catch is CancellationError {
      customFilterRules = []
      return
    } catch {
      print("❌ [SystemViewModel] 加载自定义过滤规则失败: \(error)")
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

  /// 获取当前用户+服务器绑定的默认搜索站点
  static func currentDefaultSearchSites(apiService: APIService = .shared) -> Set<Int> {
    guard let key = userDefaultsKey("defaultSearchSites", apiService: apiService) else { return [] }
    let array = UserDefaults.standard.array(forKey: key) as? [Int] ?? []
    return Set(array)
  }

  /// 获取当前用户+服务器绑定的聚合搜索默认来源；nil 表示沿用后端设置。
  static func currentDefaultMediaSearchSource(apiService: APIService = .shared) -> MediaSearchSource? {
    userDefaultsKey("defaultMediaSearchSource", apiService: apiService)
      .flatMap { UserDefaults.standard.string(forKey: $0) }
      .flatMap(MediaSearchSource.init(rawValue:))
  }

  /// 获取已按当前可用站点清理后的默认搜索站点。
  static func normalizedCurrentDefaultSearchSites(
    apiService: APIService = .shared
  ) async -> Set<Int> {
    let storedSites = currentDefaultSearchSites(apiService: apiService)
    guard !storedSites.isEmpty else { return [] }
    guard apiService.canAccess(.search) else { return [] }
    let snapshot = apiService.sessionSnapshot()

    do {
      let availableSites = try await apiService.fetchSites()
      guard apiService.isSessionUnchanged(from: snapshot) else { return [] }
      let availableSiteIds = Set(availableSites.map(\.id))
      let normalizedSites = storedSites.intersection(availableSiteIds)
      if normalizedSites != storedSites {
        persistDefaultSearchSites(normalizedSites, apiService: apiService)
      }
      return normalizedSites
    } catch is CancellationError {
      return []
    } catch {
      print("❌ [SystemViewModel] 默认搜索站点归一化失败: \(error)")
      return storedSites
    }
  }

  /// 获取已按当前可用站点清理后的默认搜索站点字符串。
  static func normalizedDefaultSearchSitesString(
    apiService: APIService = .shared
  ) async -> String? {
    siteIdsString(from: await normalizedCurrentDefaultSearchSites(apiService: apiService))
  }

  /// 获取默认搜索站点的逗号分隔字符串
  @available(*, deprecated, message: "搜索前请使用 normalizedDefaultSearchSitesString()，避免发送已删除站点。")
  static var defaultSearchSitesString: String? {
    siteIdsString(from: currentDefaultSearchSites())
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

  private func normalizeDefaultSearchSites(_ sites: Set<Int>) -> Set<Int> {
    guard hasLoadedSites else { return sites }

    let availableSiteIds = Set(availableSites.map(\.id))
    return sites.intersection(availableSiteIds)
  }

  private static func persistDefaultSearchSites(
    _ sites: Set<Int>,
    apiService: APIService = .shared
  ) {
    guard let key = userDefaultsKey("defaultSearchSites", apiService: apiService) else { return }
    let array = sites.sorted()
    if array.isEmpty {
      UserDefaults.standard.removeObject(forKey: key)
    } else {
      UserDefaults.standard.set(array, forKey: key)
    }
  }

  private static func siteIdsString(from sites: Set<Int>) -> String? {
    sites.isEmpty ? nil : sites.sorted().map { String($0) }.joined(separator: ",")
  }
}
