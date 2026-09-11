import XCTest

@testable import MoviePilot_TV

/// F-040 / F-041 / F-045 / F-052 / F-053 回归：职位 key 的规范化由 `canonicalJobKeys(from:)`
/// 单一提供，翻译与优先级共用同一套 key；翻译后的显示名在最终边界去重。
/// `Person.job` 同时承担 canonical key、去重 key 与显示串三种角色，本次修复不拆字段，
/// 而是保证三种用途对同一输入得出一致结论。
@MainActor
final class StaffJobNormalizationTests: XCTestCase {
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

  private func person(
    id: String,
    name: String = "测试",
    job: String? = nil,
    character: String? = nil,
    roles: [String]? = nil
  ) -> Person {
    Person(
      source: "themoviedb", raw_id: id, name: name, latin_name: nil,
      character: character, job: job, roles: roles, profile_path: nil,
      original_name: nil, known_for_department: nil, place_of_birth: nil,
      popularity: nil, biography: nil, birthday: nil, also_known_as: nil,
      avatar: nil, images: nil, id: "themoviedb-\(id)")
  }

  // MARK: - F-040：不同 key 翻译后同名，须在显示边界去重

  func testCinematographyAndCameraCollapseToSingleDisplayName() {
    let crew = StaffManager.processCrew(persons: [person(id: "1", job: "Cinematography/Camera")])
    XCTAssertEqual(crew.first?.job, "摄影")
  }

  func testSamePersonWithBothCameraKeysAsSeparateRecordsCollapses() {
    // 同一人分两条记录分别携带两个 key，合并后仍不得出现 "摄影/摄影"。
    let crew = StaffManager.processCrew(persons: [
      person(id: "1", job: "Cinematography"),
      person(id: "1", job: "Camera"),
    ])
    XCTAssertEqual(crew.count, 1)
    XCTAssertEqual(crew.first?.job, "摄影")
  }

  // MARK: - F-041：大小写/空白变体不再是独立 key

  func testJobKeyVariantsResolveToCanonicalKey() {
    XCTAssertEqual(canonicalJobKey(for: "Director"), "Director")
    XCTAssertEqual(canonicalJobKey(for: "director"), "Director")
    XCTAssertEqual(canonicalJobKey(for: "DIRECTOR"), "Director")
    XCTAssertEqual(canonicalJobKey(for: "Director\n"), "Director")
    XCTAssertEqual(canonicalJobKey(for: "  Director  "), "Director")
    // 未登记的职位原样保真，不丢弃上游信息。
    XCTAssertEqual(canonicalJobKey(for: "Key Grip"), "Key Grip")
    // 全空白 token 解析为空，由调用方丢弃。
    XCTAssertEqual(canonicalJobKey(for: "   "), "")
    XCTAssertEqual(canonicalJobKeys(from: "Director/ /Writer"), ["Director", "Writer"])
  }

  func testJobKeyVariantsAreTranslated() {
    XCTAssertEqual(TranslationHelper.translateJobs(jobString: "director"), "导演")
    XCTAssertEqual(TranslationHelper.translateJobs(jobString: "Director\n"), "导演")
    // 未登记职位保真显示，不做静默丢弃。
    XCTAssertEqual(TranslationHelper.translateJobs(jobString: "Key Grip"), "Key Grip")
  }

  func testLowercaseDirectorOutranksProducerInHero() {
    let staff = StaffManager.getTopGroupedStaff(
      from: [
        person(id: "1", name: "导演", job: "director"),
        person(id: "2", name: "制片", job: "Producer"),
      ], count: 1)
    XCTAssertEqual(staff.map(\.job), ["导演"])
  }

  // MARK: - F-052：多值 roles 取其中最高优先级

  func testRolesFallbackRanksByBestRolePriority() {
    // roles 为多值时，若整体查表会得 999，从而被 Producer 压过。
    let staff = StaffManager.getTopGroupedStaff(
      from: [
        person(id: "1", name: "导演兼编剧", roles: ["Director", "Writer"]),
        person(id: "2", name: "制片", roles: ["Producer"]),
      ], count: 1)
    XCTAssertEqual(staff.map(\.job), ["导演/编剧"])
  }

  func testAllEmptyRolesProducesFallbackLabelNotStraySeparator() {
    let staff = StaffManager.getTopGroupedStaff(
      from: [person(id: "1", name: "甲", roles: ["", ""])], count: 1)
    XCTAssertEqual(staff.map(\.job), ["职员"])
    XCTAssertEqual(staff.map(\.id), ["职员"])
  }

  func testAllWhitespaceJobFallsBackToRolesInsteadOfBlankLabel() {
    // 全空白职位解析不出 key，兜底分支不得产出空白显示组。
    let staff = StaffManager.getTopGroupedStaff(
      from: [person(id: "1", name: "甲", job: "   ", roles: ["Producer"])], count: 1)
    XCTAssertEqual(staff.map(\.job), ["制片人"])
  }

  // MARK: - F-045：roles-only 人员在职员卡上不再丢失副标题

  func testRolesOnlyCrewGetsJobProjectionForCardSubtitle() {
    let crew = StaffManager.processCrew(persons: [
      person(id: "1", job: nil, character: nil, roles: ["Director"])
    ])
    XCTAssertEqual(crew.first?.job, "导演")
  }

  func testCharacterSubtitleIsNotOverriddenByRoles() {
    let crew = StaffManager.processCrew(persons: [
      person(id: "1", character: "老王", roles: ["Director"])
    ])
    XCTAssertNil(crew.first?.job)
    XCTAssertEqual(crew.first?.character, "老王")
  }

  // MARK: - F-053：mergeCrew 可以消费自己的返回结果

  func testMergeCrewIsIdempotentOverItsOwnOutput() {
    let source = person(id: "1", job: "Director")
    let first = StaffManager.processCrew(persons: [source])
    XCTAssertEqual(first.first?.job, "导演")

    // 把已翻译的结果当作 existing 再合并同一人的原始 key。
    let second = StaffManager.mergeCrew(existing: first, newBatch: [source])
    XCTAssertEqual(second.count, 1)
    XCTAssertEqual(second.first?.job, "导演")
  }

  func testMergeCrewKeepsExistingPositionStable() {
    // 已翻译结果回灌不得改变既有人员顺序（Loadmore 的 UI 稳定性前提）。
    let first = StaffManager.processCrew(persons: [
      person(id: "1", name: "甲", job: "Producer"),
      person(id: "2", name: "乙", job: "Director"),
    ])
    let second = StaffManager.mergeCrew(
      existing: first, newBatch: [person(id: "1", name: "甲", job: "Producer")])
    XCTAssertEqual(second.map(\.id), first.map(\.id))
    XCTAssertEqual(second.map(\.job), first.map(\.job))
  }
}
