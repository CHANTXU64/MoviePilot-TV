import Foundation

/// 在后台读取和解码 SSE，仅在完整事件的交付边界返回 MainActor。
nonisolated enum SSEEventReader {
  // 工程启用了 NonisolatedNonsendingByDefault；仅写 nonisolated 仍可能继承调用者执行器。
  // @concurrent 显式离开 MainActor，且保留调用任务的取消传播，无需另建 detached task。
  @concurrent
  static func read<Event: Decodable & Sendable>(
    from bytes: URLSession.AsyncBytes,
    as _: Event.Type,
    receive: @MainActor @Sendable (Event) throws -> Void
  ) async throws {
    try await consume(from: bytes, as: Event.self, maximumEventBytes: nil) { event, _ in
      try receive(event)
    }
  }

  /// await 交付提供背压；资源搜索不经过无界 AsyncThrowingStream 队列。
  @concurrent
  static func consume<Event: Decodable & Sendable>(
    from bytes: URLSession.AsyncBytes,
    as _: Event.Type,
    maximumEventBytes: (@MainActor @Sendable () throws -> Int)? = nil,
    configureDecoder: (@Sendable (JSONDecoder, Int?, Int) -> Void)? = nil,
    receive: @MainActor @Sendable (Event, Int) async throws -> Void
  ) async throws {
    var frameBytes = 0
    var frameLimit: Int?
    // 有界读取不保留历史大帧的数组容量，以免预算收紧后仍占用旧缓冲。
    var framer = SSEFramer(reusesBuffers: maximumEventBytes == nil)
    let decoder = JSONDecoder()
    for try await byte in bytes {
      try Task.checkCancellation()
      // 上一帧已消费后才取下一帧预算；逐字节读取仍在后台执行。
      if frameBytes == 0 {
        frameLimit = try await maximumEventBytes?()
      }
      frameBytes += 1
      if let frameLimit, frameBytes > frameLimit {
        throw ResourceSearchFailure.capacity
      }
      if let payload = framer.consume(byte: byte) {
        configureDecoder?(decoder, frameLimit, frameBytes)
        let event = try decoder.decode(Event.self, from: Data(payload.utf8))
        try await receive(event, frameBytes)
        frameBytes = 0
      }
    }
    try Task.checkCancellation()
    if let tail = framer.flush() {
      configureDecoder?(decoder, frameLimit, frameBytes)
      let event = try decoder.decode(Event.self, from: Data(tail.utf8))
      try await receive(event, frameBytes)
    }
  }
}
