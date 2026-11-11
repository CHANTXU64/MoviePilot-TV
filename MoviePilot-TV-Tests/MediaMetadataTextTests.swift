import XCTest

@testable import MoviePilot_TV

/// F-038 / F-042 / F-043 / F-046 回归：详情页两行元数据只允许「产出非空」的显示值进入，
/// 且叶子层（语言/国家/类型）先 trim 再查表。三条缺陷共用同一处 `joined(separator:)`，
/// 因此断言统一落在**最终拼接结果**上：既不能有悬空分隔符，也不能有一条空 `Text`。
///
/// 所有用例都从 JSON 解码 `MediaInfo`，走生产解码路径（`decodeIfPresent` + 宽容元素解析），
/// 避免绕过畸形元素归一而给出假绿。
@MainActor
final class MediaMetadataTextTests: XCTestCase {
  private var savedLanguage: AppLanguage!

  override func setUp() {
    super.setUp()
    savedLanguage = TranslationHelper.currentLanguage
    TranslationHelper.currentLanguage = .zhHans
  }

  override func tearDown() {
    TranslationHelper.currentLanguage = savedLanguage
    super.tearDown()
  }

  /// 从 JSON 构造 `MediaInfo`，只填用例关心的字段。
  private func media(_ json: String) throws -> MediaInfo {
    try JSONDecoder().decode(MediaInfo.self, from: Data(json.utf8))
  }

  /// 归一后的显示值不得为空；外层 `joined(separator: " · ")` 因此不可能出现
  /// `"a ·  · b"`、`" · b"`、`"a · "` 这类悬空分隔符。
  private func assertNoDanglingSeparator(_ items: [String], file: StaticString = #filePath, line: UInt = #line) {
    for item in items {
      XCTAssertFalse(
        item.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        "元数据元素不应为空或纯空白：\(items)", file: file, line: line)
    }
    let joined = items.joined(separator: " · ")
    XCTAssertFalse(joined.hasPrefix(" · "), "不应有前导分隔符：\(joined)", file: file, line: line)
    XCTAssertFalse(joined.hasSuffix(" · "), "不应有尾随分隔符：\(joined)", file: file, line: line)
    XCTAssertFalse(joined.contains(" ·  · "), "不应有连续空段：\(joined)", file: file, line: line)
  }

  // MARK: - F-038：空白 original_language 不得进入显示行

  func testBlankOriginalLanguageProducesNoElement() throws {
    for payload in [#"{"original_language":""}"#, #"{"original_language":"   "}"#, #"{"original_language":"\n"}"#] {
      let detail = try media(payload)
      let items = MediaMetadataText.secondaryLine(for: detail)
      XCTAssertTrue(items.isEmpty, "空白语言不应产出任何元素（\(payload)）：\(items)")
    }
  }

  func testLanguageCodeIsTrimmedBeforeLookup() {
    // 带空白的代码原样回退会显示 " en "，既查不到词表也破坏整行排版。
    XCTAssertEqual(TranslationHelper.languageName(for: "en"), "英语")
    XCTAssertEqual(TranslationHelper.languageName(for: " en "), "英语")
    XCTAssertEqual(TranslationHelper.languageName(for: "en\n"), "英语")
    XCTAssertEqual(TranslationHelper.languageName(for: "  "), "")
  }

  // MARK: - F-043：空/畸形国家元素不得产出空段

  func testMalformedCountryElementsProduceNoElement() throws {
    // null / 数字 / 布尔 / 空对象 / 空串 code+name 都不支持，解码为 (nil, nil)。
    let raws = ["null", "42", "true", "{}", #"{"iso_3166_1":"","name":""}"#, #"{"iso_3166_1":"  ","name":"  "}"#]
    for raw in raws {
      let detail = try media(#"{"production_countries":[\#(raw)]}"#)
      let items = MediaMetadataText.secondaryLine(for: detail)
      XCTAssertTrue(items.isEmpty, "畸形国家元素不应产出元素（\(raw)）：\(items)")
    }
  }

  func testMalformedCountryElementsAreDroppedButValidOneSurvives() throws {
    let detail = try media(
      #"{"production_countries":[null,{"iso_3166_1":"US","name":"United States"},{"name":""}]}"#)
    let items = MediaMetadataText.secondaryLine(for: detail)
    XCTAssertEqual(items, ["美国"])
    assertNoDanglingSeparator(items)
  }

  func testUnknownNonEmptyCountryCodeIsPreserved() throws {
    // 未知 code 且无 name 时保真 code，而不是静默变空段。
    let detail = try media(#"{"production_countries":[{"iso_3166_1":"ZZ","name":""}]}"#)
    XCTAssertEqual(MediaMetadataText.secondaryLine(for: detail), ["ZZ"])
  }

  // MARK: - F-042：国家码 trim 与大小写规范化

  func testCountryNameIsTrimmedBeforeLookup() throws {
    XCTAssertEqual(TranslationHelper.countryName(for: " US "), "美国")
    XCTAssertEqual(TranslationHelper.countryName(for: "  "), "")
    // 未知非空 code 保真，全空白 code 视为无内容。
    XCTAssertEqual(TranslationHelper.countryName(for: "ZZ"), "ZZ")
  }

  func testCountryCodeIsUppercasedBeforeLookup() {
    XCTAssertEqual(TranslationHelper.countryName(for: " us "), "美国")
    XCTAssertEqual(TranslationHelper.countryName(for: "us\n"), "美国")
    // 未知 code 也按同一规范化边界返回，不能因为查表失败而恢复成小写。
    XCTAssertEqual(TranslationHelper.countryName(for: "zz"), "ZZ")
  }

  func testProductionCountryCodeIsUppercasedBeforeLookup() throws {
    let detail = try media(
      #"{"production_countries":[{"iso_3166_1":" us ","name":"Fallback"}]}"#)
    XCTAssertEqual(MediaMetadataText.secondaryLine(for: detail), ["美国"])
  }

  func testEnglishCountryNameIsTrimmed() throws {
    TranslationHelper.currentLanguage = .en
    XCTAssertEqual(TranslationHelper.countryName(for: " US\n"), "United States of America")
  }

  // MARK: - F-046：类型名规范化与空结果过滤

  func testBlankAndMalformedGenreElementsProduceNoElement() throws {
    let payloads = [
      #"[{"name":""}]"#,
      #"[{"name":"   "}]"#,
      #"[null]"#,
      #"[42]"#,
      #"[{}]"#,
      #"[{"id":28}]"#,
      #"[""]"#,
    ]
    for payload in payloads {
      let detail = try media(#"{"category":"电影","genres":\#(payload)}"#)
      let items = MediaMetadataText.primaryLine(for: detail)
      XCTAssertEqual(items, ["电影"], "空/畸形类型不应产出段（\(payload)）：\(items)")
      assertNoDanglingSeparator(items)
    }
  }

  func testWhitespacePaddedGenreIsTranslated() throws {
    let detail = try media(#"{"genres":[{"name":" Sci-Fi & Fantasy "}]}"#)
    XCTAssertEqual(MediaMetadataText.primaryLine(for: detail), ["科幻 & 奇幻"])
  }

  func testUnknownGenreNameIsTrimmedButPreserved() throws {
    let detail = try media(#"{"genres":[{"name":" 纪录片 "}]}"#)
    XCTAssertEqual(MediaMetadataText.primaryLine(for: detail), ["纪录片"])
    XCTAssertEqual(TranslationHelper.translateGenre(for: "  "), "")
  }

  // MARK: - 外层判据：分类/类型与 release_date/year 同样按显示值归一

  func testBlankCategoryFallsBackToType() throws {
    let detail = try media(#"{"category":"","type":"movie"}"#)
    XCTAssertEqual(MediaMetadataText.primaryLine(for: detail), ["movie"])

    let whitespaceCategory = try media(#"{"category":"\n ","type":"movie"}"#)
    XCTAssertEqual(MediaMetadataText.primaryLine(for: whitespaceCategory), ["movie"])

    let bothBlank = try media(#"{"category":" ","type":""}"#)
    XCTAssertTrue(MediaMetadataText.primaryLine(for: bothBlank).isEmpty)
  }

  func testBlankReleaseDateFallsBackToYear() throws {
    let detail = try media(#"{"release_date":"  ","year":"2024"}"#)
    XCTAssertEqual(MediaMetadataText.secondaryLine(for: detail), ["2024"])

    let bothBlank = try media(#"{"release_date":"\n","year":" "}"#)
    XCTAssertTrue(MediaMetadataText.secondaryLine(for: bothBlank).isEmpty)
  }

  // MARK: - 端到端：敌意载荷下两行都不得出现悬空分隔符

  func testHostilePayloadProducesNoDanglingSeparator() throws {
    let detail = try media(
      """
      {
        "category": " ",
        "type": "movie",
        "genres": [{"name": "  "}, null, 7, {"name": "纪录片"}],
        "release_date": "",
        "year": "2024",
        "runtime": 120,
        "vote_average": 8.1,
        "production_countries": [null, {"iso_3166_1": "", "name": " "}, {"iso_3166_1": "CN", "name": ""}],
        "original_language": "  "
      }
      """)

    let primary = MediaMetadataText.primaryLine(for: detail)
    let secondary = MediaMetadataText.secondaryLine(for: detail)

    XCTAssertEqual(primary, ["movie", "纪录片"])
    XCTAssertEqual(secondary, ["2024", "120 分钟", "评分 8.1", "中国"])
    assertNoDanglingSeparator(primary)
    assertNoDanglingSeparator(secondary)
  }

  func testAllValidFieldsArePreserved() throws {
    // 阳性对照：归一化不得吞掉任何合法字段或改变顺序。
    let detail = try media(
      """
      {
        "category": "电影",
        "genres": [{"name": "Sci-Fi & Fantasy"}, {"name": "War & Politics"}],
        "release_date": "2024-05-01",
        "year": "2024",
        "runtime": 128,
        "vote_average": 7.5,
        "production_countries": [{"iso_3166_1": "US", "name": "United States"}, {"iso_3166_1": "JP", "name": "Japan"}],
        "original_language": "en"
      }
      """)

    XCTAssertEqual(MediaMetadataText.primaryLine(for: detail), ["电影", "科幻 & 奇幻 · 战争 & 政治"])
    XCTAssertEqual(
      MediaMetadataText.secondaryLine(for: detail),
      ["2024-05-01", "128 分钟", "评分 7.5", "美国 / 日本", "英语"])
  }
}
