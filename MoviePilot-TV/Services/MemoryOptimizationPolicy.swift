import Combine
import Darwin
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

/// 为所有内存优化提供单一开关。自动模式在每次进入 App 及切回自动时重新判断。
@MainActor
final class MemoryOptimizationPolicy: ObservableObject {
  static let shared = MemoryOptimizationPolicy()

  @Published var mode: MemoryOptimizationMode {
    didSet {
      guard mode != oldValue else { return }
      UserDefaults.standard.set(mode.rawValue, forKey: Self.modeKey)
      applyCurrentMode()
      if mode == .automatic {
        Task { await refreshAutomaticDecision() }
      }
    }
  }

  @Published private(set) var isEnabled: Bool
  @Published private(set) var automaticEnabled = false

  private static let modeKey = "memoryOptimizationMode"
  private nonisolated static let maximumAutomaticLatency: TimeInterval = 0.010

  private init() {
    let storedMode = UserDefaults.standard.string(forKey: Self.modeKey)
      .flatMap(MemoryOptimizationMode.init(rawValue:)) ?? .automatic
    mode = storedMode
    isEnabled = storedMode == .enabled
  }

  /// 从手动模式切回自动时刷新服务器设置，再重新判断一次。
  private func refreshAutomaticDecision() async {
    let apiService = APIService.shared
    let sessionSnapshot = apiService.sessionSnapshot()
    do {
      _ = try await apiService.fetchSettings()
      guard apiService.isSessionUnchanged(from: sessionSnapshot) else { return }
      await evaluateAutomatically(
        baseURL: sessionSnapshot.baseURL,
        settingsLoaded: true,
        imageCacheAvailable: apiService.useImageCache
      )
    } catch {
      guard apiService.isSessionUnchanged(from: sessionSnapshot) else { return }
      await evaluateAutomatically(
        baseURL: sessionSnapshot.baseURL,
        settingsLoaded: false,
        imageCacheAvailable: false
      )
    }
  }

  /// 使用本次进入 App 时获取的服务器设置重新判断。
  func evaluateAutomatically(
    baseURL: String,
    settingsLoaded: Bool,
    imageCacheAvailable: Bool
  ) async {
    guard mode == .automatic else { return }

    Logger.debug(
      "[MemoryOptimization] 自动检查：服务器设置=\(settingsLoaded ? "已读取" : "读取失败")，图片缓存=\(imageCacheAvailable ? "可用" : "不可用")"
    )

    guard settingsLoaded else {
      finishAutomaticEvaluation(
        false,
        reason: "服务器设置读取失败",
        isError: true
      )
      return
    }
    guard imageCacheAvailable else {
      finishAutomaticEvaluation(false, reason: "MP 图片缓存不可用")
      return
    }
    guard let host = URL(string: baseURL)?.host, !host.isEmpty else {
      finishAutomaticEvaluation(
        false,
        reason: "服务器地址无效",
        isError: true
      )
      return
    }

    let addresses = await Task.detached(priority: .utility) {
      Self.resolvedAddresses(for: host)
    }.value
    Logger.debug(
      "[MemoryOptimization] DNS 解析：\(host) -> \(addresses.sorted().joined(separator: ", "))"
    )
    guard !addresses.isEmpty else {
      finishAutomaticEvaluation(
        false,
        reason: "服务器地址解析失败",
        isError: true
      )
      return
    }
    let addressesAreLocal = addresses.allSatisfy(Self.isLocalAddress)
    Logger.debug("[MemoryOptimization] IP 类型：\(addressesAreLocal ? "全部为内网地址" : "包含公网地址")")
    guard addressesAreLocal else {
      finishAutomaticEvaluation(false, reason: "服务器不是内网地址")
      return
    }

    guard let latency = await Self.measureServerLatency(baseURL: baseURL) else {
      finishAutomaticEvaluation(
        false,
        reason: "服务器延迟测试失败",
        isError: true
      )
      return
    }
    let latencyInMilliseconds = latency * 1_000
    Logger.debug(
      String(
        format: "[MemoryOptimization] HTTP 往返延迟：%.1fms（自动开启阈值 < %.1fms）",
        latencyInMilliseconds,
        Self.maximumAutomaticLatency * 1_000
      )
    )
    guard Self.isAutomaticLatencyAcceptable(latency) else {
      finishAutomaticEvaluation(
        false,
        reason: String(format: "服务器延迟 %.1fms，不启用", latencyInMilliseconds)
      )
      return
    }

    finishAutomaticEvaluation(
      true,
      reason: String(format: "服务器延迟 %.1fms，启用", latencyInMilliseconds)
    )
  }

  private func finishAutomaticEvaluation(
    _ result: Bool,
    reason: String,
    isError: Bool = false
  ) {
    automaticEnabled = result
    applyCurrentMode()
    if isError {
      Logger.error("[MemoryOptimization] \(reason)")
    } else {
      Logger.debug("[MemoryOptimization] \(reason)")
    }
  }

  private func applyCurrentMode() {
    isEnabled = Self.resolvedEnabledState(mode: mode, automaticEnabled: automaticEnabled)
  }

  private nonisolated static func resolvedAddresses(for host: String) -> [String] {
    var hints = addrinfo()
    hints.ai_flags = AI_ADDRCONFIG
    hints.ai_family = AF_UNSPEC
    hints.ai_socktype = SOCK_STREAM

    var result: UnsafeMutablePointer<addrinfo>?
    guard getaddrinfo(host, nil, &hints, &result) == 0, let first = result else {
      return []
    }
    defer { freeaddrinfo(first) }

    var addresses = Set<String>()
    var current: UnsafeMutablePointer<addrinfo>? = first
    while let info = current {
      var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
      if getnameinfo(
        info.pointee.ai_addr,
        info.pointee.ai_addrlen,
        &buffer,
        socklen_t(buffer.count),
        nil,
        0,
        NI_NUMERICHOST
      ) == 0 {
        addresses.insert(
          String(
            decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) },
            as: UTF8.self
          )
        )
      }
      current = info.pointee.ai_next
    }
    return Array(addresses)
  }

  /// 禁用 URLCache 请求 MP 公开设置接口，用单调时钟测量一次完整 HTTP 往返；不是 ICMP Ping。
  private nonisolated static func measureServerLatency(baseURL: String) async -> TimeInterval? {
    let normalizedBaseURL = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
    guard let url = URL(string: "\(normalizedBaseURL)/api/v1/system/global?token=moviepilot") else {
      return nil
    }
    var request = URLRequest(url: url)
    request.cachePolicy = .reloadIgnoringLocalCacheData
    request.timeoutInterval = 2

    let start = ContinuousClock.now
    do {
      let (_, response) = try await URLSession.shared.data(for: request)
      guard let response = response as? HTTPURLResponse,
        (200...299).contains(response.statusCode)
      else {
        return nil
      }
      let components = start.duration(to: .now).components
      return TimeInterval(components.seconds)
        + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
    } catch {
      return nil
    }
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
      let ipv4 = addressWithoutScope.split(separator: ":").last.map(String.init) ?? addressWithoutScope
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
