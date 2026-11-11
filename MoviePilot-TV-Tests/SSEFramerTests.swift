import XCTest

@testable import MoviePilot_TV

/// F-101 回归：SSE 必须按**事件**组帧，而不是按物理行解码。
///
/// 规范允许一个事件由多条 `data:` 行组成、以空行结束，多行内容以 `\n` 拼接后
/// 才是一个完整载荷。改动前 `streamSSE` 与兼容探针都是「一行一个 JSON」，
/// 遇到合法多行事件会逐行解码失败并让整条流抛出终止。
final class SSEFramerTests: XCTestCase {

  private struct Payload: Decodable, Equatable {
    let type: String
    let items: [Int]?
  }

  // MARK: - 单行（改动前唯一覆盖的形态，必须不变）

  func testSingleDataLineEventIsDeliveredOnBlankLine() {
    var framer = SSEFramer()

    XCTAssertNil(framer.consume(line: #"data: {"type":"start"}"#))
    XCTAssertEqual(framer.consume(line: ""), #"{"type":"start"}"#)
  }

  /// 阴性对照：单行事件的**内容**在改动前后必须一致（不锁定交付时机，故两种实现都通过）。
  func testSingleLineEventContentIsUnchanged() {
    var framer = SSEFramer()

    let payload = framer.consume(line: #"data: {"type":"start","items":[1,2]}"#) ?? framer.flush()
    XCTAssertEqual(payload, #"{"type":"start","items":[1,2]}"#)
  }

  func testDataWithoutSpaceAfterColonIsAccepted() {
    var framer = SSEFramer()

    XCTAssertNil(framer.consume(line: #"data:{"type":"start"}"#))
    XCTAssertEqual(framer.consume(line: ""), #"{"type":"start"}"#)
  }

  func testConsecutiveEventsAreFramedSeparately() {
    var framer = SSEFramer()

    XCTAssertNil(framer.consume(line: #"data: {"type":"a"}"#))
    XCTAssertEqual(framer.consume(line: ""), #"{"type":"a"}"#)
    XCTAssertNil(framer.consume(line: #"data: {"type":"b"}"#))
    XCTAssertEqual(framer.consume(line: ""), #"{"type":"b"}"#)
  }

  // MARK: - 多 data 行（本项修复的核心）

  func testMultipleDataLinesAreJoinedWithNewline() {
    var framer = SSEFramer()

    XCTAssertNil(framer.consume(line: #"data: {"type":"start","#))
    XCTAssertNil(framer.consume(line: #"data: "items":[1,2]}"#))
    XCTAssertEqual(framer.consume(line: ""), "{\"type\":\"start\",\n\"items\":[1,2]}")
  }

  /// 修复前每一行都会单独解码失败；拼接后必须是合法 JSON 且能解出完整事件。
  func testMultiLineEventDecodesAsOneEvent() throws {
    var framer = SSEFramer()

    XCTAssertNil(framer.consume(line: #"data: {"type":"done","#))
    XCTAssertNil(framer.consume(line: #"data: "items":[1,2]}"#))
    let payload = try XCTUnwrap(framer.consume(line: ""))

    let event = try JSONDecoder().decode(Payload.self, from: Data(payload.utf8))
    XCTAssertEqual(event, Payload(type: "done", items: [1, 2]))
  }

  // MARK: - 应当被忽略的行

  func testCommentsAndUnknownFieldsAreIgnored() {
    var framer = SSEFramer()

    XCTAssertNil(framer.consume(line: ": keep-alive"))
    XCTAssertNil(framer.consume(line: "event: message"))
    XCTAssertNil(framer.consume(line: "id: 42"))
    XCTAssertNil(framer.consume(line: "retry: 1000"))
    // 忽略的行不应影响后续事件成帧。
    XCTAssertNil(framer.consume(line: #"data: {"type":"start"}"#))
    XCTAssertEqual(framer.consume(line: ""), #"{"type":"start"}"#)
  }

  func testBlankLineWithoutPendingDataReturnsNil() {
    var framer = SSEFramer()

    XCTAssertNil(framer.consume(line: ""))
    XCTAssertNil(framer.consume(line: ""))
  }

  // MARK: - 收尾与空白规则

  func testUnterminatedEventIsDeliveredByFlush() {
    var framer = SSEFramer()

    XCTAssertNil(framer.consume(line: #"data: {"type":"done"}"#))
    XCTAssertEqual(framer.flush(), #"{"type":"done"}"#)
  }

  func testFlushAfterTerminatedEventReturnsNil() {
    var framer = SSEFramer()

    XCTAssertNil(framer.consume(line: #"data: {"type":"done"}"#))
    XCTAssertEqual(framer.consume(line: ""), #"{"type":"done"}"#)
    XCTAssertNil(framer.flush())
  }

  /// 规范：冒号后只吃掉**一个**空格，其余空白属于数据本身。
  func testOnlyOneLeadingSpaceAfterColonIsStripped() {
    var framer = SSEFramer()

    XCTAssertNil(framer.consume(line: "data:  padded"))
    XCTAssertEqual(framer.flush(), " padded")
  }

  func testCRLFLineEndingsAreHandled() {
    var framer = SSEFramer()

    XCTAssertNil(framer.consume(line: "data: {\"type\":\"start\"}\r"))
    XCTAssertEqual(framer.consume(line: "\r"), #"{"type":"start"}"#)
  }

  // MARK: - 字节层（事件边界只能在这一层拿到）

  /// 按字节喂入整段流，返回成帧出的全部载荷（与生产端 `streamSSE` 的遍历方式一致）。
  private func frame(_ text: String) -> [String] {
    var framer = SSEFramer()
    var payloads: [String] = []
    for byte in Array(text.utf8) {
      if let payload = framer.consume(byte: byte) {
        payloads.append(payload)
      }
    }
    if let tail = framer.flush() {
      payloads.append(tail)
    }
    return payloads
  }

  /// 回归核心：连续两个**独立**的单行事件必须成帧成两个载荷。
  /// 若改用 `bytes.lines` 取行，空行会被吞掉，这里会合并成一个非法载荷 —— 这正是
  /// 本项目一度全线报错的原因，故本用例锁死该行为。
  func testConsecutiveSingleLineEventsStaySeparateThroughByteStream() {
    let payloads = frame(#"data: {"type":"a"}"# + "\n\n" + #"data: {"type":"b"}"# + "\n\n")

    XCTAssertEqual(payloads, [#"{"type":"a"}"#, #"{"type":"b"}"#])
  }

  /// 最后一个事件没有空行收尾时，也不得与上一个事件粘连。
  func testMissingTrailingBlankLineStillYieldsSeparateEvents() {
    let payloads = frame(#"data: {"type":"a"}"# + "\n\n" + #"data: {"type":"b"}"# + "\n")

    XCTAssertEqual(payloads, [#"{"type":"a"}"#, #"{"type":"b"}"#])
  }

  /// 规范允许一个事件由多条 `data:` 行组成；经字节层必须合并成**一个**载荷。
  func testMultiLineEventThroughByteStreamDecodesAsOneEvent() throws {
    let payloads = frame("data: {\"type\":\"done\",\ndata: \"items\":[1,2]}\n\n")

    XCTAssertEqual(payloads, ["{\"type\":\"done\",\n\"items\":[1,2]}"])
    let event = try JSONDecoder().decode(Payload.self, from: Data(XCTUnwrap(payloads.first).utf8))
    XCTAssertEqual(event, Payload(type: "done", items: [1, 2]))
  }

  /// 同一段字节，两种形态必须给出**不同**的成帧结果 —— 这正是 `.lines` 做不到的区分。
  func testConsecutiveEventsAndMultiLineEventAreDistinguishable() {
    let separate = frame(#"data: {"type":"a"}"# + "\n\n" + #"data: {"type":"b"}"# + "\n\n")
    let joined = frame(#"data: {"type":"a"}"# + "\n" + #"data: {"type":"b"}"# + "\n\n")

    XCTAssertEqual(separate, [#"{"type":"a"}"#, #"{"type":"b"}"#])
    XCTAssertEqual(joined, ["{\"type\":\"a\"}\n{\"type\":\"b\"}"])
  }

  func testCRLFSeparatedEventsThroughByteStream() {
    let payloads = frame("data: {\"type\":\"a\"}\r\n\r\ndata: {\"type\":\"b\"}\r\n\r\n")

    XCTAssertEqual(payloads, [#"{"type":"a"}"#, #"{"type":"b"}"#])
  }

  /// 多字节 UTF-8 字符可能被异步字节流从中间切开，按 `\n` 切行不得把字符切坏。
  func testMultibyteCharactersSurviveByteSplitting() {
    let payloads = frame("data: {\"type\":\"append\",\"text\":\"流浪地球\"}\n\n")

    XCTAssertEqual(payloads, [#"{"type":"append","text":"流浪地球"}"#])
  }

  /// 注释行（心跳）与其后的空行都不应产生载荷。
  func testHeartbeatsAndCommentsProduceNoPayloads() {
    let payloads = frame(": ping\n\ndata: {\"type\":\"a\"}\n\n: ping\n\n")

    XCTAssertEqual(payloads, [#"{"type":"a"}"#])
  }

  /// 流停在半行上（无换行收尾）时，`flush()` 必须把它交出来。
  func testFlushDeliversResidualLineWithoutNewline() {
    var framer = SSEFramer()

    for byte in Array(#"data: {"type":"done"}"#.utf8) {
      XCTAssertNil(framer.consume(byte: byte))
    }
    XCTAssertEqual(framer.flush(), #"{"type":"done"}"#)
  }

  // MARK: - 纯 CR 行尾（外部审查点名的协议兼容缺口之一）

  /// 规范里 `CRLF`、`LF`、`CR` 三种行尾等价。修复前只认 `0x0A`，纯 `CR` 的流会被整段
  /// 攒成一行，流结束时又只砍掉一个尾部 `\r`，最后只交出**一个畸形载荷**交给
  /// `JSONDecoder` —— 不是少一个事件，是整条流报错。`APIService` 与兼容探针走的都是
  /// `consume(byte:)`，故这里按字节喂。
  func testCROnlyLineEndingsFrameEventsSeparately() {
    let payloads = frame("data: {\"type\":\"a\"}\r\rdata: {\"type\":\"b\"}\r\r")

    XCTAssertEqual(payloads, [#"{"type":"a"}"#, #"{"type":"b"}"#])
    XCTAssertFalse(payloads.contains { $0.contains("\r") }, "行尾字符不得混进载荷")
  }

  /// **阴性对照**：`CRLF` 是**一个**行尾而不是两个。若 `CR` 与 `LF` 各切一次，中间会凭空
  /// 多出一个空行，把下面这个合法的多行事件提前截断成两个载荷。
  ///
  /// 本条修复前后都通过 —— 修复前 `consume(line:)` 会剥掉行尾那个 `\r`，CRLF 本就是对的；
  /// 它守的是**新加的字节层 CR 处理**别把 CRLF 拆成两次断行。
  func testCRLFIsOneLineEndingNotTwo() {
    let payloads = frame("data: {\"type\":\"a\",\r\ndata: \"items\":[1,2]}\r\n\r\n")

    XCTAssertEqual(payloads, ["{\"type\":\"a\",\n\"items\":[1,2]}"])
  }

  /// 三种行尾混用时同样要正确成帧。
  func testMixedLineEndingsFrameCorrectly() {
    let payloads = frame(
      "data: {\"type\":\"a\"}\r\rdata: {\"type\":\"b\"}\n\ndata: {\"type\":\"c\"}\r\n\r\n")

    XCTAssertEqual(payloads, [#"{"type":"a"}"#, #"{"type":"b"}"#, #"{"type":"c"}"#])
  }

  // MARK: - 流开头的 BOM（外部审查点名的协议兼容缺口之二）

  /// 上游网关/代理可能给流加 UTF-8 BOM。修复前第一行变成 `\u{FEFF}data: ...`，
  /// `hasPrefix("data:")` 不成立，**第一个事件的数据被整条丢弃**（后面的事件不受影响，
  /// 所以线上表现为"偶发少一个事件"）。
  func testLeadingByteOrderMarkIsIgnored() {
    let payloads = frame("\u{FEFF}data: {\"type\":\"a\"}\n\ndata: {\"type\":\"b\"}\n\n")

    XCTAssertEqual(payloads, [#"{"type":"a"}"#, #"{"type":"b"}"#])
  }

  /// BOM 分支不得影响其后的取行：带 BOM 的多行事件仍要合并成**一个**载荷。
  func testMultiLineEventAfterByteOrderMarkIsStillJoined() {
    let payloads = frame("\u{FEFF}data: {\"type\":\"done\",\ndata: \"items\":[1,2]}\n\n")

    XCTAssertEqual(payloads, ["{\"type\":\"done\",\n\"items\":[1,2]}"])
  }

  /// 流停在半行上时，BOM 已剥掉的那部分不能被漏算。
  func testResidualLineAfterByteOrderMarkIsDeliveredByFlush() {
    var framer = SSEFramer()

    for byte in Array("\u{FEFF}".utf8) {
      XCTAssertNil(framer.consume(byte: byte))
    }
    for byte in Array(#"data: {"type":"done"}"#.utf8) {
      XCTAssertNil(framer.consume(byte: byte))
    }
    XCTAssertEqual(framer.flush(), #"{"type":"done"}"#)
  }

  /// 阴性对照：BOM 只在流开头忽略**一次**。中途再出现不属于规范，按普通非 `data` 行丢弃，
  /// 不得被当成 BOM 吃掉 —— 否则 `\u{FEFF}` 之后紧跟的真实字节会被静默吞掉。
  /// （两种实现都通过：本条守的是"别把 BOM 处理铺到整条流上"。）
  func testByteOrderMarkIsOnlyHonoredAtStreamStart() {
    let payloads = frame("data: {\"type\":\"a\"}\n\n\u{FEFF}data: {\"type\":\"b\"}\n\n")

    XCTAssertEqual(payloads, [#"{"type":"a"}"#])
  }

  /// 阴性对照：以 `0xEF` 开头但**不是** BOM 的字节必须原样保留。这条守的是新加的
  /// 三字节前瞻逻辑的误判路径 —— 只有 `EF BB BF` 齐了才算 BOM，`EF BB BB` 不是。
  /// （两种实现都通过：修复前根本没有前瞻逻辑，本条防的是修复本身引入的误吞。）
  func testNonBOMBytesStartingWithEFAreNotSwallowed() {
    let payloads = frame("\u{FEFB}\n\ndata: {\"type\":\"a\"}\n\n")

    XCTAssertEqual(payloads, [#"{"type":"a"}"#])
  }

  /// 只有 BOM、没有内容的流不产生载荷。
  func testByteOrderMarkOnlyStreamProducesNoPayloads() {
    XCTAssertEqual(frame("\u{FEFF}"), [])
  }
}
