import Foundation

/// SSE 事件组帧器（F-101）。
///
/// SSE 规范允许一个事件由**多条** `data:` 行组成，并以一个空行作为事件结束标志；
/// 同一事件的多行内容需要以 `\n` 拼接后再解析。生产端 `APIService.streamSSE` 与
/// `BackendCompatibilityTests` 的兼容探针此前都按物理行立即解码，遇到这种合法事件
/// 会把每一行单独当 JSON 解、必然失败，并让整条流抛出终止（不是少收一个事件，
/// 是整条流断掉：搜索会掉到同步接口重试，AI 进度监控直接失败）。
///
/// **本类型必须自己按字节切行，不能用 `URLSession.AsyncBytes.lines`。**
/// 这是本项修复的关键约束：`AsyncLineSequence` 会**丢弃空行**，空行根本送不到解析器
/// 手里（已用真实 SSE 流复核：`data: a\n\n data: b\n\n` 只取出两行，分隔空行消失）。
/// 后果是事件边界在取行阶段就已丢失 —— 两个独立事件 `data: a\n\n data: b\n\n` 与一个
/// 多行事件 `data: a\n data: b\n\n` 经 `.lines` 之后都是 `["data: a", "data: b"]`，
/// 二者不可区分。因此「在 `.lines` 之上补一层累积」不但修不好多行事件，反而会把
/// 原本正确的**连续单行事件**合并成一个非法载荷而导致全线报错；只有拿到空行才能成帧。
///
/// 本类型只负责「按事件边界累积与合并」，不做 JSON 解码、不判定业务语义 ——
/// 生产解析器与兼容探针因此复用同一条规则，而不是各写一份。
///
/// 行尾按规范三种全收：`CRLF`、`LF`、`CR`。此前只认 `LF`，纯 `CR` 的流会被攒成一整行，
/// 到流结束时只剩一个畸形载荷交给 `JSONDecoder`，整条流报错。流开头的 UTF-8 BOM 也只
/// 忽略一次 —— 漏掉它会让第一行不满足 `hasPrefix("data:")`，第一个事件的数据被整条丢弃。
///
/// 与规范的唯一偏差：流结束时若仍有未以空行收尾的挂起事件，`flush()` 会交付它
/// 而不是丢弃（规范建议丢弃）。本项目此前就是「data 行一到即处理」，断线前最后
/// 一个事件（可能是 `done`）一直收得到；严格丢弃会静默降低容错，故保留该行为。
nonisolated struct SSEFramer {
  /// 当前事件已累积的 `data` 字段值（尚未成帧）。
  private var pendingDataLines: [String] = []

  /// 当前尚未遇到换行的半行内容（原始字节）。
  private var currentLine: [UInt8] = []

  /// 上一个字节是 `CR`：紧随其后的 `LF` 属于同一个 CRLF 行尾，不再单独切一次行。
  private var lastByteWasCR = false

  /// 流开头的 BOM 是否已了结（识别到并丢弃，或确认不是 BOM）。
  private var bomResolved = false

  /// 已匹配上的 BOM 前缀长度（`EF` / `EF BB` / `EF BB BF`）。
  private var bomMatchedBytes = 0

  /// UTF-8 BOM。只允许出现在流的最开头，且只忽略一次。
  private static let byteOrderMark: [UInt8] = [0xEF, 0xBB, 0xBF]

  /// 送入流中的一个字节；该字节使某个事件成帧时返回合并后的 data 内容，否则返回 nil。
  mutating func consume(byte: UInt8) -> String? {
    // 流开头的 BOM 必须丢掉，否则第一行变成 `\u{FEFF}data: ...`，
    // `hasPrefix("data:")` 不成立，**第一个事件的数据会被整条丢弃**。
    // 只在开头认一次：解析出结果后本分支不再进入。
    if !bomResolved {
      if byte == Self.byteOrderMark[bomMatchedBytes] {
        bomMatchedBytes += 1
        if bomMatchedBytes == Self.byteOrderMark.count {
          bomResolved = true
        }
        return nil
      }
      // 不是 BOM：把已经吃进来的前缀原样补回再按正常流程走。
      // 前缀只可能是 `[0xEF]` 或 `[0xEF, 0xBB]`，都够不上行尾，故这里不会成帧。
      bomResolved = true
      currentLine.append(contentsOf: Self.byteOrderMark.prefix(bomMatchedBytes))
      bomMatchedBytes = 0
    }

    return consumeBody(byte: byte)
  }

  /// 已排除 BOM 干扰的按字节切行。
  private mutating func consumeBody(byte: UInt8) -> String? {
    // CRLF 里的 `LF` 紧跟在 `CR` 之后，属于**同一个**行尾。若在这里再切一次，
    // 会凭空多出一个空行，把事件提前截断。
    if lastByteWasCR {
      lastByteWasCR = false
      if byte == 0x0A { return nil }
    }

    // 规范允许 `CRLF`、`LF`、`CR` 三种行尾，三者等价。
    // UTF-8 的多字节序列里不会出现 0x0A / 0x0D（续字节均 ≥ 0x80），故切行不会切开一个字符。
    guard byte == 0x0A || byte == 0x0D else {
      currentLine.append(byte)
      return nil
    }
    if byte == 0x0D { lastByteWasCR = true }

    let line = String(decoding: currentLine, as: UTF8.self)
    currentLine.removeAll(keepingCapacity: true)
    return consume(line: line)
  }

  /// 送入一行（不含行尾换行符）。
  /// 该行构成事件结尾时返回合并后的 data 内容，否则返回 nil。
  mutating func consume(line: String) -> String? {
    // 兼容 CRLF：行尾的单个 `\r` 不属于内容。
    let line = line.hasSuffix("\r") ? String(line.dropLast()) : line

    // 空行 = 事件结束。这一行能走到这里，正是因为调用方没有用 `.lines`。
    if line.isEmpty {
      return flush()
    }

    // 只认 `data` 字段。`event:` / `id:` / `retry:` 与以 `:` 开头的注释行（心跳）
    // 一律忽略 —— 与改动前的 `hasPrefix("data:")` 过滤、其余行直接丢弃一致。
    guard line.hasPrefix("data:") else { return nil }

    var value = line.dropFirst("data:".count)
    // 规范：冒号后若紧跟一个空格，只去掉那一个；其余空白属于数据本身。
    if value.hasPrefix(" ") { value = value.dropFirst() }
    pendingDataLines.append(String(value))
    return nil
  }

  /// 交付当前挂起事件；无挂起内容时返回 nil。
  mutating func flush() -> String? {
    // 流可能停在一个没有换行收尾的半行上，先把这半行补进来再交付。
    if !currentLine.isEmpty {
      let line = String(decoding: currentLine, as: UTF8.self)
      currentLine.removeAll(keepingCapacity: true)
      if let payload = consume(line: line) { return payload }
    }

    guard !pendingDataLines.isEmpty else { return nil }
    defer { pendingDataLines.removeAll(keepingCapacity: true) }
    return pendingDataLines.joined(separator: "\n")
  }
}
