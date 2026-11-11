#if DEBUG
import Foundation

/// UI 预览目录的「模拟后端」。
///
/// 设计目标：预览目录渲染的是线上同一套 View/ViewModel，只把最底层的网络请求
/// 换成固定 fixture。这样页面加载、空数据、失败、无权限、加载更多等状态都由真实
/// 业务代码驱动，预览结构与线上保持一致，也不会访问真实 MoviePilot 后端。
///
/// 各业务域在 `Fixtures/` 下用 extension 提供自己的 fixture 与行为开关；
/// APIService 的对应方法在 `#if DEBUG if UIPreviewMode.isEnabled()` 时直接调用它们。
@MainActor
final class UIPreviewBackend {
  static let shared = UIPreviewBackend()

  /// 单个接口的模拟行为。
  enum Behavior: Equatable {
    /// 返回正常 fixture 数据。
    case data
    /// 返回空数据（列表为空、无结果、无记录）。
    case empty
    /// 抛出模拟失败（页面展示失败状态/提示）。
    case failure
    /// 抛出指定类型的错误，用于预览不同错误种类下页面/提示的差异。
    case error(UIPreviewErrorKind)
    /// 永不返回，用于长时间保持加载中。
    case hang
    /// 延迟后再返回 fixture 数据，用于提交中/刷新中等过渡态。
    case delayed(seconds: Double)
  }

  private(set) var environment: UIPreviewEnvironment = .standard
  private(set) var lastActivation: Date = .distantPast
  /// 诊断：页面请求了但预览没有提供 fixture 的接口（按出现顺序）。
  private(set) var missingEndpointLog: [String] = []

  private init() {}

  /// 预览场景进入时调用：切换会话身份、全局设置与逐接口行为，并重建预览后端状态。
  /// 同一环境多次激活是安全的（用于 SwiftUI 重求值）。
  func activate(_ environment: UIPreviewEnvironment) {
    self.environment = environment
    APIService.shared.installUIPreviewSession(
      token: environment.token,
      baseURL: environment.baseURL
    )
    lastActivation = Date()
  }

  /// 回到目录/默认状态：标准登录用户、全部接口返回 fixture。
  func reset() {
    missingEndpointLog = []
    activate(.standard)
  }

  func behavior(for key: String) -> Behavior {
    environment.behaviors[key] ?? .data
  }

  /// 场景是否显式指定了该接口的行为。用于同一 API 方法被多个业务域共用时，
  /// 按「哪个域设置了行为键」选择对应 fixture，未设置时走默认域。
  func hasBehavior(for key: String) -> Bool {
    environment.behaviors[key] != nil
  }

  func isData(for key: String) -> Bool {
    behavior(for: key) == .data
  }

  /// 当前行为是否为 `empty`。
  func isEmpty(for key: String) -> Bool {
    behavior(for: key) == .empty
  }

  /// 统一处理 failure / error / hang / delayed；`data` 与 `empty` 直接返回，由 fixture 决定数据形态。
  func gate(_ key: String) async throws {
    switch behavior(for: key) {
    case .data, .empty:
      return
    case .failure:
      throw UIPreviewBackendError.simulatedFailure(feature: key)
    case .error(let kind):
      throw kind.makeError()
    case .hang:
      try await Task.sleep(for: .seconds(60 * 60 * 24 * 365))
      throw CancellationError()
    case .delayed(let seconds):
      try await Task.sleep(for: .seconds(seconds))
    }
  }

  /// 失败场景下 `gate` 会抛出该错误；页面的错误提示会带上描述，方便确认正处于预览状态。
  func simulatedFailureError() -> Error {
    UIPreviewBackendError.simulatedFailure(feature: "预览")
  }

  /// 场景附加参数（例如当前搜索词、当前数据源）。
  func context(_ key: String) -> String? {
    environment.context[key]
  }

  func recordMissingEndpoint(_ endpoint: String) {
    guard !missingEndpointLog.contains(endpoint) else { return }
    missingEndpointLog.append(endpoint)
    Logger.error("[UIPreview] 未提供 fixture 的接口：\(endpoint)")
  }

  /// 兜底：任何没有被 APIService 预览钩子拦截的请求都不会访问真实后端。
  /// GET 直接抛出可见错误；写操作模拟成功，避免预览页面停留在错误提示。
  func unstubbedRequest(endpoint: String, method: String) async throws -> Data {
    recordMissingEndpoint("\(method.uppercased()) \(endpoint)")
    if method.uppercased() == "GET" {
      throw UIPreviewBackendError.missingStub(endpoint: endpoint)
    }
    return Data(#"{"success":true,"data":null}"#.utf8)
  }
}

/// UI 预览可模拟的错误种类。
///
/// 预览渲染真实页面，页面拿到的是真实错误对象，因此不同错误类型下的提示、重试、
/// 鉴权跳转或网络说明都能按线上分支走一遍。`makeError()` 构造的是生产代码里同名
/// `APIError`/`UIPreviewBackendError` 实例；调用方只通过 `localizedDescription` 展示。
enum UIPreviewErrorKind: Equatable {
  case invalidURL
  case networkTimeout
  case networkOffline
  case networkConnectionLost
  case decoding
  /// 后端 `success=false` 的业务错误，`message` 是后端返回的文案。
  case serverMessage(String)
  /// 502/503/504 反向代理错误。
  case gateway(Int)
  /// 其他 HTTP 状态码（403、404、429、500 等）。
  case http(Int)
  /// 需要交互的鉴权挑战（401 且返回了提示文案）。
  case authenticationChallenge(statusCode: Int, message: String?)
  case credentialsRejected
  case mfaUnsupported
  case unauthorized
  case unknown
  /// 自定义业务错误文案（没有对应生产错误类型时使用）。
  case business(String)

  func makeError() -> Error {
    switch self {
    case .invalidURL:
      return APIError.invalidURL
    case .networkTimeout:
      return APIError.networkError(URLError(.timedOut))
    case .networkOffline:
      return APIError.networkError(URLError(.notConnectedToInternet))
    case .networkConnectionLost:
      return APIError.networkError(URLError(.networkConnectionLost))
    case .decoding:
      return APIError.decodingError(
        DecodingError.dataCorrupted(
          .init(codingPath: [], debugDescription: "The given data was not valid JSON.")))
    case .serverMessage(let message):
      return APIError.serverMessage(message)
    case .gateway(let status):
      return APIError.gatewayStatus(status, "HTTP \(status)")
    case .http(let status):
      return APIError.authenticationChallenge(statusCode: status, message: nil)
    case .authenticationChallenge(let statusCode, let message):
      return APIError.authenticationChallenge(statusCode: statusCode, message: message)
    case .credentialsRejected:
      return APIError.credentialsRejected
    case .mfaUnsupported:
      return APIError.mfaUnsupported
    case .unauthorized:
      return APIError.unauthorized
    case .unknown:
      return APIError.unknown
    case .business(let message):
      return UIPreviewBackendError.business(message)
    }
  }
}

/// UI 预览模拟后端的错误。Debug 下可见，Release 不编译。
enum UIPreviewBackendError: LocalizedError {
  case missingStub(endpoint: String)
  case simulatedFailure(feature: String)
  case business(String)

  var errorDescription: String? {
    switch self {
    case .missingStub(let endpoint):
      return "UI 预览未提供该接口的模拟数据：\(endpoint)"
    case .simulatedFailure(let feature):
      return "UI 预览：模拟加载失败（\(feature)）"
    case .business(let message):
      return message
    }
  }
}

/// 预览场景环境：会话身份 + 全局设置覆盖 + 逐接口行为 + 场景附加参数。
struct UIPreviewEnvironment {
  var token: Token?
  var baseURL: String
  var backendVersion: String?
  var behaviors: [String: UIPreviewBackend.Behavior]
  var context: [String: String]

  init(
    token: Token?,
    baseURL: String = UIPreviewEnvironment.defaultBaseURL,
    backendVersion: String? = UIPreviewEnvironment.defaultBackendVersion,
    behaviors: [String: UIPreviewBackend.Behavior] = [:],
    context: [String: String] = [:]
  ) {
    self.token = token
    self.baseURL = baseURL
    self.backendVersion = backendVersion
    self.behaviors = behaviors
    self.context = context
  }

  static let defaultBaseURL = "http://moviepilot-ui-preview.local:3000"
  static let defaultBackendVersion = "v3.2.5"

  /// 标准预览环境：登录态、全部权限、所有接口返回 fixture。
  static let standard = UIPreviewEnvironment(
    token: UIPreviewFixtures.userToken()
  )

  /// 应用内播放可用环境：应用内播放从后端 v3.2.6 起开放，这里用该版本演示播放入口与播放器链路。
  /// 注意 v3.2.6 尚未登记到兼容版本表，只用于预览；`MainContentView` 类场景不会弹版本告警。
  static let playback = UIPreviewEnvironment(
    token: UIPreviewFixtures.userToken(),
    backendVersion: "v3.2.6"
  )

  /// 未登录环境（登录页、登录流程预览）。
  static let loggedOut = UIPreviewEnvironment(token: nil)

  /// 指定功能权限的登录用户环境（低权限 Tab/无权限状态预览）。
  static func limited(
    permissions: Set<UserPermissionKey>,
    superUser: Bool = false
  ) -> UIPreviewEnvironment {
    UIPreviewEnvironment(
      token: UIPreviewFixtures.userToken(
        permissions: permissions,
        superUser: superUser
      )
    )
  }
}

/// 逐接口行为键。各业务域在自己的 fixture 文件里用 extension 追加常量。
enum UIPreviewBehaviorKey {}
#endif
