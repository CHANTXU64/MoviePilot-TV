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
    var framer = SSEFramer()
    let decoder = JSONDecoder()
    for try await byte in bytes {
      try Task.checkCancellation()
      if let payload = framer.consume(byte: byte) {
        let event = try decoder.decode(Event.self, from: Data(payload.utf8))
        try await receive(event)
      }
    }
    try Task.checkCancellation()
    if let tail = framer.flush() {
      let event = try decoder.decode(Event.self, from: Data(tail.utf8))
      try await receive(event)
    }
  }
}
