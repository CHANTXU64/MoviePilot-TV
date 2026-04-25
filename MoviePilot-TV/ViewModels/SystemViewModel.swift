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

  private let keychainService = "MoviePilot-TV"
  private let keychainAccount = "accessToken"

  @Published var isRefreshing: Bool = false
  @Published var refreshMessage: String? = nil

  // MARK: - 自定义过滤规则
  @Published var customFilterRules: [CustomRule] = []
  @Published var isLoadingRules: Bool = false

  /// 当前选中的过滤规则 ID（绑定 URL + 用户名）
  var selectedCustomFilterRuleId: String? {
    get {
      UserDefaults.standard.string(forKey: filterRuleUserDefaultsKey)
    }
    set {
      if let value = newValue {
        UserDefaults.standard.set(value, forKey: filterRuleUserDefaultsKey)
      } else {
        UserDefaults.standard.removeObject(forKey: filterRuleUserDefaultsKey)
      }
      objectWillChange.send()
    }
  }

  /// 当前选中的自定义过滤规则
  var selectedCustomFilterRule: CustomRule? {
    guard let ruleId = selectedCustomFilterRuleId else { return nil }
    return customFilterRules.first { $0.id == ruleId }
  }

  /// 持久化 key，绑定 baseURL + 用户名
  private var filterRuleUserDefaultsKey: String {
    let baseURL = APIService.shared.baseURL
    let username =
      KeychainHelper.shared.read(service: "MoviePilot-TV", account: "username")
      ?? UserDefaults.standard.string(forKey: "username")
      ?? "default"
    return "selectedCustomFilterRuleId_\(baseURL)_\(username)"
  }

  init() {
    checkKeychainStatus()
  }

  /// 手动刷新登录凭据（解决服务器重启或 Token 失效问题）
  func relogin() async {
    isRefreshing = true
    refreshMessage = nil

    // 从 Keychain 获取保存的用户名密码
    let username =
      KeychainHelper.shared.read(service: "MoviePilot-TV", account: "username")
      ?? UserDefaults.standard.string(forKey: "username")
    let password =
      KeychainHelper.shared.read(service: "MoviePilot-TV", account: "password")
      ?? UserDefaults.standard.string(forKey: "password")

    guard let u = username, let p = password, !u.isEmpty, !p.isEmpty else {
      refreshMessage = "未找到保存的凭据，请重新登录"
      isRefreshing = false
      return
    }

    do {
      _ = try await APIService.shared.login(username: u, password: p)
      refreshMessage = "刷新成功"
      checkKeychainStatus()
    } catch {
      refreshMessage = "刷新失败: \(error.localizedDescription)"
    }

    isRefreshing = false
  }

  /// 检查凭证的实际存储方式 (Keychain 或降级的 UserDefaults)
  func checkKeychainStatus() {
    // 从单一事实来源 APIService 获取当前 App 生效的 token
    guard let activeToken = APIService.shared.token, !activeToken.isEmpty else {
      // 如果没有生效的 token，则当前无任何凭证在使用
      self.storageMechanism = .none
      self.storageDescription = "未登录"
      return
    }

    // 尝试从 Keychain 中读取 token
    let keychainToken = KeychainHelper.shared.read(
      service: keychainService,
      account: keychainAccount
    )

    // 核心验证：只有当 Keychain 里的 token 与当前 App 生效的 token 完全一致时，
    // 才认为 Keychain 是"使用中"的。
    if let keychainToken, keychainToken == activeToken {
      self.storageMechanism = .keychain
      self.storageDescription = "已登录 (安全存储)"
    } else {
      // 否则，虽然 App 已登录（有 activeToken），但凭证并非来自 Keychain，
      // 这说明程序已降级到使用 UserDefaults。
      self.storageMechanism = .userDefaults
      self.storageDescription = "已登录 (非安全模式)"
    }
  }

  // MARK: - 自定义过滤规则加载

  /// 从后端加载自定义过滤规则
  func loadCustomFilterRules() async {
    guard !isLoadingRules else { return }
    isLoadingRules = true
    do {
      customFilterRules = try await APIService.shared.fetchCustomFilterRules()
      print("✅ [SystemViewModel] 加载到 \(customFilterRules.count) 个自定义过滤规则")
      // 如果选中的规则 ID 不在列表中，清除选择
      if let selectedId = selectedCustomFilterRuleId,
        !customFilterRules.contains(where: { $0.id == selectedId })
      {
        print("⚠️ [SystemViewModel] 选中的规则 \(selectedId) 已不存在，清除选择")
        selectedCustomFilterRuleId = nil
      }
    } catch {
      print("❌ [SystemViewModel] 加载自定义过滤规则失败: \(error)")
    }
    isLoadingRules = false
  }

  // MARK: - 静态方法：供 ViewModel 层读取当前选中规则

  /// 获取当前用户+服务器绑定的过滤规则 ID
  static func currentSelectedFilterRuleId() -> String? {
    let baseURL = APIService.shared.baseURL
    let username =
      KeychainHelper.shared.read(service: "MoviePilot-TV", account: "username")
      ?? UserDefaults.standard.string(forKey: "username")
      ?? "default"
    let key = "selectedCustomFilterRuleId_\(baseURL)_\(username)"
    return UserDefaults.standard.string(forKey: key)
  }
}
