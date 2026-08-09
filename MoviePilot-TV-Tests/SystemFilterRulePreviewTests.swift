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
      include: "2160p",
      exclude: "CAM",
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
      include: "  2160p  ",
      exclude: "   ",
      size_range: " 1024-4096 ",
      seeders: " 5 ",
      publish_time: " "
    )

    XCTAssertEqual(
      SystemFilterRulePreview.summary(for: rule),
      "包含: 2160p · 大小: 1024-4096 MB · 做种≥5"
    )
  }
}
