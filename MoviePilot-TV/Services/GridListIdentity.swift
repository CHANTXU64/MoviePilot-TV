import Foundation

/// Grid 逻辑列表的稳定身份。UUID 标识数据源，generation 标识其当前内容代际。
/// 普通尾部追加保持 generation；reset/refresh 或新数据源推进 generation，以拒绝迟到旧事件。
struct GridListIdentity: Hashable, Sendable {
  let id: UUID
  let generation: UInt64

  init(id: UUID, generation: UInt64) {
    self.id = id
    self.generation = generation
  }

  @MainActor
  static func make(id: UUID = UUID()) -> GridListIdentity {
    GridListIdentity(id: id, generation: GridListIdentitySequence.next())
  }

  @MainActor
  func advanced() -> GridListIdentity {
    GridListIdentity.make(id: id)
  }
}

@MainActor
private enum GridListIdentitySequence {
  private static var generation: UInt64 = 0

  static func next() -> UInt64 {
    generation &+= 1
    return generation
  }
}
