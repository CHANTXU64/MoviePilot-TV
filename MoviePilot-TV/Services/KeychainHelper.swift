import Foundation
import Security

class KeychainHelper {
  static let shared = KeychainHelper()
  private init() {}

  func save(_ value: String, service: String, account: String) -> Bool {
    guard let data = value.data(using: .utf8) else { return false }

    // 准备一个基础查询字典，用于定位 Keychain 项目。
    // 新增 kSecAttrAccessible 属性，确保密钥仅在此设备首次解锁后可用，
    // 且不会被同步到 iCloud 或未加密的 iTunes 备份中，防止敏感信息泄露。
    let query = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: service,
      kSecAttrAccount: account,
      kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    ] as [String: Any]

    // 准备要更新的数据。
    let attributesToUpdate = [kSecValueData: data] as CFDictionary

    // 首先，尝试原子性地“更新”项目。
    // 这是官方推荐的做法，因为它比“先删后增”更安全、更高效。
    // - 如果项目已存在，它将被直接更新。
    // - 如果项目不存在，此函数将返回 `errSecItemNotFound`，我们随后处理。
    let status = SecItemUpdate(query as CFDictionary, attributesToUpdate)

    switch status {
    // 情况一：更新成功。这意味着项目之前已存在，现在已被新值覆盖。
    case errSecSuccess:
      return true

    // 情况二：项目未找到。这意味着这是首次保存该项目。
    case errSecItemNotFound:
      // 由于项目不存在，我们现在“添加”它。
      // 此处的 query 已经包含了 kSecAttrAccessible 属性，所以无需再次添加。
      var addQuery = query
      addQuery[kSecValueData as String] = data
      let addStatus = SecItemAdd(addQuery as CFDictionary, nil)

      // 返回添加操作的最终结果。
      return addStatus == errSecSuccess

    // 情况三：发生其他未预期的 Keychain 错误。
    default:
      // 打印错误以帮助调试，并返回失败。
      print("Keychain save failed with unhandled status: \(status)")
      return false
    }
  }

  func read(service: String, account: String) -> String? {
    let query =
      [
        kSecAttrService: service,
        kSecAttrAccount: account,
        kSecClass: kSecClassGenericPassword,
        kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        kSecReturnData: true,
        kSecMatchLimit: kSecMatchLimitOne,
      ] as CFDictionary

    var dataTypeRef: AnyObject?
    // 获取 Keychain 操作的状态码，以进行精细的错误处理
    let status = SecItemCopyMatching(query, &dataTypeRef)

    // 仅在明确成功时才继续处理
    if status == errSecSuccess {
      guard let data = dataTypeRef as? Data else {
        // 理论上，errSecSuccess 应该总是有数据返回，如果为 nil，说明查询配置可能存在问题
        return nil
      }
      return String(data: data, encoding: .utf8)
    } else {
      // 对于其他所有状态，都返回 nil。
      // 为了方便调试，我们特别打印出非“未找到”的错误。
      if status != errSecItemNotFound {
        // 在调试期间，这能帮助我们快速定位非预期的 Keychain 错误
        print("Keychain read failed with unhandled status: \(status)")
      }
      return nil
    }
  }

  func delete(service: String, account: String) -> Bool {
    let query =
      [
        kSecAttrService: service,
        kSecAttrAccount: account,
        kSecClass: kSecClassGenericPassword,
        kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
      ] as CFDictionary

    // 执行删除并获取状态码
    let status = SecItemDelete(query)

    // 如果删除成功，或项目本就不存在，都视为操作成功，因为最终状态符合预期（项目不存在）。
    return status == errSecSuccess || status == errSecItemNotFound
  }
}
