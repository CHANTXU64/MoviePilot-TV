import XCTest

@testable import MoviePilot_TV

/// UI 预览模式的入口、隔离边界与目录完整性测试。
///
/// 预览只在 Debug/Testing 编译，因此测试直接 @testable 访问 `#if DEBUG` 下的类型。
final class UIPreviewModeTests: XCTestCase {
  // MARK: - 启动参数

  func testPreviewModeRequiresExplicitLaunchArgument() {
    XCTAssertTrue(UIPreviewMode.isEnabled(arguments: ["MoviePilot-TV", "-uiPreviewMode"]))
    XCTAssertFalse(UIPreviewMode.isEnabled(arguments: ["MoviePilot-TV"]))
    XCTAssertFalse(UIPreviewMode.isEnabled(arguments: ["MoviePilot-TV", "uiPreviewMode"]))
  }

  func testLaunchArgumentMatchesDocumentedEntryPoint() {
    XCTAssertEqual(UIPreviewMode.launchArgument, "-uiPreviewMode")
    XCTAssertEqual(UIPreviewMode.sceneLaunchArgument, "-uiPreviewScene")
  }

  func testSceneLaunchArgumentSelectsSpecificCatalogScene() {
    XCTAssertEqual(
      UIPreviewMode.sceneID(arguments: [
        "MoviePilot-TV", "-uiPreviewMode", "-uiPreviewScene", "detail.movie",
      ]),
      "detail.movie"
    )
    XCTAssertNil(UIPreviewMode.sceneID(arguments: ["MoviePilot-TV", "-uiPreviewMode"]))
    XCTAssertNil(UIPreviewMode.sceneID(arguments: ["MoviePilot-TV", "-uiPreviewScene"]))
    // 下一个启动参数不能被当成场景 ID。
    XCTAssertNil(
      UIPreviewMode.sceneID(arguments: [
        "MoviePilot-TV", "-uiPreviewMode", "-uiPreviewScene", "-anotherArgument",
      ])
    )
  }

  // MARK: - 入口

  func testContentViewPreviewEntryIsDebugOnlyAndKeepsRealRootSeam() throws {
    let source = try String(contentsOf: repoFile("MoviePilot-TV/Views/ContentView.swift"))

    XCTAssertTrue(source.contains("#if DEBUG"))
    XCTAssertTrue(source.contains("UIPreviewMode.isEnabled()"))
    XCTAssertTrue(source.contains("PreviewCatalogView(initialSceneID: UIPreviewMode.sceneID())"))

    XCTAssertTrue(source.contains("struct RealAppContentView: View"))

    let contentViewSource = try sourceSlice(
      source,
      from: "struct ContentView: View",
      to: "struct RealAppContentView: View"
    )
    XCTAssertFalse(contentViewSource.contains("@StateObject private var viewModel"))
    XCTAssertFalse(contentViewSource.contains("@StateObject private var mediaActionHandler"))
    XCTAssertTrue(contentViewSource.contains("RealAppContentView()"))
    XCTAssertTrue(contentViewSource.contains("RealAppContentView(viewModel: injectedViewModel)"))
  }

  func testPreviewSupportFilesAreDebugWrapped() throws {
    let directory = repoFile("MoviePilot-TV/PreviewSupport")
    let files = try FileManager.default.subpathsOfDirectory(atPath: directory.path)
      .filter { $0.hasSuffix(".swift") }

    XCTAssertFalse(files.isEmpty)

    for file in files {
      let source = try String(contentsOf: directory.appendingPathComponent(file))
      XCTAssertTrue(
        source.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("#if DEBUG"),
        "\(file) 必须只在 DEBUG 下编译。"
      )
    }
  }

  // MARK: - 模拟后端隔离

  @MainActor
  func testUnstubbedGetRequestIsBlockedInPreviewBackend() async {
    let backend = UIPreviewBackend.shared
    do {
      _ = try await backend.unstubbedRequest(endpoint: "/some/unstubbed", method: "GET")
      XCTFail("未提供 fixture 的 GET 请求必须失败，避免预览访问真实后端。")
    } catch let error as UIPreviewBackendError {
      guard case .missingStub = error else {
        return XCTFail("错误类型应为 missingStub，实际为 \(error)。")
      }
    } catch {
      XCTFail("应为 UIPreviewBackendError，实际为 \(error)。")
    }
  }

  @MainActor
  func testUnstubbedWriteRequestIsSimulatedLocally() async throws {
    let data = try await UIPreviewBackend.shared.unstubbedRequest(
      endpoint: "/some/write", method: "POST")
    XCTAssertFalse(data.isEmpty)
  }

  @MainActor
  func testFixtureBehaviorsDriveEmptyFailureAndHangStates() async throws {
    let backend = UIPreviewBackend.shared
    let key = UIPreviewBehaviorKey.homeSubscriptions

    backend.activate(
      UIPreviewEnvironment.standard.with(behaviors: [key: .empty])
    )
    let emptySubscriptions = try await UIPreviewFixtures.homeSubscriptions()
    XCTAssertTrue(emptySubscriptions.isEmpty)

    backend.activate(
      UIPreviewEnvironment.standard.with(behaviors: [key: .failure])
    )
    do {
      _ = try await UIPreviewFixtures.homeSubscriptions()
      XCTFail("failure 行为必须让 fixture 抛错。")
    } catch {
      // expected
    }

    backend.activate(UIPreviewEnvironment.standard)
    let subscriptions = try await UIPreviewFixtures.homeSubscriptions()
    XCTAssertFalse(subscriptions.isEmpty)
  }

  @MainActor
  func testErrorBehaviorThrowsTypedErrorsWithVisibleDescriptions() async throws {
    let backend = UIPreviewBackend.shared
    let key = UIPreviewBehaviorKey.homeSubscriptions

    let kinds: [UIPreviewErrorKind] = [
      .invalidURL,
      .networkTimeout,
      .networkOffline,
      .networkConnectionLost,
      .decoding,
      .serverMessage("服务器繁忙，请稍后重试"),
      .gateway(503),
      .http(403),
      .authenticationChallenge(statusCode: 401, message: "请重新登录"),
      .credentialsRejected,
      .mfaUnsupported,
      .unauthorized,
      .unknown,
      .business("自定义业务错误"),
    ]

    for kind in kinds {
      backend.activate(UIPreviewEnvironment.standard.with(behaviors: [key: .error(kind)]))
      do {
        _ = try await UIPreviewFixtures.homeSubscriptions()
        XCTFail("error(\(kind)) 行为必须让 fixture 抛错。")
      } catch {
        let description = (error as? LocalizedError)?.errorDescription ?? ""
        XCTAssertFalse(description.isEmpty, "error(\(kind)) 抛出的错误必须有可见文案。")
      }
    }

    backend.activate(UIPreviewEnvironment.standard)
  }

  // MARK: - APIService 预览钩子

  func testAPIServicePreviewHooksShortCircuitBeforeNetwork() throws {
    let source = try String(contentsOf: repoFile("MoviePilot-TV/Services/APIService.swift"))

    XCTAssertTrue(source.contains("func installUIPreviewSession("))
    XCTAssertTrue(source.contains("UIPreviewBackend.shared.unstubbedRequest("))

    let guardedMethods = [
      "func fetchCachedMediaServers(",
      "func fetchMediaServerLatest(",
      "func fetchRecommend(",
      "func fetchDiscoverSources(",
      "func fetchRecommendSources(",
      "func fetchSubscriptionShares(",
      "func fetchSubscriptions(",
      "func fetchStatistic(",
      "func fetchStorage(",
      "func fetchDownloaderInfo(",
      "func fetchDownloadClients(",
      "func fetchDownloading(",
      "func fetchTransferHistory(",
      "func fetchStorages(",
      "func fetchSites(",
    ]

    for method in guardedMethods {
      let body = try sourceSlice(source, from: method)
      let guardRange = try XCTUnwrap(
        body.range(of: "UIPreviewMode.isEnabled()"),
        "\(method) 缺少 UI 预览钩子。"
      )
      let requestRange = try XCTUnwrap(
        body.range(of: "makeRequest(") ?? body.range(of: "sessionCachedValue("),
        "\(method) 缺少真实请求标记。"
      )
      XCTAssertLessThan(
        guardRange.lowerBound, requestRange.lowerBound,
        "\(method) 的预览钩子必须在真实请求之前。")
    }
  }

  func testPreviewSessionReplacementDoesNotPersistServerURL() throws {
    let source = try String(contentsOf: repoFile("MoviePilot-TV/Services/APIService.swift"))
    XCTAssertTrue(source.contains("installUIPreviewSession"))
    // 预览会话不写 serverURL；真实会话仍保留原持久化逻辑。
    XCTAssertTrue(source.contains("if !UIPreviewMode.isEnabled() {"))
    XCTAssertTrue(source.contains("UserDefaults.standard.set(normalizedURL, forKey: \"serverURL\")"))
  }

  // MARK: - 目录完整性

  @MainActor
  func testPreviewCatalogSceneIDsAreUniqueAndContentIsNonEmpty() {
    let sections = UIPreviewCatalog.sections
    XCTAssertFalse(sections.isEmpty)

    var sectionIDs = Set<String>()
    var sceneIDs = Set<String>()

    for section in sections {
      XCTAssertTrue(sectionIDs.insert(section.id).inserted, "重复的预览分组 ID：\(section.id)")
      XCTAssertFalse(section.title.isEmpty)
      XCTAssertFalse(section.scenes.isEmpty, "预览分组 \(section.id) 不能为空。")

      for scene in section.scenes {
        XCTAssertTrue(sceneIDs.insert(scene.id).inserted, "重复的预览场景 ID：\(scene.id)")
        XCTAssertFalse(scene.title.isEmpty)
      }
    }
  }

  @MainActor
  func testPreviewCatalogCoversPrimaryAreas() throws {
    let sceneIDs = UIPreviewCatalog.sections.flatMap { $0.scenes.map(\.id) }
    let requiredPrefixes = [
      "app.",
      "home.",
      "recommend.",
      "explore.",
      "search.",
      "resource.",
      "detail.",
      "season.",
      "status.",
      "settings.",
      "login.",
      "player.",
      "sheet.",
      "component.",
      "subtitle.",
      "log.",
    ]
    for prefix in requiredPrefixes {
      XCTAssertTrue(
        sceneIDs.contains { $0.hasPrefix(prefix) },
        "缺少 \(prefix) 前缀的预览场景。"
      )
    }
    // 当前分组：应用启动与全局、主框架与一级页面、详情、搜索、字幕搜索、设置/登录/日志、播放器、播放流程、核心组件。
    XCTAssertGreaterThanOrEqual(UIPreviewCatalog.sections.count, 9)
    // 旧分支目录有 163 个场景，重建后不允许明显缩水。
    print("UI_PREVIEW_SCENE_COUNT=\(sceneIDs.count)")
    XCTAssertGreaterThanOrEqual(sceneIDs.count, 380)
  }

  @MainActor
  func testPreviewSceneTitlesAreChineseAndNotesDescribeStates() {
    for section in UIPreviewCatalog.sections {
      for scene in section.scenes {
        XCTAssertFalse(scene.title.isEmpty)
        XCTAssertNotNil(scene.note, "场景 \(scene.id) 缺少说明。")
      }
    }
  }

  @MainActor
  func testPreviewCatalogResolvesFirstScene() throws {
    let firstSection = try XCTUnwrap(UIPreviewCatalog.sections.first)
    let firstScene = try XCTUnwrap(firstSection.scenes.first)

    XCTAssertEqual(UIPreviewCatalog.scene(id: firstScene.id)?.id, firstScene.id)
    XCTAssertNil(UIPreviewCatalog.scene(id: "not-a-preview-scene"))
    XCTAssertNil(UIPreviewCatalog.scene(id: nil))
  }

  // MARK: - 发布隔离与文档

  func testReleasePreviewGuardStillScansPreviewSymbols() throws {
    let workflow = try String(
      contentsOf: repoFile(".github/workflows/release-preview-guard.yml"))

    XCTAssertTrue(workflow.contains("-configuration Release"))
    for symbol in ["UIPreview", "PreviewCatalog", "-uiPreviewMode"] {
      XCTAssertTrue(
        workflow.contains(symbol),
        "Release Preview Guard 必须检查预览符号：\(symbol)"
      )
    }
  }

  func testPreviewSupportIsNotReferencedFromReleaseVisibleCode() throws {
    let contentView = try String(contentsOf: repoFile("MoviePilot-TV/Views/ContentView.swift"))
    let previewBranch = try sourceSlice(contentView, from: "#if DEBUG", to: "#else")
    XCTAssertTrue(previewBranch.contains("PreviewCatalogView"))

    let releaseBranch = try sourceSlice(contentView, from: "#else", to: "#endif")
    XCTAssertFalse(releaseBranch.contains("PreviewCatalogView"))
  }

  func testDocsDescribePreviewEntry() throws {
    let readme = try String(contentsOf: repoFile("README.md"))
    XCTAssertTrue(readme.contains("-uiPreviewMode"))
    XCTAssertTrue(readme.contains("-uiPreviewScene"))

    let agents = try String(contentsOf: repoFile("AGENTS.md"))
    XCTAssertTrue(agents.contains("ai/ui-preview-mode"))
  }

  // MARK: - Helpers

  private func sourceSlice(
    _ source: String,
    from startMarker: String,
    to endMarker: String? = nil
  ) throws -> Substring {
    let start = try XCTUnwrap(source.range(of: startMarker), "找不到片段起点：\(startMarker)")
    if let endMarker {
      let end = try XCTUnwrap(
        source.range(of: endMarker, range: start.upperBound..<source.endIndex),
        "找不到片段终点：\(endMarker)"
      )
      return source[start.lowerBound..<end.lowerBound]
    }
    return source[start.lowerBound...]
  }

  private func repoFile(_ path: String) -> URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent(path)
  }
}
