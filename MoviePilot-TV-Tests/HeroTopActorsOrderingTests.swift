import XCTest

@testable import MoviePilot_TV

/// F-050 回归：Hero 主演必须**先去重、再取前四**。
///
/// `fullDetail.actors` 取自后端 TMDB `credits.cast`（`app/core/context.py:481-486`），
/// 只过滤 `known_for_department == "Acting"` 而**不去重**；TMDB 的 cast 允许同一个人以
/// 不同 `character` 出现多条。原实现先 `prefix(4)` 再把 4 条交给 `processActors` 按 id
/// 合并，于是这 4 条里的多角色重复被折叠掉，Hero 只剩 2~3 人 —— 而列表后面明明还有
/// 别的演员可以顶上。
///
/// 注意这里断言的是**取哪四个人**，不是显示内容：`mergeActors` 会把同一人的多个角色
/// 合并成「角色A / 角色B」，所以重复项本身的信息不会丢，丢的是人数。
@MainActor
final class HeroTopActorsOrderingTests: XCTestCase {

  // MARK: - Fixtures

  private func person(
    id: String,
    name: String? = "演员",
    character: String? = nil
  ) -> Person {
    Person(
      source: "themoviedb", raw_id: id, name: name, latin_name: nil,
      character: character, job: nil, roles: nil, profile_path: nil,
      original_name: nil, known_for_department: "Acting", place_of_birth: nil,
      popularity: nil, biography: nil, birthday: nil, also_known_as: nil,
      avatar: nil, images: nil, id: "themoviedb-\(id)")
  }

  private func detail(actors: [Person]) -> MediaInfo {
    MediaInfo(
      tmdb_id: 1,
      source: "themoviedb",
      title: "测试媒体",
      type: "电影",
      actors: actors
    )
  }

  private func viewModel(actors: [Person]) -> MediaDetailViewModel {
    MediaDetailViewModel(
      detail: detail(actors: actors),
      apiService: APIService.isolatedTestingInstance()
    )
  }

  private func names(_ persons: [Person]) -> [String] {
    persons.compactMap(\.name)
  }

  // MARK: - 阳性：截断前先按 id 去重

  /// 前四条里第一人占了两条（多角色），后两条是不同演员 —— 去重后正好四人。
  /// 旧顺序下重复项被合并，Hero 只有三人，且第四人永远进不来。
  func testDuplicateInFirstFourDoesNotShortenHeroRow() {
    let viewModel = viewModel(actors: [
      person(id: "9", name: "甲", character: "角色一"),
      person(id: "9", name: "甲", character: "角色二"),
      person(id: "10", name: "乙", character: "角色三"),
      person(id: "11", name: "丙", character: "角色四"),
      person(id: "12", name: "丁", character: "角色五"),
    ])

    viewModel.applyFullDetail(detail(actors: [
      person(id: "9", name: "甲", character: "角色一"),
      person(id: "9", name: "甲", character: "角色二"),
      person(id: "10", name: "乙", character: "角色三"),
      person(id: "11", name: "丙", character: "角色四"),
      person(id: "12", name: "丁", character: "角色五"),
    ]))

    XCTAssertEqual(names(viewModel.heroTopActors), ["甲", "乙", "丙", "丁"])
  }

  // MARK: - 阳性：无名氏不占名额（F-056 并入本项）

  /// `name` 为 nil 的人在视图里经 `compactMap { $0.name }` 渲染成空档，却照样消耗四个
  /// 名额之一。剔掉后第五人得以上位。
  ///
  /// 旧实现（含只改顺序、不过滤的中间版本）都会给出 `["乙", "丙", "丁"]`。
  func testNamelessActorDoesNotOccupyHeroSlot() {
    let actors = [
      person(id: "9", name: nil),
      person(id: "10", name: "乙"),
      person(id: "11", name: "丙"),
      person(id: "12", name: "丁"),
      person(id: "13", name: "戊"),
    ]
    let viewModel = viewModel(actors: actors)
    viewModel.applyFullDetail(detail(actors: actors))

    XCTAssertEqual(names(viewModel.heroTopActors), ["乙", "丙", "丁", "戊"])
  }

  /// 纯空白名与 nil 名同处理 —— 「trim 后为空」才是判据，不是「非 nil」。
  func testWhitespaceOnlyNameIsTreatedAsNameless() {
    let actors = [
      person(id: "9", name: "   "),
      person(id: "10", name: "乙"),
      person(id: "11", name: "丙"),
      person(id: "12", name: "丁"),
      person(id: "13", name: "戊"),
    ]
    let viewModel = viewModel(actors: actors)
    viewModel.applyFullDetail(detail(actors: actors))

    XCTAssertEqual(names(viewModel.heroTopActors), ["乙", "丙", "丁", "戊"])
  }

  // MARK: - 阴性对照

  /// 重复项的多角色必须合并保留，而不是「为了让第四人进来就把重复项丢掉」。
  ///
  /// **这条不是阳性用例**：反向验证（把生产代码退回 `prefix(4)` 在前）时它照样通过 ——
  /// 旧实现取的前四条里甲本就占了两条，合并结果同样是「角色一/角色二」。合并口径既
  /// 不随选取顺序改变，也就无法区分新旧实现，所以它拦的是**另一种错误修法**（用
  /// `Set` 按 id 去重只留首条，会把「角色二」丢掉），而不是本次的 bug。
  ///
  /// `mergeActors` 经 `mergeUniqueStrings` 用 `"/"`（无空格）拼接，与详情页职员行一致。
  func testMergedDuplicateKeepsAllCharacters() {
    let actors = [
      person(id: "9", name: "甲", character: "角色一"),
      person(id: "9", name: "甲", character: "角色二"),
      person(id: "10", name: "乙", character: "角色三"),
      person(id: "11", name: "丙", character: "角色四"),
      person(id: "12", name: "丁", character: "角色五"),
    ]
    let viewModel = viewModel(actors: actors)
    viewModel.applyFullDetail(detail(actors: actors))

    XCTAssertEqual(viewModel.heroTopActors.first?.character, "角色一/角色二")
  }

  /// 无重复时，取哪四个人与旧实现完全一致 —— 修复只改「顺序」，不改「选人」。
  func testOrderIsUnchangedWhenNoDuplicatesExist() {
    let actors = (1...6).map { person(id: "\($0)", name: "演员\($0)") }
    let viewModel = viewModel(actors: actors)
    viewModel.applyFullDetail(detail(actors: actors))

    XCTAssertEqual(names(viewModel.heroTopActors), ["演员1", "演员2", "演员3", "演员4"])
  }

  /// 保持服务端顺序：截断发生在去重**之后**，但不做任何重排。
  func testServerOrderIsPreserved() {
    let actors = [
      person(id: "30", name: "丙"),
      person(id: "10", name: "甲"),
      person(id: "20", name: "乙"),
    ]
    let viewModel = viewModel(actors: actors)
    viewModel.applyFullDetail(detail(actors: actors))

    XCTAssertEqual(names(viewModel.heroTopActors), ["丙", "甲", "乙"])
  }

  /// 过滤只**判空**，不**改写**姓名：带空白的真名要原样保留。防止有人顺手把显示名
  /// 也 trim 掉，那是另一处口径（视图直接拼 `$0.name`），不属于本次取样顺序修复。
  func testNameIsOnlyCheckedForEmptinessNotRewritten() {
    let actors = [person(id: "1", name: " 甲 "), person(id: "2", name: "乙")]
    let viewModel = viewModel(actors: actors)
    viewModel.applyFullDetail(detail(actors: actors))

    XCTAssertEqual(names(viewModel.heroTopActors), [" 甲 ", "乙"])
  }

  /// 不足四人时不补足、不崩 —— 只有三人就显示三人。
  func testFewerThanFourActorsAreShownAsIs() {
    let actors = [person(id: "1", name: "甲"), person(id: "2", name: "乙")]
    let viewModel = viewModel(actors: actors)
    viewModel.applyFullDetail(detail(actors: actors))

    XCTAssertEqual(names(viewModel.heroTopActors), ["甲", "乙"])
  }

  /// 完全无演员时 Hero 保持为空，把位置让给 `:250-251` 的分页兜底 ——
  /// 该分支的触发条件（完全为空）本次未改动，此处固定「空进空出」。
  func testEmptyActorsLeaveHeroRowEmpty() {
    let viewModel = viewModel(actors: [])
    viewModel.applyFullDetail(detail(actors: []))

    XCTAssertTrue(viewModel.heroTopActors.isEmpty)
  }
}
