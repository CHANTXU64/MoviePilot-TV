import Combine
import Foundation

enum MemoryOptimizationMode: String, CaseIterable, Hashable, Identifiable {
  case automatic
  case enabled
  case disabled

  var id: String { rawValue }

  var title: String {
    switch self {
    case .automatic:
      return "自动"
    case .enabled:
      return "开启"
    case .disabled:
      return "关闭"
    }
  }
}

private final class MemoryOptimizationProbeMetrics: NSObject, URLSessionTaskDelegate,
  @unchecked Sendable
{
  private let lock = NSLock()
  private var storedResult: (latency: TimeInterval, remoteAddress: String)?

  var result: (latency: TimeInterval, remoteAddress: String)? {
    lock.lock()
    defer { lock.unlock() }
    return storedResult
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didFinishCollecting metrics: URLSessionTaskMetrics
  ) {
    guard let transaction = metrics.transactionMetrics.last,
      let requestStartDate = transaction.requestStartDate,
      let responseStartDate = transaction.responseStartDate,
      let remoteAddress = transaction.remoteAddress
    else {
      return
    }

    lock.lock()
    storedResult = (
      latency: responseStartDate.timeIntervalSince(requestStartDate),
      remoteAddress: remoteAddress
    )
    lock.unlock()
  }
}

/// 控制允许以少量网络或重新渲染成本换取更低内存的优化。自动模式会按当前会话判断。
@MainActor
final class MemoryOptimizationPolicy: ObservableObject {
  typealias LatencyProbe =
    @Sendable (String) async -> (
      latency: TimeInterval, remoteAddress: String
    )?

  static let shared = MemoryOptimizationPolicy()

  @Published var mode: MemoryOptimizationMode {
    didSet {
      guard mode != oldValue else { return }
      if isProductionInstance {
        UserDefaults.standard.set(mode.rawValue, forKey: Self.modeKey)
      }
      cancelAutomaticEvaluation()
      if mode == .automatic {
        automaticEnabled = false
      }
      applyCurrentMode()
      if mode == .automatic, isProductionInstance {
        refreshAutomaticDecision()
      }
    }
  }

  @Published private(set) var isEnabled: Bool
  @Published private(set) var automaticEnabled = false

  private static let modeKey = "memoryOptimizationMode"
  private nonisolated static let maximumAutomaticLatency: TimeInterval = 0.030
  private let latencyProbe: LatencyProbe
  private let sessionIsCurrent: @MainActor (APIServiceSessionSnapshot) -> Bool
  private let isProductionInstance: Bool
  private var automaticEvaluationGeneration = 0
  private var automaticEvaluationTask: Task<Void, Never>?

  private init() {
    latencyProbe = Self.measureServerLatency
    sessionIsCurrent = { APIService.shared.isSessionUnchanged(from: $0) }
    isProductionInstance = true
    let storedMode =
      UserDefaults.standard.string(forKey: Self.modeKey)
      .flatMap(MemoryOptimizationMode.init(rawValue:)) ?? .automatic
    mode = storedMode
    isEnabled = storedMode == .enabled
  }

  init(
    testingMode: MemoryOptimizationMode,
    automaticEnabled: Bool = false,
    latencyProbe: @escaping LatencyProbe,
    sessionIsCurrent: @escaping @MainActor (APIServiceSessionSnapshot) -> Bool
  ) {
    self.latencyProbe = latencyProbe
    self.sessionIsCurrent = sessionIsCurrent
    isProductionInstance = false
    mode = testingMode
    self.automaticEnabled = automaticEnabled
    isEnabled = Self.resolvedEnabledState(
      mode: testingMode,
      automaticEnabled: automaticEnabled
    )
  }

  /// 服务器或登录会话改变后，立即停用旧的自动判断，等待当前会话重新检查。
  func invalidateAutomaticDecision() {
    cancelAutomaticEvaluation()
    automaticEnabled = false
    applyCurrentMode()
  }

  /// 从手动模式切回自动时刷新服务器设置，再重新判断一次。
  private func refreshAutomaticDecision() {
    let apiService = APIService.shared
    let sessionSnapshot = apiService.sessionSnapshot()
    let generation = automaticEvaluationGeneration
    automaticEvaluationTask = Task { [weak self] in
      guard let self else { return }
      do {
        _ = try await apiService.fetchSettings()
        await performAutomaticEvaluation(
          sessionSnapshot: sessionSnapshot,
          settingsLoaded: true,
          imageCacheAvailable: apiService.useImageCache,
          generation: generation
        )
      } catch {
        await performAutomaticEvaluation(
          sessionSnapshot: sessionSnapshot,
          settingsLoaded: false,
          imageCacheAvailable: false,
          generation: generation
        )
      }
    }
  }

  /// 使用本次进入 App 时获取的服务器设置重新判断。
  func evaluateAutomatically(
    sessionSnapshot: APIServiceSessionSnapshot,
    settingsLoaded: Bool,
    imageCacheAvailable: Bool
  ) {
    guard mode == .automatic,
      sessionIsCurrent(sessionSnapshot)
    else {
      return
    }

    cancelAutomaticEvaluation()
    let generation = automaticEvaluationGeneration
    automaticEvaluationTask = Task { [weak self] in
      await self?.performAutomaticEvaluation(
        sessionSnapshot: sessionSnapshot,
        settingsLoaded: settingsLoaded,
        imageCacheAvailable: imageCacheAvailable,
        generation: generation
      )
    }
  }

  private func performAutomaticEvaluation(
    sessionSnapshot: APIServiceSessionSnapshot,
    settingsLoaded: Bool,
    imageCacheAvailable: Bool,
    generation: Int
  ) async {
    guard
      canPublishAutomaticResult(
        generation: generation,
        sessionSnapshot: sessionSnapshot
      )
    else {
      return
    }

    func finish(_ result: Bool, reason: String, isError: Bool = false) {
      finishAutomaticEvaluation(
        result,
        reason: reason,
        isError: isError,
        generation: generation,
        sessionSnapshot: sessionSnapshot
      )
    }

    Logger.debug(
      "[MemoryOptimization] 自动检查：服务器设置=\(settingsLoaded ? "已读取" : "读取失败")，图片缓存=\(imageCacheAvailable ? "可用" : "不可用")"
    )

    guard settingsLoaded else {
      finish(
        false,
        reason: "服务器设置读取失败",
        isError: true
      )
      return
    }
    guard imageCacheAvailable else {
      finish(false, reason: "MP 图片缓存不可用")
      return
    }
    guard URL(string: sessionSnapshot.baseURL)?.host?.isEmpty == false else {
      finish(
        false,
        reason: "服务器地址无效",
        isError: true
      )
      return
    }

    var probes: [(latency: TimeInterval, remoteAddress: String)] = []
    for _ in 0..<3 {
      guard !Task.isCancelled else { return }
      if let probe = await latencyProbe(sessionSnapshot.baseURL) {
        probes.append(probe)
      }
    }
    let probeDescription = probes.map {
      String(format: "%@ %.1fms", $0.remoteAddress, $0.latency * 1_000)
    }.joined(separator: "，")
    Logger.debug("[MemoryOptimization] 有效探测 \(probes.count)/3：\(probeDescription)")

    guard probes.allSatisfy({ Self.isLocalAddress($0.remoteAddress) }) else {
      finish(false, reason: "实际连接的服务器不是内网地址")
      return
    }
    guard probes.count >= 2 else {
      finish(false, reason: "服务器延迟测试有效结果不足", isError: true)
      return
    }
    guard let latency = probes.map(\.latency).min() else { return }
    let latencyInMilliseconds = latency * 1_000
    Logger.debug(
      String(
        format: "[MemoryOptimization] HTTP 首包延迟最小值：%.1fms（自动开启阈值 < %.1fms）",
        latencyInMilliseconds,
        Self.maximumAutomaticLatency * 1_000
      )
    )
    guard Self.isAutomaticLatencyAcceptable(latency) else {
      finish(
        false,
        reason: String(format: "服务器延迟 %.1fms，不启用", latencyInMilliseconds)
      )
      return
    }

    finish(
      true,
      reason: String(format: "服务器延迟 %.1fms，启用", latencyInMilliseconds)
    )
  }

  private func finishAutomaticEvaluation(
    _ result: Bool,
    reason: String,
    isError: Bool,
    generation: Int,
    sessionSnapshot: APIServiceSessionSnapshot
  ) {
    guard
      canPublishAutomaticResult(
        generation: generation,
        sessionSnapshot: sessionSnapshot
      )
    else {
      Logger.debug("[MemoryOptimization] 忽略过期的自动检查结果")
      return
    }

    automaticEnabled = result
    applyCurrentMode()
    if isError {
      Logger.error("[MemoryOptimization] \(reason)")
    } else {
      Logger.debug("[MemoryOptimization] \(reason)")
    }
  }

  private func canPublishAutomaticResult(
    generation: Int,
    sessionSnapshot: APIServiceSessionSnapshot
  ) -> Bool {
    Self.canPublishAutomaticResult(
      mode: mode,
      generation: generation,
      currentGeneration: automaticEvaluationGeneration,
      sessionIsCurrent: sessionIsCurrent(sessionSnapshot)
    )
  }

  private func cancelAutomaticEvaluation() {
    automaticEvaluationTask?.cancel()
    automaticEvaluationTask = nil
    automaticEvaluationGeneration &+= 1
  }

  private func applyCurrentMode() {
    isEnabled = Self.resolvedEnabledState(mode: mode, automaticEnabled: automaticEnabled)
  }

  /// 禁用 URLCache 请求 MP 公开设置接口，用 URLSession 指标测量请求发出到响应首字节；不是 ICMP Ping。
  private nonisolated static func measureServerLatency(
    baseURL: String
  ) async -> (latency: TimeInterval, remoteAddress: String)? {
    let normalizedBaseURL = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
    guard let url = URL(string: "\(normalizedBaseURL)/api/v1/system/global?token=moviepilot") else {
      return nil
    }
    var request = URLRequest(url: url)
    request.cachePolicy = .reloadIgnoringLocalCacheData
    request.timeoutInterval = 2

    let metrics = MemoryOptimizationProbeMetrics()
    do {
      let (_, response) = try await URLSession.shared.data(for: request, delegate: metrics)
      guard let response = response as? HTTPURLResponse,
        (200...299).contains(response.statusCode)
      else {
        return nil
      }
      return metrics.result
    } catch {
      return nil
    }
  }

  nonisolated static func canPublishAutomaticResult(
    mode: MemoryOptimizationMode,
    generation: Int,
    currentGeneration: Int,
    sessionIsCurrent: Bool
  ) -> Bool {
    mode == .automatic && generation == currentGeneration && sessionIsCurrent
  }

  nonisolated static func isAutomaticLatencyAcceptable(_ latency: TimeInterval) -> Bool {
    latency < maximumAutomaticLatency
  }

  nonisolated static func resolvedEnabledState(
    mode: MemoryOptimizationMode,
    automaticEnabled: Bool
  ) -> Bool {
    switch mode {
    case .automatic:
      return automaticEnabled
    case .enabled:
      return true
    case .disabled:
      return false
    }
  }

  nonisolated static func isLocalAddress(_ address: String) -> Bool {
    let addressWithoutScope = String(address.split(separator: "%", maxSplits: 1)[0]).lowercased()

    if addressWithoutScope.contains(".") {
      let ipv4 =
        addressWithoutScope.split(separator: ":").last.map(String.init) ?? addressWithoutScope
      let parts = ipv4.split(separator: ".").compactMap { UInt8($0) }
      guard parts.count == 4 else { return false }

      return parts[0] == 10
        || parts[0] == 127
        || (parts[0] == 169 && parts[1] == 254)
        || (parts[0] == 172 && (16...31).contains(parts[1]))
        || (parts[0] == 192 && parts[1] == 168)
        || (parts[0] == 100 && (64...127).contains(parts[1]))
    }

    if addressWithoutScope == "::1" {
      return true
    }
    guard let firstGroup = addressWithoutScope.split(separator: ":").first,
      let value = UInt16(firstGroup, radix: 16)
    else {
      return false
    }
    return value & 0xFE00 == 0xFC00 || value & 0xFFC0 == 0xFE80
  }
}
