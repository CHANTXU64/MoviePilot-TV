import XCTest

@testable import MoviePilot_TV

@MainActor
final class SystemFilterRulePreviewTests: XCTestCase {
  func testCustomRuleResponseSilentlyDropsMalformedAndDuplicateRules() throws {
    let response = try JSONDecoder().decode(
      CustomFilterRulesResponse.self,
      from: Data(
        """
        {
          "value": [
            { "id": "valid-1", "name": "规则一", "include": "2160p" },
            { "id": "missing-name" },
            { "id": 123, "name": "错误类型" },
            { "id": "valid-1", "name": "重复 ID" },
            { "id": "valid-2", "name": "规则一" },
            { "id": "valid-2", "name": "规则二" },
            { "id": "   ", "name": "空 ID" },
            { "id": "valid-3", "name": "规则三" }
          ]
        }
        """.utf8
      )
    )

    XCTAssertEqual(response.value.map(\.id), ["valid-1", "valid-2", "valid-3"])
    XCTAssertEqual(response.value.map(\.name), ["规则一", "规则二", "规则三"])
  }

  func testSummaryIncludesFilterRuleDetailsForPreview() {
    let rule = CustomRule(
      id: "rule-1",
      name: "高清优先",
      include: ["2160p"],
      exclude: ["CAM"],
      size_range: "1024-4096",
      seeders: "5",
      publish_time: "1440"
    )

    XCTAssertEqual(
      SystemFilterRulePreview.summary(for: rule),
      "包含: 2160p · 排除: CAM · 大小: 1024-4096 MB · 做种≥5 · 发布: 1440分钟"
    )
  }

  func testSummaryIsNilWhenRuleHasNoDetailConditions() {
    let rule = CustomRule(
      id: "rule-2",
      name: "仅名称",
      include: nil,
      exclude: nil,
      size_range: nil,
      seeders: nil,
      publish_time: nil
    )

    XCTAssertNil(SystemFilterRulePreview.summary(for: rule))
  }

  func testSummaryTrimsWhitespaceAndIgnoresBlankConditions() {
    let rule = CustomRule(
      id: "rule-3",
      name: "空白字段",
      include: ["  2160p  "],
      exclude: ["   "],
      size_range: " 1024-4096 ",
      seeders: " 5 ",
      publish_time: " "
    )

    XCTAssertEqual(
      SystemFilterRulePreview.summary(for: rule),
      "包含: 2160p · 大小: 1024-4096 MB · 做种≥5"
    )
  }

  func testCustomRuleDecodesIncludeExcludeAsStringOrList() throws {
    let stringRule = try JSONDecoder().decode(
      CustomRule.self,
      from: Data(#"{"id":"s","name":"串","include":"2160p","exclude":"CAM"}"#.utf8)
    )
    XCTAssertEqual(stringRule.include, ["2160p"])
    XCTAssertEqual(stringRule.exclude, ["CAM"])

    let listRule = try JSONDecoder().decode(
      CustomRule.self,
      from: Data(#"{"id":"l","name":"列","include":["2160p","HDR"],"exclude":["CAM","HDTV"]}"#.utf8)
    )
    XCTAssertEqual(listRule.include, ["2160p", "HDR"])
    XCTAssertEqual(listRule.exclude, ["CAM", "HDTV"])
  }

  // MARK: - CustomFilterService 与后端 __match_rule 对齐

  private func makeContext(
    title: String,
    size: Int64 = 1024,
    seeders: Int? = nil,
    pubdate: String? = nil
  ) throws -> Context {
    let pubdateJSON = pubdate.map { "\"\($0)\"" } ?? "null"
    let seedersJSON = seeders.map(String.init) ?? "null"
    let torrent = try JSONDecoder().decode(
      TorrentInfo.self,
      from: Data(
        """
        {
          "title": "\(title)",
          "size": \(size),
          "seeders": \(seedersJSON),
          "pubdate": \(pubdateJSON)
        }
        """.utf8
      )
    )
    return Context(torrent_info: torrent)
  }

  private func makePubdate(minutesAgo: Int) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return formatter.string(from: Date().addingTimeInterval(-Double(minutesAgo) * 60))
  }

  func testMatchIncludeListAnyMatchPasses() throws {
    let rule = CustomRule(id: "r", name: "r", include: ["CAM", "2160p"])
    XCTAssertTrue(try CustomFilterService.matchRule(
      context: try makeContext(title: "电影 2160p HDR"), rule: rule))
    XCTAssertFalse(try CustomFilterService.matchRule(
      context: try makeContext(title: "电影 1080p"), rule: rule))
  }

  func testMatchExcludeListAnyMatchExcludes() throws {
    let rule = CustomRule(id: "r", name: "r", exclude: ["CAM", "HDTV"])
    XCTAssertFalse(try CustomFilterService.matchRule(
      context: try makeContext(title: "电影 HDTV 1080p"), rule: rule))
    XCTAssertTrue(try CustomFilterService.matchRule(
      context: try makeContext(title: "电影 1080p"), rule: rule))
  }

  func testMatchSeedersTrimsWhitespaceLikePythonInt() throws {
    let rule = CustomRule(id: "r", name: "r", seeders: " 5 ")
    XCTAssertFalse(try CustomFilterService.matchRule(
      context: try makeContext(title: "t", seeders: 3), rule: rule))
    XCTAssertTrue(try CustomFilterService.matchRule(
      context: try makeContext(title: "t", seeders: 7), rule: rule))
  }

  func testMatchInvalidSeedersThrows() {
    let rule = CustomRule(id: "r", name: "r", seeders: "5-10")
    XCTAssertThrowsError(try CustomFilterService.matchRule(
      context: try makeContext(title: "t", seeders: 9), rule: rule))
  }

  func testMatchMissingOrInvalidPubdateTreatsAsZeroMinutes() throws {
    // 后端 pub_minutes() 对缺失/不可解析 pubdate 返回 0；单值规则要求 >= 1440 → 排除。
    let rule = CustomRule(id: "r", name: "r", publish_time: "1440")
    XCTAssertFalse(try CustomFilterService.matchRule(
      context: try makeContext(title: "t"), rule: rule))
    XCTAssertFalse(try CustomFilterService.matchRule(
      context: try makeContext(title: "t", pubdate: "not-a-date"), rule: rule))
    // 区间 [0, 100] 包含 0 分钟 → 通过。
    let rangeRule = CustomRule(id: "r", name: "r", publish_time: "0-100")
    XCTAssertTrue(try CustomFilterService.matchRule(
      context: try makeContext(title: "t"), rule: rangeRule))
  }

  func testMatchRecentPubdateFailsSingleValueRule() throws {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    let nowString = formatter.string(from: Date())
    let rule = CustomRule(id: "r", name: "r", publish_time: "1440")
    XCTAssertFalse(try CustomFilterService.matchRule(
      context: try makeContext(title: "t", pubdate: nowString), rule: rule))
  }

  func testMatchInvalidRegexThrows() {
    let rule = CustomRule(id: "r", name: "r", include: ["["])
    XCTAssertThrowsError(try CustomFilterService.matchRule(
      context: try makeContext(title: "t"), rule: rule))
  }

  func testMatchSizeSingleValueExcludesLikeBackendUnknown() throws {
    // 后端 _parse_size_range 对无符号单值返回 unknown → 不匹配 → 排除。
    let rule = CustomRule(id: "r", name: "r", size_range: "1024")
    XCTAssertFalse(try CustomFilterService.matchRule(
      context: try makeContext(title: "t", size: 1024 * 1024 * 1024), rule: rule))
    // 纯空白同样返回 unknown → 排除（空字符串则由 __match_rule 整体跳过）。
    let blankRule = CustomRule(id: "r", name: "r", size_range: "   ")
    XCTAssertFalse(try CustomFilterService.matchRule(
      context: try makeContext(title: "t", size: 1024 * 1024 * 1024), rule: blankRule))
  }

  func testMatchSizeBetweenRange() throws {
    let rule = CustomRule(id: "r", name: "r", size_range: "1-2")
    XCTAssertTrue(try CustomFilterService.matchRule(
      context: try makeContext(title: "t", size: Int64(1.5 * 1024 * 1024)), rule: rule))
    XCTAssertFalse(try CustomFilterService.matchRule(
      context: try makeContext(title: "t", size: Int64(3 * 1024 * 1024)), rule: rule))
  }

  func testMatchSizeGreaterThanAndLessThan() throws {
    let gteRule = CustomRule(id: "r", name: "r", size_range: ">1")
    XCTAssertTrue(try CustomFilterService.matchRule(
      context: try makeContext(title: "t", size: Int64(2 * 1024 * 1024)), rule: gteRule))
    XCTAssertFalse(try CustomFilterService.matchRule(
      context: try makeContext(title: "t", size: Int64(0.5 * 1024 * 1024)), rule: gteRule))

    let lteRule = CustomRule(id: "r", name: "r", size_range: "<3")
    XCTAssertTrue(try CustomFilterService.matchRule(
      context: try makeContext(title: "t", size: Int64(2 * 1024 * 1024)), rule: lteRule))
    XCTAssertFalse(try CustomFilterService.matchRule(
      context: try makeContext(title: "t", size: Int64(5 * 1024 * 1024)), rule: lteRule))

    // 后端 float(size_range[1:].strip()) 允许 "> 1" 这类操作符后带空白。
    let spacedRule = CustomRule(id: "r", name: "r", size_range: "> 1")
    XCTAssertTrue(try CustomFilterService.matchRule(
      context: try makeContext(title: "t", size: Int64(2 * 1024 * 1024)), rule: spacedRule))
  }

  func testMatchSizeInvalidFormatsFailOrExcludeLikeBackend() throws {
    // 后端 split("-") 解包两段失败 → 抛异常。
    let multiDashRule = CustomRule(id: "r", name: "r", size_range: "1-2-3")
    XCTAssertThrowsError(try CustomFilterService.matchRule(
      context: try makeContext(title: "t"), rule: multiDashRule))

    // 后端 float("abc") 失败 → 抛异常。
    let gteInvalidRule = CustomRule(id: "r", name: "r", size_range: ">abc")
    XCTAssertThrowsError(try CustomFilterService.matchRule(
      context: try makeContext(title: "t"), rule: gteInvalidRule))
    let lteInvalidRule = CustomRule(id: "r", name: "r", size_range: "<abc")
    XCTAssertThrowsError(try CustomFilterService.matchRule(
      context: try makeContext(title: "t"), rule: lteInvalidRule))

    // 后端 "abc" 无符号无比较符 → unknown → 不匹配（排除），但不抛异常。
    let unknownRule = CustomRule(id: "r", name: "r", size_range: "abc")
    XCTAssertFalse(try CustomFilterService.matchRule(
      context: try makeContext(title: "t", size: 1024 * 1024), rule: unknownRule))
  }

  func testMatchPublishTimeRangeMidValue() throws {
    let rangeRule = CustomRule(id: "r", name: "r", publish_time: "0-100")
    XCTAssertTrue(try CustomFilterService.matchRule(
      context: try makeContext(title: "t", pubdate: makePubdate(minutesAgo: 50)), rule: rangeRule))
    XCTAssertFalse(try CustomFilterService.matchRule(
      context: try makeContext(title: "t", pubdate: makePubdate(minutesAgo: 150)), rule: rangeRule))

    // 后端 tuple(float... ) 对多段只取前两段，第三段忽略。
    let extraDashRule = CustomRule(id: "r", name: "r", publish_time: "5-10-15")
    XCTAssertTrue(try CustomFilterService.matchRule(
      context: try makeContext(title: "t", pubdate: makePubdate(minutesAgo: 8)), rule: extraDashRule))
    XCTAssertFalse(try CustomFilterService.matchRule(
      context: try makeContext(title: "t", pubdate: makePubdate(minutesAgo: 12)), rule: extraDashRule))
  }

  func testMatchPublishTimeInvalidThrows() {
    // 与后端 split("-") + float() 一致：空段、缺段、纯文本均显式失败。
    for invalid in ["abc", "-", "-5", "5-"] {
      let rule = CustomRule(id: "r", name: "r", publish_time: invalid)
      XCTAssertThrowsError(try CustomFilterService.matchRule(
        context: try makeContext(title: "t"), rule: rule), "publish_time \(invalid) 应显式失败")
    }
  }

  func testCustomRuleEmptyStringExcludeDecodesAsNilAndArrayEmptyStringStillExcludes() throws {
    // 后端 `rule.get("exclude") or []`：空字符串视为未配置 → 放行。
    let emptyStringRule = try JSONDecoder().decode(
      CustomRule.self,
      from: Data(#"{"id":"s","name":"串","exclude":""}"#.utf8)
    )
    XCTAssertNil(emptyStringRule.exclude)
    XCTAssertTrue(try CustomFilterService.matchRule(
      context: try makeContext(title: "t"), rule: emptyStringRule))

    // 数组形式 ["", ...] 是真实列表 → 后端按空正则匹配一切 → 排除。
    let arrayRule = try JSONDecoder().decode(
      CustomRule.self,
      from: Data(#"{"id":"a","name":"列","exclude":[""]}"#.utf8)
    )
    XCTAssertEqual(arrayRule.exclude, [""])
    XCTAssertFalse(try CustomFilterService.matchRule(
      context: try makeContext(title: "t"), rule: arrayRule))

    // include 数组空串：空正则匹配一切 → 通过（与后端一致）。
    let arrayIncludeRule = try JSONDecoder().decode(
      CustomRule.self,
      from: Data(#"{"id":"i","name":"列","include":[""]}"#.utf8)
    )
    XCTAssertEqual(arrayIncludeRule.include, [""])
    XCTAssertTrue(try CustomFilterService.matchRule(
      context: try makeContext(title: "t"), rule: arrayIncludeRule))
  }
}
