import Foundation
import Kingfisher

/// 通用的 MoviePilot 图片预热器。
/// 接受 APIService 生成的 MP 图片缓存 URL；相同 URL 合并进行中的请求，并短期跳过已成功的请求。
/// 收到有效图片响应头后立即取消响应体，不保存文件，也不在 Apple TV 上解码图片。
@MainActor
final class MPImageWarmer {
  struct Handle: Hashable, Sendable {
    let requestID: UUID
    let ownerID: UUID
    fileprivate let urlKey: String
  }

  private struct ActiveRequest {
    let requestID: UUID
    let task: URLSessionDataTask
    var owners: Set<UUID>
  }

  static let shared = MPImageWarmer()

  private let sessionDelegate: MPImageWarmSessionDelegate
  private let session: URLSession
  private let recentWarmTTL: TimeInterval
  private let recentWarmLimit: Int
  private let now: @Sendable () -> Date
  private var activeRequests: [String: ActiveRequest] = [:]
  private var recentlyWarmedURLs: [String: Date] = [:]

  var activeRequestCount: Int { activeRequests.count }
  var cachedURLCount: Int { recentlyWarmedURLs.count }

  init(
    configuration: URLSessionConfiguration = MPImageWarmer.makeConfiguration(),
    recentWarmTTL: TimeInterval = 60 * 60,
    recentWarmLimit: Int = 512,
    now: @escaping @Sendable () -> Date = Date.init
  ) {
    let sessionDelegate = MPImageWarmSessionDelegate()
    self.sessionDelegate = sessionDelegate
    session = URLSession(
      configuration: configuration,
      delegate: sessionDelegate,
      delegateQueue: nil
    )
    self.recentWarmTTL = recentWarmTTL
    self.recentWarmLimit = recentWarmLimit
    self.now = now
    sessionDelegate.owner = self
  }

  @discardableResult
  func warm(_ url: URL) async -> Handle? {
    let apiService = APIService.shared
    return await warm(
      url,
      baseURL: apiService.baseURL,
      imageCacheEnabled: apiService.useImageCache
    )
  }

  /// 批量预热并去除本批次内的重复 URL；不限制其他图片请求的并发。
  func warm(_ urls: [URL]) async -> [Handle] {
    var handles: [Handle] = []
    var seenURLs = Set<String>()
    for url in urls {
      guard seenURLs.insert(Self.warmKey(for: url)).inserted else { continue }
      if let handle = await warm(url) {
        handles.append(handle)
      }
    }
    return handles
  }

  @discardableResult
  func warm(
    _ url: URL,
    baseURL: String,
    imageCacheEnabled: Bool
  ) async -> Handle? {
    guard
      Self.isWarmable(
        url,
        baseURL: baseURL,
        imageCacheEnabled: imageCacheEnabled
      )
    else {
      Logger.debug("[MPImageWarmer] 跳过非 MP 缓存图片：\(url.path)")
      return nil
    }

    let urlKey = Self.warmKey(for: url)
    if isRecentlyWarmed(urlKey) {
      Logger.debug("[MPImageWarmer] 已缓存，跳过：\(url.path)")
      return nil
    }

    let ownerID = UUID()
    if var activeRequest = activeRequests[urlKey] {
      activeRequest.owners.insert(ownerID)
      activeRequests[urlKey] = activeRequest
      return Handle(
        requestID: activeRequest.requestID,
        ownerID: ownerID,
        urlKey: urlKey
      )
    }

    var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
    guard let requestWithCookies = AnyModifier.cookieModifier.modified(for: request) else {
      return nil
    }
    request = requestWithCookies

    let requestID = UUID()
    let task = session.dataTask(with: request)
    activeRequests[urlKey] = ActiveRequest(
      requestID: requestID,
      task: task,
      owners: [ownerID]
    )
    task.priority = URLSessionTask.lowPriority
    task.resume()
    return Handle(requestID: requestID, ownerID: ownerID, urlKey: urlKey)
  }

  func cancel(_ handle: Handle) {
    guard var activeRequest = activeRequests[handle.urlKey],
      activeRequest.requestID == handle.requestID
    else {
      return
    }

    activeRequest.owners.remove(handle.ownerID)
    guard activeRequest.owners.isEmpty else {
      activeRequests[handle.urlKey] = activeRequest
      return
    }

    activeRequests.removeValue(forKey: handle.urlKey)
    activeRequest.task.cancel()
    Logger.debug("[MPImageWarmer] 已取消：\(activeRequest.task.originalRequest?.url?.path ?? "")")
  }

  func clear() {
    let requests = activeRequests.values
    activeRequests.removeAll()
    recentlyWarmedURLs.removeAll()
    for request in requests {
      request.task.cancel()
    }
  }

  fileprivate func didReceive(_ response: URLResponse, for task: URLSessionDataTask) {
    guard let url = task.originalRequest?.url else { return }
    let urlKey = Self.warmKey(for: url)
    guard activeRequests[urlKey]?.task.taskIdentifier == task.taskIdentifier else { return }
    activeRequests.removeValue(forKey: urlKey)

    guard let response = response as? HTTPURLResponse,
      (200..<300).contains(response.statusCode),
      response.mimeType?.lowercased().hasPrefix("image/") == true
    else {
      Logger.error("[MPImageWarmer] 响应无效：\(url.path)")
      return
    }

    cacheRecentlyWarmed(urlKey)
    Logger.debug("[MPImageWarmer] 完成：\(url.path)，HTTP \(response.statusCode)")
  }

  fileprivate func didComplete(_ task: URLSessionTask, error: Error?) {
    guard let url = task.originalRequest?.url else { return }
    let urlKey = Self.warmKey(for: url)
    guard activeRequests[urlKey]?.task.taskIdentifier == task.taskIdentifier else { return }
    activeRequests.removeValue(forKey: urlKey)

    Logger.error("[MPImageWarmer] 失败：\(url.path)，\(error?.localizedDescription ?? "未知错误")")
  }

  private func isRecentlyWarmed(_ urlKey: String) -> Bool {
    guard let warmedAt = recentlyWarmedURLs[urlKey] else { return false }
    guard now().timeIntervalSince(warmedAt) < recentWarmTTL else {
      recentlyWarmedURLs.removeValue(forKey: urlKey)
      return false
    }
    return true
  }

  private func cacheRecentlyWarmed(_ urlKey: String) {
    if recentlyWarmedURLs.count >= recentWarmLimit,
      recentlyWarmedURLs[urlKey] == nil,
      let oldestKey = recentlyWarmedURLs.min(by: { $0.value < $1.value })?.key
    {
      recentlyWarmedURLs.removeValue(forKey: oldestKey)
    }
    recentlyWarmedURLs[urlKey] = now()
  }

  nonisolated static func makeConfiguration() -> URLSessionConfiguration {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    return configuration
  }

  nonisolated static func isWarmable(
    _ url: URL,
    baseURL: String,
    imageCacheEnabled: Bool
  ) -> Bool {
    guard imageCacheEnabled,
      let base = URLComponents(string: baseURL),
      let target = URLComponents(url: url, resolvingAgainstBaseURL: false),
      base.scheme?.lowercased() == target.scheme?.lowercased(),
      base.host?.lowercased() == target.host?.lowercased(),
      effectivePort(base) == effectivePort(target)
    else {
      return false
    }

    let basePath =
      base.path == "/" ? "" : base.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    let pathPrefix = basePath.isEmpty ? "" : "/\(basePath)"
    let queryItems = target.queryItems ?? []

    switch target.path {
    case "\(pathPrefix)/api/v1/system/cache/image":
      return queryItems.contains { $0.name == "url" && $0.value?.isEmpty == false }
    case "\(pathPrefix)/api/v1/system/img/1":
      return queryItems.contains { $0.name == "imgurl" && $0.value?.isEmpty == false }
        && queryItems.contains { $0.name == "cache" && $0.value?.lowercased() == "true" }
    default:
      return false
    }
  }

  /// 当前会话的 MP 服务器固定，登出时会清空预热记录，因此只需按原图去重。
  nonisolated static func warmKey(for url: URL) -> String {
    guard let target = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
      return url.absoluteString
    }
    let parameterName =
      target.path.hasSuffix("/api/v1/system/cache/image") ? "url" : "imgurl"
    return target.queryItems?.first(where: { $0.name == parameterName })?.value
      ?? url.absoluteString
  }

  nonisolated private static func effectivePort(_ components: URLComponents) -> Int? {
    if let port = components.port {
      return port
    }
    switch components.scheme?.lowercased() {
    case "http":
      return 80
    case "https":
      return 443
    default:
      return nil
    }
  }
}

final class MPImageWarmSessionDelegate: NSObject, URLSessionDataDelegate,
  @unchecked Sendable
{
  weak var owner: MPImageWarmer?

  func urlSession(
    _ session: URLSession,
    dataTask: URLSessionDataTask,
    didReceive response: URLResponse,
    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
  ) {
    completionHandler(.cancel)
    Task { @MainActor [weak owner] in
      owner?.didReceive(response, for: dataTask)
    }
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: Error?
  ) {
    guard (error as? URLError)?.code != .cancelled else { return }
    Task { @MainActor [weak owner] in
      owner?.didComplete(task, error: error)
    }
  }
}
