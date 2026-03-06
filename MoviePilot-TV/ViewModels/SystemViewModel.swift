import Foundation
import Combine

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

  init() {
    checkKeychainStatus()
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
    // 才认为 Keychain 是“使用中”的。
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
}
