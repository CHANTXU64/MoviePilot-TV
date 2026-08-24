import XCTest

@testable import MoviePilot_TV

@MainActor
final class DynamicSourceBehaviorTests: XCTestCase {
  func testMediaGridEquatableIdentityIncludesImageConfiguration() throws {
    let gridSource = try source("MoviePilot-TV/Views/Components/MediaGridView.swift")
    XCTAssertTrue(
      gridSource.contains(
        "lhs.imageConfigurationIdentity == rhs.imageConfigurationIdentity"
      )
    )
    XCTAssertTrue(
      gridSource.contains(
        "imageConfigurationIdentity: apiService.imageConfigurationIdentity"
      )
    )
    XCTAssertTrue(gridSource.contains("lhs.itemIndex == rhs.itemIndex"))
    XCTAssertTrue(gridSource.contains("lhs.itemCount == rhs.itemCount"))
    XCTAssertTrue(gridSource.contains("lhs.listIdentity == rhs.listIdentity"))
    XCTAssertTrue(gridSource.contains("GridImageDemandContext("))
    XCTAssertFalse(gridSource.contains("loadsImage(at:"))
    XCTAssertFalse(gridSource.contains("loadsImage: loadsImage"))
    XCTAssertFalse(gridSource.contains("topRestorationRevision"))
    XCTAssertFalse(
      gridSource.contains("domRetention.reconcile(itemIDs: items.map(\\.id))\n    domRetention.cardFocusChanged")
    )
    let paginatorSource = try source("MoviePilot-TV/Services/Paginator.swift")
    XCTAssertTrue(
      paginatorSource.contains("@Published private(set) var listIdentity: GridListIdentity")
    )
    let recommendSource = try source("MoviePilot-TV/Views/Pages/RecommendView.swift")
    let exploreSource = try source("MoviePilot-TV/Views/Pages/ExploreView.swift")
    XCTAssertFalse(recommendSource.contains(".id(paginator.listID)"))
    XCTAssertFalse(exploreSource.contains(".id(paginator.listID)"))
    XCTAssertEqual(gridSource.components(separatedBy: ".id(listIdentity.id)").count - 1, 1)
    XCTAssertTrue(
      gridSource.contains("          .id(listIdentity.id)\n          .padding(.horizontal, -12)")
    )
    let preloaderSource = try source("MoviePilot-TV/ViewModels/MediaPreloader.swift")
    XCTAssertTrue(
      preloaderSource.contains("retrieveHeroImage(url, fallbackURL: target.fallbackURL)")
    )
    let managedImageSource = try source("MoviePilot-TV/Views/Components/PageManagedImage.swift")
    XCTAssertTrue(managedImageSource.contains("$0.listIdentity.generation"))
  }

  func testMemoryCleanupPagesUseTheIntendedLifecycleBoundaries() throws {
    let statusSource = try source("MoviePilot-TV/Views/Pages/StatusView.swift")
    let downloadSource = try source("MoviePilot-TV/Views/Pages/DownloadTaskView.swift")
    let downloadViewModelSource = try source(
      "MoviePilot-TV/ViewModels/DownloadTaskViewModel.swift"
    )
    let transferSource = try source("MoviePilot-TV/Views/Pages/TransferHistoryView.swift")
    let seasonSource = try source("MoviePilot-TV/Views/Pages/SubscribeSeasonView.swift")
    let manualSearchSource = try source("MoviePilot-TV/Views/Sheets/ManualMediaSearchSheet.swift")
    let lifecycleSource = try source("MoviePilot-TV/Services/PageImageLifecycle.swift")
    let retentionSource = try source(
      "MoviePilot-TV/Services/PresentationTransitionRetention.swift"
    )
    let detailSource = try source("MoviePilot-TV/Views/Pages/MediaDetailContainerView.swift")

    XCTAssertTrue(statusSource.contains("DownloadTaskView(isSelected: isSelected)"))
    XCTAssertTrue(statusSource.contains(".task(id: isSelected)"))
    XCTAssertTrue(statusSource.contains("guard isSelected else { return }"))
    XCTAssertTrue(
      statusSource.contains(
        ".environment(\\.pageImageLifecycle, imageLifecycleCoordinator.rootLifecycle)"
      )
    )
    XCTAssertTrue(downloadSource.contains(".task(id: isSelected)"))
    XCTAssertTrue(downloadSource.contains("guard isSelected else { return }"))
    XCTAssertTrue(downloadSource.contains("viewModel.setPresentationActive(isSelected)"))
    XCTAssertTrue(downloadViewModelSource.contains("private var presentationGeneration = 0"))
    XCTAssertTrue(downloadViewModelSource.contains("currentPresentationGeneration"))
    XCTAssertTrue(downloadViewModelSource.contains("!Task.isCancelled"))
    XCTAssertTrue(downloadSource.contains("PageManagedImage("))
    XCTAssertFalse(downloadSource.contains("KFImage.sessionImage("))

    XCTAssertTrue(
      transferSource.contains(
        "if !keepsRowsMounted {\n        EmptyView()\n      } else if viewModel.isFirstLoading"
      )
    )
    XCTAssertTrue(statusSource.contains("TransferHistoryView.shouldMountRows("))
    XCTAssertTrue(transferSource.contains(".onChange(of: keepsRowsMounted)"))

    XCTAssertTrue(seasonSource.contains("@State private var gridListIdentity"))
    XCTAssertFalse(seasonSource.contains("private let gridListIdentity"))
    XCTAssertTrue(seasonSource.contains("GridImageDemandContext("))
    XCTAssertTrue(seasonSource.contains("seasonInfos.prefix(retainedItemCount)"))
    XCTAssertTrue(seasonSource.contains("let displayCount = min(10, viewModel.seasonInfos.count)"))

    XCTAssertTrue(manualSearchSource.contains("searchTask?.cancel()"))
    XCTAssertTrue(manualSearchSource.contains("viewModel.presentationDidDisappear()"))
    XCTAssertTrue(manualSearchSource.contains("guard searchRevision == revision else { return }"))

    XCTAssertTrue(
      lifecycleSource.contains(
        "tabTransitionImageRetention: Duration = PresentationTransitionRetention.duration"
      )
    )
    XCTAssertTrue(retentionSource.contains("static let duration = Duration.seconds(1)"))
    XCTAssertTrue(
      detailSource.contains(
        "loadingPosterReleaseDelay = PresentationTransitionRetention.duration"
      )
    )
  }

  func testHomeAsyncNavigationCapturesSourceBeforeTaskAndUsesConditionalPush() throws {
    let homeSource = try source("MoviePilot-TV/Views/Pages/HomeView.swift")

    XCTAssertTrue(
      homeSource.contains(
        "@EnvironmentObject private var navigationCoordinator: ImageNavigationCoordinator"
      )
    )
    XCTAssertEqual(
      homeSource.components(
        separatedBy: "let navigationSource = navigationCoordinator.sourceToken()"
      ).count - 1,
      2
    )
    XCTAssertTrue(
      homeSource.contains(
        "let navigationSource = navigationCoordinator.sourceToken()\n                  let loadingPosterURL = item.imageURLs.image\n                  Task {"
      )
    )
    XCTAssertTrue(
      homeSource.contains(
        "if canSearchResources {\n                  Button {\n                    let navigationSource = navigationCoordinator.sourceToken()\n                    Task {"
      )
    )
    XCTAssertEqual(
      homeSource.components(separatedBy: "ifCurrent: navigationSource").count - 1,
      3
    )
    XCTAssertFalse(homeSource.contains("onTMDBDetail"))
    XCTAssertFalse(homeSource.contains("onSearchResource"))
  }

  func testLoadingPosterIsScopedToNavigationEntryInsteadOfGlobalState() throws {
    let lifecycleSource = try source("MoviePilot-TV/Services/PageImageLifecycle.swift")
    let destinationSource = try source(
      "MoviePilot-TV/Views/Components/ImageNavigationDestination.swift"
    )
    let actionSource = try source("MoviePilot-TV/ViewModels/MediaActionHandler.swift")
    let cardSource = try source("MoviePilot-TV/Views/Components/MediaCard.swift")

    XCTAssertTrue(lifecycleSource.contains("let loadingPosterURL: URL?"))
    XCTAssertTrue(destinationSource.contains("loadingPosterURL: entry.loadingPosterURL"))
    XCTAssertFalse(actionSource.contains("MediaCardTransition.loadingPosterURL"))
    XCTAssertFalse(cardSource.contains("enum MediaCardTransition"))
  }

  func testPrefetchBackgroundImageWarmsOnFocusAndDecodesAfterOpeningDetail() throws {
    let preloaderSource = try source("MoviePilot-TV/ViewModels/MediaPreloader.swift")
    let prefetchStart = try XCTUnwrap(
      preloaderSource.range(of: "private func prefetchBackgroundImage(for detail: MediaInfo")
    )
    let prefetchEnd = try XCTUnwrap(
      preloaderSource.range(
        of: "private func retrieveHeroImage(_ url: URL, fallbackURL: URL?)",
        range: prefetchStart.upperBound..<preloaderSource.endIndex
      )
    )
    let prefetch = preloaderSource[prefetchStart.lowerBound..<prefetchEnd.lowerBound]
    let cancelStart = try XCTUnwrap(preloaderSource.range(of: "func cancelImageWarm()"))
    let cancelEnd = try XCTUnwrap(
      preloaderSource.range(
        of: "func shouldWarmBackgroundImage()",
        range: cancelStart.upperBound..<preloaderSource.endIndex
      )
    )
    let cancel = preloaderSource[cancelStart.lowerBound..<cancelEnd.lowerBound]
    let containerSource = try source("MoviePilot-TV/Views/Pages/MediaDetailContainerView.swift")

    XCTAssertTrue(prefetch.contains("let canWarmOnMoviePilot = MPImageWarmer.isWarmable("))
    XCTAssertTrue(prefetch.contains("if preparedAsCandidate, canWarmOnMoviePilot"))
    XCTAssertTrue(prefetch.contains("MPImageWarmer.shared.warm(url)"))
    XCTAssertTrue(prefetch.contains("activeImageWarmHandle = handle"))
    XCTAssertTrue(prefetch.contains("return"))
    XCTAssertTrue(prefetch.contains("retrieveHeroImage(url, fallbackURL: target.fallbackURL)"))
    XCTAssertTrue(prefetch.contains("guard !Task.isCancelled else { return }"))
    XCTAssertTrue(cancel.contains("MPImageWarmer.shared.cancel(activeImageWarmHandle)"))
    XCTAssertTrue(containerSource.contains("preloadTask.cancelImageWarm()"))
  }

  func testPluginFilterParserKeepsSupportedControlsAndSkipsUnknownControls() {
    let parsed = PluginFilterControlParser.parse([
      .object([
        "component": .string("VChipGroup"),
        "props": .object([
          "model": .string("mtype"),
          "label": .string("类型"),
        ]),
        "content": .array([
          .object([
            "component": .string("VChip"),
            "props": .object(["value": .string("movies")]),
            "text": .string("电影"),
          ])
        ]),
      ]),
      .object([
        "component": .string("FutureRange"),
        "props": .object([
          "model": .string("score"),
          "label": .string("评分"),
        ]),
      ]),
    ])

    XCTAssertEqual(parsed.map(\.field), ["mtype"])
    XCTAssertEqual(parsed.first?.options.map(\.title), ["电影"])
  }

  func testPluginFilterSwitchAndRangeSliderParsedWithVisibility() {
    let parsed = PluginFilterControlParser.parse([
      .object([
        "component": .string("div"),
        "props": .object([
          "show": .string("{{mtype == 'movies'}}"),
        ]),
        "content": .array([
          .object([
            "component": .string("VSwitch"),
            "props": .object([
              "model": .string("using_rating"),
              "label": .string("启用"),
            ]),
          ]),
          .object([
            "component": .string("VRangeSlider"),
            "props": .object([
              "v-model": .string("user_rating"),
              "min": .string("1"),
              "max": .string("10"),
              "step": .string("1"),
            ]),
          ]),
        ]),
      ]),
    ])

    XCTAssertEqual(parsed.map(\.field), ["using_rating", "user_rating"])
    XCTAssertEqual(parsed[0].kind, .toggle)
    XCTAssertEqual(parsed[1].kind, .choice)
    XCTAssertEqual(parsed[1].options.map(\.value), (1...10).map { JSONValue.int($0) })
    XCTAssertEqual(parsed[1].options.map(\.title), (1...10).map(String.init))
    XCTAssertEqual(parsed[1].rangeBounds, [.int(1), .int(10)])
    XCTAssertEqual(parsed[0].showExpressions, ["{{mtype == 'movies'}}"])
    XCTAssertEqual(parsed[1].showExpressions, ["{{mtype == 'movies'}}"])
  }

  func testRangeSliderProjectsDefaultArrayAndWritesSelectedLowerBound() throws {
    let control = try XCTUnwrap(
      PluginFilterControlParser.parse([
        .object([
          "component": .string("VRangeSlider"),
          "props": .object([
            "v-model": .string("user_rating"),
            "min": .int(1),
            "max": .int(10),
          ]),
        ])
      ]).first
    )

    XCTAssertEqual(control.selectionValue(from: .array([.int(1), .int(10)])), .int(1))
    let stored = control.storedValue(for: .int(7))
    XCTAssertEqual(stored, .array([.int(7), .int(10)]))

    let path = ExploreViewModel.appendingQuery(
      to: "plugin/IMDbDiscover/discover",
      values: [control.field: stored]
    )
    let items = try XCTUnwrap(URLComponents(string: path)?.queryItems)
    XCTAssertEqual(
      items.filter { $0.name == "user_rating[]" }.compactMap(\.value),
      ["7", "10"]
    )
  }

  func testPluginFilterMultiSelectParsedAsMultiChoiceAndSingleStaysChoice() {
    let parsed = PluginFilterControlParser.parse([
      .object([
        "component": .string("VSelect"),
        "props": .object([
          "model": .string("genre"),
          "multiple": .bool(true),
          "items": .array([
            .string("动作"),
            .string("喜剧"),
          ]),
        ]),
      ]),
      .object([
        "component": .string("VSelect"),
        "props": .object([
          "model": .string("country"),
          "items": .array([.string("美国")]),
        ]),
      ]),
    ])

    XCTAssertEqual(parsed[0].kind, .multiChoice)
    XCTAssertEqual(parsed[0].options.map(\.title), ["动作", "喜剧"])
    XCTAssertEqual(parsed[1].kind, .choice)
  }

  func testPluginFilterShowExpressionControlsVisibility() throws {
    let parsed = PluginFilterControlParser.parse([
      .object([
        "component": .string("VChipGroup"),
        "props": .object([
          "model": .string("ranked_list"),
          "show": .string("{{mtype == 'movies'}}"),
        ]),
      ]),
    ])
    let control = try XCTUnwrap(parsed.first)

    XCTAssertTrue(control.isVisible(in: ["mtype": .string("movies")]))
    XCTAssertFalse(control.isVisible(in: ["mtype": .string("series")]))
    XCTAssertFalse(control.isVisible(in: [:]))
  }

  func testPluginFilterUnparsableExpressionStaysVisible() throws {
    let parsed = PluginFilterControlParser.parse([
      .object([
        "component": .string("VChipGroup"),
        "props": .object([
          "model": .string("ranked_list"),
          "show": .string("{{mtype === 'movies'}}"),
        ]),
      ]),
    ])
    let control = try XCTUnwrap(parsed.first)

    XCTAssertTrue(control.isVisible(in: ["mtype": .string("movies")]))
  }

  func testPluginFilterExpressionEvaluator() {
    let values: [String: JSONValue] = [
      "mtype": .string("movies"),
      "year": .int(2026),
      "flag": .bool(true),
    ]

    XCTAssertEqual(
      PluginFilterExpression.evaluate("{{mtype == 'movies'}}", values: values),
      true
    )
    XCTAssertEqual(
      PluginFilterExpression.evaluate("mtype != 'series'", values: values),
      true
    )
    XCTAssertEqual(
      PluginFilterExpression.evaluate("{{mtype == 'series' && flag}}", values: values),
      false
    )
    XCTAssertEqual(
      PluginFilterExpression.evaluate("{{mtype == 'series' || flag}}", values: values),
      true
    )
    XCTAssertEqual(
      PluginFilterExpression.evaluate("{{ !flag }}", values: values),
      false
    )
    XCTAssertEqual(
      PluginFilterExpression.evaluate("{{ year == 2026 }}", values: values),
      true
    )
    XCTAssertEqual(
      PluginFilterExpression.evaluate("{{ missing == 'x' }}", values: values),
      false
    )
    XCTAssertEqual(
      PluginFilterExpression.evaluate("{{ (mtype == 'movies') }}", values: values),
      true
    )
    XCTAssertNil(PluginFilterExpression.evaluate("{{ mtype === 'movies' }}", values: values))
    XCTAssertNil(PluginFilterExpression.evaluate("", values: values))
  }

  func testPluginFilterToggleValueRoundTrips() {
    let values = ExploreViewModel.applyingPluginFilter(
      field: "using_rating",
      value: .bool(true),
      to: ["using_rating": .bool(false)],
      defaults: ["using_rating": .bool(false)],
      depends: nil
    )

    XCTAssertEqual(values["using_rating"], .bool(true))
  }

  func testPluginFilterUserWriteAlignsWithWebDefaultRestore() {
    // Web ExtraSourceView watch：falsy 值且有非空默认时恢复默认
    let restored = ExploreViewModel.applyingPluginFilter(
      field: "user_rating",
      value: .null,
      to: ["user_rating": .array([.int(1), .int(10)])],
      defaults: ["user_rating": .array([.int(1), .int(10)])],
      depends: nil
    )
    XCTAssertEqual(restored["user_rating"], .array([.int(1), .int(10)]))

    // 空数组是 truthy，不触发恢复（Web 多选清空语义）
    let cleared = ExploreViewModel.applyingPluginFilter(
      field: "genre",
      value: .array([]),
      to: ["genre": .array([.string("动作")])],
      defaults: ["genre": .array([.string("动作")])],
      depends: nil
    )
    XCTAssertEqual(cleared["genre"], .array([]))

    // 默认 false 的开关关闭后保持 false
    let turnedOff = ExploreViewModel.applyingPluginFilter(
      field: "using_rating",
      value: .bool(false),
      to: ["using_rating": .bool(false)],
      defaults: ["using_rating": .bool(false)],
      depends: nil
    )
    XCTAssertEqual(turnedOff["using_rating"], .bool(false))
  }

  func testAppendingQueryFlattensArrayWithBrackets() throws {
    let path = ExploreViewModel.appendingQuery(
      to: "plugin/ImdbSource/imdb-discover",
      values: [
        "user_rating": .array([.int(1), .int(10)]),
        "mtype": .string("series"),
      ]
    )
    let components = try XCTUnwrap(URLComponents(string: path))
    let items = try XCTUnwrap(components.queryItems)

    XCTAssertEqual(
      items.filter { $0.name == "user_rating[]" }.compactMap(\.value),
      ["1", "10"]
    )
    XCTAssertEqual(items.first(where: { $0.name == "mtype" })?.value, "series")
  }

  func testAppendingQuerySkipsNullAndEmptyCollections() throws {
    let path = ExploreViewModel.appendingQuery(
      to: "plugin/TvdbDiscover/tvdb_discover",
      values: [
        "empty": .array([]),
        "nilValue": .null,
        "genre": .array([.string("动作"), .string("喜剧")]),
      ]
    )
    let components = try XCTUnwrap(URLComponents(string: path))
    let items = try XCTUnwrap(components.queryItems)

    XCTAssertNil(items.first(where: { $0.name == "empty" }))
    XCTAssertNil(items.first(where: { $0.name == "nilValue" }))
    XCTAssertEqual(
      items.filter { $0.name == "genre[]" }.compactMap(\.value),
      ["动作", "喜剧"]
    )
  }

  func testAppendingQueryFlattensNestedObjectWithBrackets() throws {
    let path = ExploreViewModel.appendingQuery(
      to: "plugin/Example/discover",
      values: [
        "filter": .object([
          "genre": .string("动作"),
          "year": .int(2026),
        ])
      ]
    )
    let components = try XCTUnwrap(URLComponents(string: path))
    let items = try XCTUnwrap(components.queryItems)

    XCTAssertEqual(items.first(where: { $0.name == "filter[genre]" })?.value, "动作")
    XCTAssertEqual(items.first(where: { $0.name == "filter[year]" })?.value, "2026")
  }

  func testAppendingQueryUsesIndexesForArrayOfObjects() throws {
    let path = ExploreViewModel.appendingQuery(
      to: "plugin/Example/discover",
      values: [
        "x": .array([
          .object(["a": .int(1)]),
          .object(["a": .int(2)]),
        ])
      ]
    )
    let components = try XCTUnwrap(URLComponents(string: path))
    let items = try XCTUnwrap(components.queryItems)

    XCTAssertEqual(items.first(where: { $0.name == "x[0][a]" })?.value, "1")
    XCTAssertEqual(items.first(where: { $0.name == "x[1][a]" })?.value, "2")
  }

  func testAppendingQueryMixedArrayUsesIndexesAndSkipsNull() throws {
    let path = ExploreViewModel.appendingQuery(
      to: "plugin/Example/discover",
      values: [
        "x": .array([
          .object(["a": .int(1)]),
          .int(2),
          .null,
        ])
      ]
    )
    let components = try XCTUnwrap(URLComponents(string: path))
    let items = try XCTUnwrap(components.queryItems)

    XCTAssertEqual(items.first(where: { $0.name == "x[0][a]" })?.value, "1")
    XCTAssertEqual(items.first(where: { $0.name == "x[1]" })?.value, "2")
    XCTAssertNil(items.first(where: { $0.name == "x[2]" }))
  }

  func testAppendingQueryKeepsExistingQueryAndEncodesSpecialChars() throws {
    let path = ExploreViewModel.appendingQuery(
      to: "plugin/ImdbSource/imdb-discover?apikey=signed%23token",
      values: [
        "user_rating": .array([.int(1), .int(10)]),
        "name": .string("C++"),
      ]
    )
    let components = try XCTUnwrap(URLComponents(string: path))
    let items = try XCTUnwrap(components.queryItems)

    XCTAssertEqual(items.first(where: { $0.name == "apikey" })?.value, "signed#token")
    XCTAssertEqual(items.first(where: { $0.name == "name" })?.value, "C++")
    XCTAssertEqual(
      items.filter { $0.name == "user_rating[]" }.compactMap(\.value),
      ["1", "10"]
    )
  }

  func testPluginFilterRangeSliderBoundaries() {
    func parse(_ props: [String: JSONValue]) -> [PluginFilterOption] {
      let controls = PluginFilterControlParser.parse([
        .object([
          "component": .string("VRangeSlider"),
          "props": .object(props),
        ]),
      ])
      return controls.first?.options ?? []
    }

    XCTAssertTrue(parse(["v-model": .string("x"), "min": .string("5"), "max": .string("1")]).isEmpty)
    XCTAssertTrue(
      parse(["v-model": .string("x"), "min": .string("0"), "max": .string("1e308"), "step": .string("1")]).isEmpty
    )
    XCTAssertTrue(
      parse(["v-model": .string("x"), "min": .string("0"), "max": .string("10"), "step": .string("0.0001")]).isEmpty
    )
    XCTAssertTrue(
      parse(["v-model": .string("x"), "min": .string("0"), "max": .string("10"), "step": .string("0")]).isEmpty
    )
    XCTAssertEqual(
      parse(["v-model": .string("x"), "min": .string("1"), "max": .string("3"), "step": .string("0.5")])
        .map(\.value),
      [.int(1), .double(1.5), .int(2), .double(2.5), .int(3)]
    )
    XCTAssertEqual(
      parse(["v-model": .string("x"), "min": .string("0"), "max": .string("1e10"), "step": .string("1e9")])
        .map(\.value),
      (0...10).map { .int($0 * 1_000_000_000) }
    )
    let huge = parse([
      "v-model": .string("x"),
      "min": .string("1e300"),
      "max": .string("1e301"),
      "step": .string("1e299"),
    ])
    XCTAssertEqual(huge.count, 91)
    XCTAssertEqual(huge.first?.value, .double(1e300))
  }

  func testPluginFilterNestedVisibilityCombinesWithAnd() throws {
    let parsed = PluginFilterControlParser.parse([
      .object([
        "component": .string("div"),
        "props": .object([
          "show": .string("{{mtype == 'movies'}}"),
        ]),
        "content": .array([
          .object([
            "component": .string("VChipGroup"),
            "props": .object([
              "model": .string("ranked_list"),
              "show": .string("{{flag}}"),
            ]),
          ]),
        ]),
      ]),
    ])
    let control = try XCTUnwrap(parsed.first)

    XCTAssertEqual(control.showExpressions, ["{{mtype == 'movies'}}", "{{flag}}"])
    XCTAssertTrue(
      control.isVisible(in: ["mtype": .string("movies"), "flag": .bool(true)])
    )
    XCTAssertFalse(
      control.isVisible(in: ["mtype": .string("movies"), "flag": .bool(false)])
    )
    XCTAssertFalse(
      control.isVisible(in: ["mtype": .string("series"), "flag": .bool(true)])
    )
  }

  func testPluginFilterSameFieldDifferentVisibilityBranchesBothSurvive() {
    let parsed = PluginFilterControlParser.parse([
      .object([
        "component": .string("VChipGroup"),
        "props": .object([
          "model": .string("genre"),
          "show": .string("{{mtype == 'movies'}}"),
        ]),
      ]),
      .object([
        "component": .string("VChipGroup"),
        "props": .object([
          "model": .string("genre"),
          "show": .string("{{mtype == 'series'}}"),
        ]),
      ]),
    ])

    XCTAssertEqual(parsed.count, 2)
    XCTAssertEqual(parsed[0].showExpressions, ["{{mtype == 'movies'}}"])
    XCTAssertEqual(parsed[1].showExpressions, ["{{mtype == 'series'}}"])
  }

  func testPluginFilterMultiplePropIsCaseInsensitive() {
    let parsed = PluginFilterControlParser.parse([
      .object([
        "component": .string("VSelect"),
        "props": .object([
          "model": .string("genre"),
          "Multiple": .bool(true),
          "items": .array([.string("动作")]),
        ]),
      ]),
    ])

    XCTAssertEqual(parsed.first?.kind, .multiChoice)
  }

  func testPluginFilterDependencyClearsDependentField() {
    let values = ExploreViewModel.applyingPluginFilter(
      field: "country",
      value: .string("jpn"),
      to: [
        "country": .string("usa"),
        "company": .int(12),
      ],
      depends: ["company": ["country"]]
    )

    XCTAssertEqual(values["country"], .string("jpn"))
    XCTAssertEqual(values["company"], .null)
  }

  func testDynamicPathKeepsQueryAndRejectsExternalPaths() throws {
    let path = ExploreViewModel.appendingQuery(
      to: "plugin/TvdbDiscover/tvdb_discover?apikey=signed%23token",
      values: [
        "mtype": .string("series"),
        "year": .int(2026),
      ]
    )
    let endpoint = try relativeBackendEndpoint(path: path, params: ["page": "3"])
    let components = try XCTUnwrap(URLComponents(string: endpoint))
    let items = try XCTUnwrap(components.queryItems)

    XCTAssertEqual(components.path, "/plugin/TvdbDiscover/tvdb_discover")
    XCTAssertEqual(items.first(where: { $0.name == "apikey" })?.value, "signed#token")
    XCTAssertEqual(items.first(where: { $0.name == "mtype" })?.value, "series")
    XCTAssertEqual(items.first(where: { $0.name == "year" })?.value, "2026")
    XCTAssertEqual(items.first(where: { $0.name == "page" })?.value, "3")
    XCTAssertThrowsError(try relativeBackendEndpoint(path: "https://example.com/media"))
    XCTAssertThrowsError(try relativeBackendEndpoint(path: "../system/global"))
    XCTAssertThrowsError(try relativeBackendEndpoint(path: "//example.com/media"))
    XCTAssertEqual(
      redactedEndpointForLogging(
        "/plugin/TvdbDiscover/tvdb_discover?apikey=secret-token#signed"
      ),
      "/plugin/TvdbDiscover/tvdb_discover"
    )
  }

  func testQueryAppendKeepsExistingPercentEncodingAndEscapesLiteralPlus() throws {
    let endpoint = try relativeBackendEndpoint(
      path: "discover/tmdb/popular?token=A%2BB&lang=zh-CN",
      params: ["q": "C++", "name": "张三"]
    )
    let components = try XCTUnwrap(URLComponents(string: endpoint))

    let rawQuery = try XCTUnwrap(components.percentEncodedQuery)
    XCTAssertTrue(rawQuery.contains("token=A%2BB"))
    XCTAssertTrue(rawQuery.contains("lang=zh-CN"))
    XCTAssertTrue(rawQuery.contains("q=C%2B%2B"))
    XCTAssertTrue(rawQuery.contains("name=%E5%BC%A0%E4%B8%89"))
    XCTAssertFalse(rawQuery.contains("q=C++"))

    let items = try XCTUnwrap(components.queryItems)
    XCTAssertEqual(items.first(where: { $0.name == "token" })?.value, "A+B")
    XCTAssertEqual(items.first(where: { $0.name == "q" })?.value, "C++")
    XCTAssertEqual(items.first(where: { $0.name == "name" })?.value, "张三")
  }

  func testExploreAppendingQueryKeepsPercentEncodedTokenAndEncodesValues() throws {
    let path = ExploreViewModel.appendingQuery(
      to: "plugin/Example/example?token=A%2BB&apikey=signed%23token",
      values: [
        "keyword": .string("C++ 电影"),
        "year": .int(2026),
      ]
    )
    let components = try XCTUnwrap(URLComponents(string: path))

    let rawQuery = try XCTUnwrap(components.percentEncodedQuery)
    XCTAssertTrue(rawQuery.contains("token=A%2BB"))
    XCTAssertTrue(rawQuery.contains("apikey=signed%23token"))
    XCTAssertTrue(rawQuery.contains("keyword=C%2B%2B%20%E7%94%B5%E5%BD%B1"))
    XCTAssertTrue(rawQuery.contains("year=2026"))

    let items = try XCTUnwrap(components.queryItems)
    XCTAssertEqual(items.first(where: { $0.name == "token" })?.value, "A+B")
    XCTAssertEqual(items.first(where: { $0.name == "keyword" })?.value, "C++ 电影")
  }

  func testDiscoverSourceSnapshotDeduplicatesBuiltInsAndPluginPrefixes() {
    let sources = ExploreViewModel.updatedExtraSourceSnapshot(
      previous: [],
      response: [
        descriptor(name: "伪装内置", prefix: "anilist", path: "plugin/fake"),
        descriptor(name: "TheTVDB", prefix: "tvdb", path: "plugin/tvdb"),
        descriptor(name: "重复 TheTVDB", prefix: "tvdb", path: "plugin/duplicate"),
      ]
    )

    XCTAssertEqual(sources.map(\.name), ["TheTVDB"])
    XCTAssertEqual(
      ExploreViewModel.updatedExtraSourceSnapshot(previous: sources, response: nil),
      sources
    )
  }

  func testRecommendSourcesKeepBuiltInOrderAndDeduplicatePaths() {
    let shelves = RecommendViewModel.mergedShelves(extras: [
      RecommendSourceDescriptor(
        name: "重复 AniList",
        api_path: "anilist/trending",
        type: "动画"
      ),
      RecommendSourceDescriptor(
        name: "插件电影",
        api_path: "plugin/example/movies?mode=hot",
        type: "电影"
      ),
      RecommendSourceDescriptor(
        name: "重复插件",
        api_path: "plugin/example/movies?mode=hot",
        type: "电影"
      ),
    ])

    XCTAssertEqual(shelves.filter { $0.id == "anilist/trending" }.count, 1)
    XCTAssertEqual(shelves.filter { $0.id == "plugin/example/movies?mode=hot" }.count, 1)
    XCTAssertEqual(
      shelves.first(where: { $0.id == "plugin/example/movies?mode=hot" })?.category,
      .movie
    )
  }

  func testCustomFocusAndSourceRefreshGuardsRemainInViewCode() throws {
    let exploreView = try source("MoviePilot-TV/Views/Pages/ExploreView.swift")
    XCTAssertFalse(exploreView.contains("customFocusedIndex"))
    XCTAssertTrue(exploreView.contains("case .custom: 0"))
    XCTAssertTrue(
      exploreView.contains(".focusable(hasFocusableFilters && focusedPickerIndex == nil)")
    )

    try assertDiscoveryGuardPrecedesFetch(
      in: source("MoviePilot-TV/ViewModels/ExploreViewModel.swift"),
      fetchCall: "fetchDiscoverSources()"
    )
    try assertDiscoveryGuardPrecedesFetch(
      in: source("MoviePilot-TV/ViewModels/RecommendViewModel.swift"),
      fetchCall: "fetchRecommendSources()"
    )
  }

  func testAllRootMediaDestinationsRouteCollectionsDefensively() throws {
    for relativePath in [
      "MoviePilot-TV/Views/Pages/HomeView.swift",
      "MoviePilot-TV/Views/Pages/ExploreView.swift",
      "MoviePilot-TV/Views/Pages/RecommendView.swift",
      "MoviePilot-TV/Views/Pages/SearchView.swift",
    ] {
      let viewSource = try source(relativePath)
      XCTAssertTrue(
        viewSource.contains(".navigationDestination(for: ImageNavigationEntry.self)"),
        relativePath
      )
      XCTAssertTrue(viewSource.contains("ImageNavigationDestination(entry: entry)"), relativePath)
    }

    let destinationSource = try source(
      "MoviePilot-TV/Views/Components/ImageNavigationDestination.swift"
    )
    let collectionDestination = try XCTUnwrap(
      destinationSource.range(of: "CollectionDetailView(")
    )
    let mediaDestination = try XCTUnwrap(
      destinationSource.range(of: "MediaDetailContainerView(")
    )
    XCTAssertTrue(destinationSource.contains("if let collectionID = media.collection_id"))
    XCTAssertLessThan(collectionDestination.lowerBound, mediaDestination.lowerBound)
  }

  func testSharedMediaEntryPointsUseCollectionSafePreloadGate() throws {
    for relativePath in [
      "MoviePilot-TV/Views/Components/MediaGridView.swift",
      "MoviePilot-TV/Views/Components/MediaContextMenu.swift",
      "MoviePilot-TV/Views/Pages/SearchView.swift",
      "MoviePilot-TV/Views/Pages/MediaDetailView.swift",
    ] {
      let viewSource = try source(relativePath)
      XCTAssertTrue(
        viewSource.contains("navigationCoordinator.push(")
          || viewSource.contains("preloadFocusedCandidateIfNeeded("),
        relativePath
      )
      XCTAssertFalse(
        viewSource.contains("MediaPreloader.shared.preload(for:"),
        relativePath
      )
    }

    let containerSource = try source("MoviePilot-TV/Views/Pages/MediaDetailContainerView.swift")
    XCTAssertTrue(containerSource.contains("preloadAuxiliary("))
    XCTAssertFalse(containerSource.contains("preloadIfNeeded(for:"))
    XCTAssertFalse(
      containerSource.contains("MediaPreloader.shared.preload(for:"),
      "详情 task 必须由 navigation entry 注入，destination 重求值不得创建 orphan task"
    )
  }

  private func descriptor(name: String, prefix: String, path: String)
    -> DiscoverSourceDescriptor
  {
    DiscoverSourceDescriptor(
      name: name,
      mediaid_prefix: prefix,
      api_path: path,
      filter_params: [:],
      filter_ui: [],
      depends: nil
    )
  }

  private func assertDiscoveryGuardPrecedesFetch(
    in source: String,
    fetchCall: String
  ) throws {
    let refresh = try XCTUnwrap(source.range(of: "func refreshSources"))
    let fetch = try XCTUnwrap(
      source.range(of: fetchCall, range: refresh.upperBound..<source.endIndex)
    )
    XCTAssertNotNil(
      source.range(
        of: "guard apiService.canAccess(.discovery)",
        range: refresh.upperBound..<fetch.lowerBound
      )
    )
  }

  private func source(_ relativePath: String) throws -> String {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath))
  }
}
