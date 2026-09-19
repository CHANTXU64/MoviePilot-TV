import Foundation

/// 按 key 合并在途请求、最新者胜出的内存缓存。会话/代际失效与“旧结果不得回写”都在这里统一处理，
/// 调用方只提供 key、加载闭包和自身的校验（会话快照、任务取消）。
///
/// - 普通读取：命中未过期缓存直接返回；否则加入同 key 仍在运行的加载，没有才发起新加载。
/// - 强制刷新：跳过缓存发起新加载，并把同 key 的上一个加载（包括已完成但仍有等待者未返回的）
///   标记为被它取代。被取代加载的成功或失败既不写缓存，也不返回；它的等待者沿取代链等待最新加载，
///   拿到最新加载的成功或失败。
/// - `invalidateAll()`：推进代际并清空缓存。在途加载不取消（可能正在执行重登等不可中断流程），
///   但其成功结果不再写缓存，等待者按新代际重新读取；其失败照常抛给等待者。
/// - 未被取代的加载失败时直接抛给它的全部等待者，不写缓存、不自动重试。
/// - 每次读取前与拿到成功结果后都执行调用方的 `validate`；它抛错时立即停止，不返回任何值。
@MainActor
final class CoalescingCache<Key: Hashable & Sendable, Value: Sendable> {
  private final class FlightState {
    let generation: UInt64
    /// 取代本次加载的强制刷新。
    var successor: Flight?
    var isFinished = false
    /// 尚未恢复的等待者数。归零且已完成后才从 `latestFlights` 移除，
    /// 保证完成后、等待者恢复前开始的强刷仍能取代它。
    var waiterCount = 0

    init(generation: UInt64) {
      self.generation = generation
    }
  }

  private struct Flight {
    let state: FlightState
    let task: Task<Result<Value, Error>, Never>
  }

  private struct Entry {
    let value: Value
    var expiresAt: Date
  }

  private let ttl: TimeInterval
  private let capacity: Int
  private let renewsTTLOnAccess: Bool
  private let now: () -> Date
  private var entries: [Key: Entry] = [:]
  /// 每个 key 最近发起的加载；运行中或仍有等待者未返回时保留。
  private var latestFlights: [Key: Flight] = [:]
  private var generation: UInt64 = 0

  init(
    ttl: TimeInterval,
    capacity: Int,
    renewsTTLOnAccess: Bool = true,
    now: @escaping () -> Date = Date.init
  ) {
    self.ttl = ttl
    self.capacity = max(1, capacity)
    self.renewsTTLOnAccess = renewsTTLOnAccess
    self.now = now
  }

  func value(
    for key: Key,
    forceRefresh: Bool = false,
    validate: () throws -> Void,
    load: @escaping @MainActor () async throws -> Value
  ) async throws -> Value {
    var startsNewLoad = forceRefresh
    while true {
      try validate()
      if !startsNewLoad, let cached = cachedValue(for: key) {
        return cached
      }

      var flight: Flight
      if !startsNewLoad, let running = latestFlights[key], !running.state.isFinished {
        flight = running
      } else {
        flight = startFlight(for: key, supersedesLatest: startsNewLoad, load: load)
      }
      startsNewLoad = false

      var result = await awaitResult(of: flight, key: key)
      while let successor = flight.state.successor {
        flight = successor
        result = await awaitResult(of: flight, key: key)
      }

      switch result {
      case .success(let value):
        try validate()
        guard flight.state.generation == generation else { continue }
        return value
      case .failure(let error):
        // 共享加载不随单个等待者取消；已取消的等待者只收到取消，不收到共享加载的业务错误。
        try Task.checkCancellation()
        if error is CancellationError, flight.state.generation != generation { continue }
        throw error
      }
    }
  }

  /// 推进代际并清空缓存。用于会话切换或会改变结果的 mutation 之后。
  func invalidateAll() {
    generation &+= 1
    entries.removeAll()
    latestFlights.removeAll()
  }

  private func cachedValue(for key: Key) -> Value? {
    guard var entry = entries[key] else { return nil }
    let currentDate = now()
    guard currentDate <= entry.expiresAt else {
      entries.removeValue(forKey: key)
      return nil
    }
    if renewsTTLOnAccess {
      entry.expiresAt = currentDate.addingTimeInterval(ttl)
      entries[key] = entry
    }
    return entry.value
  }

  private func startFlight(
    for key: Key,
    supersedesLatest: Bool,
    load: @escaping @MainActor () async throws -> Value
  ) -> Flight {
    let state = FlightState(generation: generation)
    let task = Task { [weak self] () -> Result<Value, Error> in
      let result: Result<Value, Error>
      do {
        result = .success(try await load())
      } catch {
        result = .failure(error)
      }
      self?.finish(key: key, state: state, result: result)
      return result
    }
    let flight = Flight(state: state, task: task)
    if supersedesLatest {
      latestFlights[key]?.state.successor = flight
    }
    latestFlights[key] = flight
    return flight
  }

  private func awaitResult(of flight: Flight, key: Key) async -> Result<Value, Error> {
    flight.state.waiterCount += 1
    let result = await flight.task.value
    flight.state.waiterCount -= 1
    releaseIfSettled(flight.state, key: key)
    return result
  }

  private func finish(key: Key, state: FlightState, result: Result<Value, Error>) {
    state.isFinished = true
    releaseIfSettled(state, key: key)
    guard state.successor == nil, state.generation == generation,
      case .success(let value) = result
    else { return }
    store(value, for: key)
  }

  private func releaseIfSettled(_ state: FlightState, key: Key) {
    guard state.isFinished, state.waiterCount == 0,
      latestFlights[key]?.state === state
    else { return }
    latestFlights.removeValue(forKey: key)
  }

  private func store(_ value: Value, for key: Key) {
    if entries[key] == nil, entries.count >= capacity,
      let evictedKey = entries.min(by: { $0.value.expiresAt < $1.value.expiresAt })?.key
    {
      entries.removeValue(forKey: evictedKey)
    }
    entries[key] = Entry(value: value, expiresAt: now().addingTimeInterval(ttl))
  }
}
