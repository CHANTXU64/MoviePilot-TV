import XCTest

@testable import MoviePilot_TV

final class SystemViewDefaultStyleTests: XCTestCase {
  func testSystemViewDoesNotUsePrivateSettingsImplementation() throws {
    let source = try Self.source(at: "MoviePilot-TV/Views/Pages/SystemView.swift")

    XCTAssertTrue(source.contains("struct SystemView: View"))
    XCTAssertFalse(source.contains("TVSettingsView("))
    XCTAssertFalse(source.contains("PrivateTVSettings"))
    XCTAssertFalse(source.contains("TVSettingKit"))
    XCTAssertFalse(source.contains("_TSK"))
  }

  func testContentViewLabelsSystemTabAsSettings() throws {
    let source = try Self.source(at: "MoviePilot-TV/Views/ContentView.swift")

    XCTAssertTrue(
      source.contains(
        "SystemView(isSelected: selectedTab == .system)"
      )
    )
    XCTAssertTrue(source.contains("Label(\"设置\", systemImage: \"gear\")"))
    XCTAssertFalse(source.contains("Label(\"系统\", systemImage: \"gear\")"))
  }

  func testStatusTabSelectionDrivesAuthoritativeTransferHistoryRefresh() throws {
    let contentSource = try Self.source(at: "MoviePilot-TV/Views/ContentView.swift")
    let statusSource = try Self.source(at: "MoviePilot-TV/Views/Pages/StatusView.swift")
    let historySource = try Self.source(
      at: "MoviePilot-TV/Views/Pages/TransferHistoryView.swift"
    )

    XCTAssertTrue(contentSource.contains("StatusView(isSelected: selectedTab == .status)"))
    XCTAssertTrue(
      statusSource.contains(
        "TransferHistoryView(viewModel: transferHistoryViewModel, isSelected: isSelected)"
      )
    )
    XCTAssertTrue(historySource.contains(".task(id: isSelected)"))
    XCTAssertTrue(historySource.contains("await Self.runAutoRefresh("))
  }

  func testRecommendTabSelectionDrivesSuccessEmptyReactivation() throws {
    let contentSource = try Self.source(at: "MoviePilot-TV/Views/ContentView.swift")
    let recommendSource = try Self.source(at: "MoviePilot-TV/Views/Pages/RecommendView.swift")

    XCTAssertTrue(
      contentSource.contains("RecommendView(isSelected: selectedTab == .recommend)"))
    XCTAssertTrue(recommendSource.contains(".task(id: isSelected)"))
    XCTAssertTrue(recommendSource.contains("guard isSelected else { return }"))
    XCTAssertTrue(recommendSource.contains("await viewModel.refreshSources()"))
  }

  func testTransferHistoryMutationIntentsCarryTheirSourceSession() throws {
    let source = try Self.source(
      at: "MoviePilot-TV/Views/Pages/TransferHistoryView.swift"
    )

    XCTAssertTrue(source.contains("let sourceSession = viewModel.captureMutationSession()"))
    XCTAssertTrue(source.contains("TransferHistoryItemMutationIntent("))
    XCTAssertTrue(source.contains("TransferHistoryBatchMutationIntent("))
    XCTAssertTrue(source.contains("sourceSession: intent.sourceSession"))
    XCTAssertTrue(source.contains("sourceSession: sourceSession"))
  }

  func testSystemViewKeepsConnectionAppInfoAndChangelogEntryPoints() throws {
    let source = try Self.source(at: "MoviePilot-TV/Views/Pages/SystemView.swift")

    XCTAssertTrue(source.contains("\"连接与APP信息\""))
    XCTAssertTrue(source.contains("\"连接\""))
    XCTAssertTrue(source.contains("\"APP 信息\""))
    XCTAssertTrue(source.contains("\"版本更新历史\""))
    XCTAssertTrue(source.contains("row(\"版本更新历史\", showsDisclosure: true)"))
    XCTAssertTrue(source.contains("push(.changelog)"))
    XCTAssertTrue(source.contains("\"MoviePilot TV APP\""))
    XCTAssertFalse(source.contains("\"连接与版本\""))
  }

  func testUpdateNoticeOnlyChecksWhenSettingsTabIsSelected() throws {
    let source = try Self.source(at: "MoviePilot-TV/Views/Pages/SystemView.swift")

    XCTAssertTrue(source.contains(".onChange(of: isSelected)"))
    XCTAssertTrue(source.contains("guard isSelected, updateNotice == nil else { return }"))
    XCTAssertTrue(source.contains("AppChangelog.markPresented(entry)"))
    XCTAssertTrue(source.contains(".alert(item: $updateNotice)"))
  }

  func testChangelogSheetUsesReadableTvOSLayout() throws {
    let source = try Self.source(at: "MoviePilot-TV/Views/Pages/SystemView.swift")

    XCTAssertTrue(source.contains(".frame(width: 1_440, height: 1_025)"))
    XCTAssertTrue(source.contains(".font(.callout)"))
    XCTAssertTrue(source.contains(".font(isPrimary ? .headline.bold() : .subheadline.bold())"))
    XCTAssertTrue(source.contains("Text(entry.releaseDate)"))
    XCTAssertTrue(source.contains("value: \"\\(entry.releaseDate) · MoviePilot \\(entry.compatibleMoviePilotVersion)\""))
  }

  func testReleaseWorkflowUsesMergedChangelogAsReleaseNotesSource() throws {
    let source = try Self.source(at: ".agents/prompts/release.md")

    XCTAssertTrue(source.contains("## 更新内容"))
    XCTAssertTrue(source.contains("### 新增功能"))
    XCTAssertFalse(source.contains("## 主要更新"))
    XCTAssertTrue(source.contains("只有兼容 MoviePilot 后端基线相对上一发布版本发生变化时"))
    XCTAssertTrue(source.contains("`highlights` → `更新内容` 标题下最前面的摘要条目"))
    XCTAssertTrue(source.contains("Changelog 改动未合并到 `main` 前，不得进入正式发布"))
    XCTAssertTrue(source.contains("保持文字和顺序一致"))
  }

  func testSearchSettingsAndHeaderKeepPermissionAndLayoutContract() throws {
    let systemSource = try Self.source(at: "MoviePilot-TV/Views/Pages/SystemView.swift")
    let searchSource = try Self.source(at: "MoviePilot-TV/Views/Pages/SearchView.swift")

    XCTAssertTrue(
      systemSource.contains("case .mediaSourceSelection:\n            if canConfigureRecommendations {")
    )
    XCTAssertTrue(systemSource.contains("case .siteSelection:\n            if canConfigureSearch {"))
    XCTAssertTrue(
      systemSource.contains("if canConfigureRecommendations {\n        section(\"聚合搜索\")")
    )
    XCTAssertTrue(searchSource.contains("ZStack(alignment: .trailing)"))
    XCTAssertTrue(searchSource.contains("ZStack(alignment: .leading)"))
    XCTAssertTrue(searchSource.contains(".frame(width: 300, alignment: .trailing)"))
    XCTAssertTrue(searchSource.contains(".frame(width: 300, alignment: .leading)"))
    XCTAssertTrue(searchSource.contains("private var visibleFilterSearchType: SearchType"))
    XCTAssertTrue(searchSource.contains("visibleFilterSearchType == .resource"))
    XCTAssertTrue(searchSource.contains("visibleFilterSearchType == .unified"))
    XCTAssertTrue(
      searchSource.contains("Text(\"搜索来源：\\(viewModel.mediaSourceButtonLabel)\")")
    )
  }

  func testSubscriptionCompatibilityChecklistTracksPermissionContractRisk() throws {
    let source = try Self.source(at: "docs/subscription-compatibility-checklist.md")

    XCTAssertTrue(source.contains("## 订阅权限与快照"))
    XCTAssertTrue(source.contains("permissions.subscribe"))
    XCTAssertTrue(source.contains("GET /subscribe/"))
    XCTAssertTrue(source.contains("普通用户与超级用户"))
    XCTAssertTrue(source.contains("不要把“过滤异常记录”当成长期契约"))
    XCTAssertTrue(source.contains("best_version"))
    XCTAssertTrue(source.contains("完整 PUT"))
    XCTAssertTrue(source.contains("订阅写入、状态修改、搜索、重置、删除和 Fork"))
    XCTAssertTrue(source.contains("MoviePilot v2.15.3 起"))
    XCTAssertTrue(source.contains("同一媒体同一季可以存在不同剧集组的订阅"))
    XCTAssertTrue(source.contains("这与后端已按剧集组区分查重/存在性的行为并不对称"))
  }

  func testSubscribeSeasonViewHidesAvailabilityBadgeWhenStatusTextIsNil() throws {
    let source = try Self.source(at: "MoviePilot-TV/Views/Pages/SubscribeSeasonView.swift")

    XCTAssertTrue(source.contains("let bottomLeft = statusText.map"))
    XCTAssertTrue(source.contains("bottomLeftText: bottomLeft"))
  }

  func testSystemViewExitHandlersOnlyRunWhenSettingsTabIsActive() throws {
    let source = try Self.source(at: "MoviePilot-TV/Views/Pages/SystemView.swift")

    XCTAssertTrue(
      source.contains("SystemSettingsRootBackObserver(isEnabled: isSelected && isActive && page == .root)")
    )
    XCTAssertTrue(
      source.contains(".systemSettingsExitCommand(isEnabled: isSelected && isActive && page != .root")
    )
  }

  func testMissingPersistedFilterRuleDoesNotDisplayAsNoFilter() throws {
    let source = try Self.source(at: "MoviePilot-TV/Views/Pages/SystemView.swift")

    XCTAssertTrue(source.contains("guard let ruleId else { return \"不过滤\" }"))
    XCTAssertTrue(
      source.contains("return viewModel.customFilterRules.first(where: { $0.id == ruleId })?.name ?? \"规则未加载\"")
    )
    XCTAssertFalse(source.contains("?.name ?? \"不过滤\""))
  }

  func testLogoutRequiresConfirmationAlert() throws {
    let source = try Self.source(at: "MoviePilot-TV/Views/Pages/SystemView.swift")

    XCTAssertTrue(source.contains("@State private var showLogoutConfirmation = false"))
    XCTAssertTrue(source.contains("showLogoutConfirmation = true"))
    XCTAssertTrue(source.contains(".alert(\"退出登录\", isPresented: $showLogoutConfirmation)"))
    XCTAssertTrue(source.contains("Button(\"确认退出登录\", role: .destructive)"))
    XCTAssertTrue(source.contains("viewModel.logout()"))
    XCTAssertFalse(source.contains("APIService.shared.logout()"))
  }

  func testSettingsPreviewUsesGlassLogoAsset() throws {
    let source = try Self.source(at: "MoviePilot-TV/Views/Pages/SystemView.swift")

    XCTAssertTrue(source.contains("Image(\"SettingsLogoGlass\")"))
    XCTAssertFalse(source.contains("Image(\"App Icon\")"))
  }

  func testPreviewKeepsSettingsListAtOriginalLeadingPosition() throws {
    let source = try Self.source(at: "MoviePilot-TV/Views/Pages/SystemView.swift")

    XCTAssertTrue(source.contains("private static let previewWidth: CGFloat = 600"))
    XCTAssertTrue(source.contains("private static let horizontalPadding: CGFloat = 240"))
    XCTAssertTrue(source.contains("private static let columnSpacing: CGFloat = 210"))
    XCTAssertFalse(source.contains("private static let columnSpacing: CGFloat = 270"))
  }

  func testSessionChangePreloaderCleanupUsesUnifiedSessionState() throws {
    let source = try Self.source(at: "MoviePilot-TV/ViewModels/MediaPreloader.swift")

    XCTAssertTrue(source.contains("apiService.$session"))
    XCTAssertTrue(source.contains("session.token == nil"))
    XCTAssertTrue(source.contains("session.uiIdentity != self.observedSessionUIIdentity"))
    XCTAssertTrue(source.contains("if shouldClear { self.clearAll() }"))
  }

  func testContentViewNormalizesHiddenSelectedTabOnAppear() throws {
    let source = try Self.source(at: "MoviePilot-TV/Views/ContentView.swift")

    XCTAssertTrue(source.contains(".onAppear {"))
    XCTAssertTrue(
      source.contains(
        "selectedTab = ContentViewModel.resolvedSelectedTab(selectedTab, visibleTabs: viewModel.visibleTabs)"
      )
    )
  }

  func testMediaDetailHeaderFocusOnlyTargetsVisiblePermittedActions() throws {
    let source = try Self.source(at: "MoviePilot-TV/Views/Pages/MediaDetailView.swift")

    XCTAssertTrue(source.contains("@ObservedObject private var apiService = APIService.shared"))
    XCTAssertTrue(source.contains("private var canJumpToTMDB: Bool"))
    XCTAssertTrue(source.contains("private var preferredHeaderFocus: ButtonField?"))
    XCTAssertTrue(source.contains("if !hasAppeared, let preferredHeaderFocus"))
    XCTAssertFalse(source.contains(".defaultFocus($focusedButton, preferredHeaderFocus)"))
    XCTAssertTrue(source.contains("private var shouldShowOtherInfo: Bool"))
    XCTAssertTrue(source.contains("case subscribe, search, sites, otherInfo"))
    XCTAssertFalse(source.contains("equals: .tmdbJump"))
    XCTAssertTrue(source.contains(".focused($focusedButton, equals: .otherInfo)"))
  }

  func testMediaDetailSeasonInformationButtonStaysEnabled() throws {
    let source = try Self.source(at: "MoviePilot-TV/Views/Pages/MediaDetailView.swift")

    XCTAssertTrue(
      source.contains(".disabled(detail.canDirectlySubscribe && viewModel.isUnsubscribing)")
    )
    XCTAssertTrue(
      source.contains("if detail.canDirectlySubscribe && viewModel.isUnsubscribing")
    )
    XCTAssertFalse(source.contains("|| isSeasonInformationUnavailable"))
    XCTAssertFalse(source.contains(".opacity(isSeasonInformationUnavailable"))
    XCTAssertTrue(source.contains("分季信息加载失败"))
    XCTAssertTrue(source.contains("暂无分季信息"))
  }

  func testLoginViewUsesSettingsLogoNotificationAndStableLoadingLabel() throws {
    let source = try Self.source(at: "MoviePilot-TV/Views/Pages/LoginView.swift")

    XCTAssertTrue(source.contains("@EnvironmentObject private var notificationManager: NotificationManager"))
    XCTAssertTrue(source.contains("Image(\"SettingsLogoGlass\")"))
    XCTAssertTrue(source.contains("ProgressView()"))
    XCTAssertTrue(source.contains("Text(viewModel.isLoading ? \"登录中\" : \"登录\")"))
    XCTAssertTrue(source.contains("notificationManager.show(message: message, type: .error)"))
    XCTAssertFalse(source.contains("Image(systemName: \"film.stack.fill\")"))
    XCTAssertFalse(source.contains("Text(errorMessage)"))
    XCTAssertFalse(source.contains(".foregroundColor(.red)"))
  }

  func testHomeMediaHeaderPickerRowIsFocusSection() throws {
    let source = try Self.source(at: "MoviePilot-TV/Views/Pages/HomeView.swift")
    let start = try XCTUnwrap(source.range(of: "private struct MediaSectionView"))
    let end = try XCTUnwrap(source.range(of: "private struct SubscribeSectionView", range: start.upperBound..<source.endIndex))
    let mediaSection = String(source[start.lowerBound..<end.lowerBound])

    XCTAssertTrue(mediaSection.contains("Picker(\"服务器\", selection: $selectedServer)"))
    XCTAssertTrue(mediaSection.contains(".padding(.horizontal, 8)\n      .focusSection()"))
  }

  @MainActor
  func testSubscriptionCancellationFailureUsesGlobalNotification() throws {
    let homeSource = try Self.source(at: "MoviePilot-TV/Views/Pages/HomeView.swift")
    let detailSource = try Self.source(at: "MoviePilot-TV/Views/Pages/MediaDetailView.swift")
    let failureMessage = SubscriptionCancelConfirmation.failureMessage

    XCTAssertEqual(failureMessage, "取消订阅失败，请重试")
    XCTAssertTrue(homeSource.contains("guard try await viewModel.deleteSubscribe(subscribe: item) else"))
    XCTAssertTrue(homeSource.contains("message: SubscriptionCancelConfirmation.failureMessage"))
    XCTAssertTrue(detailSource.contains("guard await viewModel.cancelSubscription() else"))
    XCTAssertTrue(detailSource.contains("message: SubscriptionCancelConfirmation.failureMessage"))
  }

  func testSheetFeedbackAndLoadingStateUseSharedPatterns() throws {
    let sheetStyleSource = try Self.source(at: "MoviePilot-TV/Views/Components/SheetStyles.swift")
    let subscribeSheetSource = try Self.source(at: "MoviePilot-TV/Views/Sheets/SubscribeSheet.swift")
    let reorganizeSheetSource = try Self.source(at: "MoviePilot-TV/Views/Sheets/ReorganizeSheet.swift")
    let addDownloadSheetSource = try Self.source(at: "MoviePilot-TV/Views/Sheets/AddDownloadSheet.swift")
    let addDownloadViewModelSource = try Self.source(at: "MoviePilot-TV/ViewModels/AddDownloadViewModel.swift")
    let transferSource = try Self.source(at: "MoviePilot-TV/Views/Pages/TransferHistoryView.swift")
    let subscriptionModifierSource = try Self.source(at: "MoviePilot-TV/Views/Components/SubscriptionModifier.swift")
    let forkSource = try Self.source(at: "MoviePilot-TV/Views/Sheets/ForkSubscribeSheet.swift")

    XCTAssertTrue(sheetStyleSource.contains("struct SheetFeedbackView: View"))
    XCTAssertTrue(sheetStyleSource.contains("struct SheetActionButton: View"))
    XCTAssertTrue(subscribeSheetSource.contains("SheetActionButton("))
    XCTAssertTrue(reorganizeSheetSource.contains("SheetActionButton("))
    XCTAssertTrue(addDownloadSheetSource.contains("SheetActionButton("))
    XCTAssertTrue(addDownloadSheetSource.contains("SheetFeedbackView(message: message, actionTitle: \"重新加载\")"))
    XCTAssertTrue(forkSource.contains("SheetActionButton("))
    XCTAssertTrue(subscribeSheetSource.contains("title: viewModel.isNewSubscription ? \"确定\" : \"保存\""))
    XCTAssertTrue(reorganizeSheetSource.contains("title: \"开始整理\""))
    XCTAssertTrue(addDownloadSheetSource.contains("title: \"确定\""))
    XCTAssertTrue(forkSource.contains("title: \"复用订阅\""))
    XCTAssertFalse([subscribeSheetSource, reorganizeSheetSource, addDownloadSheetSource, forkSource].contains { $0.contains("失败，重试") })
    XCTAssertFalse(subscribeSheetSource.contains("NotificationManager"))
    XCTAssertFalse(reorganizeSheetSource.contains("NotificationManager"))
    XCTAssertFalse(addDownloadSheetSource.contains("NotificationManager"))
    XCTAssertFalse(addDownloadSheetSource.contains(".onChange(of: viewModel.errorMessage"))
    XCTAssertTrue(addDownloadViewModelSource.contains("下载设置没有加载完成，请重试。"))
    XCTAssertTrue(addDownloadViewModelSource.contains("暂时无法添加下载，请稍后重试。"))
    XCTAssertFalse(addDownloadViewModelSource.contains("error.localizedDescription"))
    XCTAssertTrue(transferSource.contains("notificationManager.show(message: message, type: .error)"))
    XCTAssertTrue(subscriptionModifierSource.contains("notificationManager.show(message: handler.notificationMessage, type: handler.notificationType)"))
    XCTAssertFalse(subscriptionModifierSource.contains(".alert(alertTitle, isPresented: $showAlert)"))
    XCTAssertTrue(forkSource.contains("subscriptionHandler.forkErrorMessage"))
  }

  func testReorganizeSheetUsesSheetRowSourceButtonPreviewSheetAndBackgroundSubmit() throws {
    let source = try Self.source(at: "MoviePilot-TV/Views/Sheets/ReorganizeSheet.swift")

    XCTAssertTrue(source.contains("SheetPicker(\n        title: \"媒体来源\""))
    XCTAssertTrue(source.contains("MediaSearchSource.allowed(for: .media).map"))
    XCTAssertFalse(source.contains("Picker(\"媒体来源\""))
    XCTAssertFalse(source.contains("private var sourceButtons: some View"))
    XCTAssertFalse(source.contains(".disabled((viewModel.form.type_name ?? \"\").isEmpty)"))
    XCTAssertTrue(source.contains("placeholder: \"自动判断\""))
    XCTAssertFalse(source.contains("placeholder: \"留空自动识别\""))
    XCTAssertTrue(source.contains("Image(systemName: \"magnifyingglass\")"))
    XCTAssertTrue(source.contains(".accessibilityLabel(\"搜索媒体\")"))
    XCTAssertFalse(source.contains("Label(\"搜索媒体\", systemImage: \"magnifyingglass\")"))
    XCTAssertTrue(source.contains(".sheet(isPresented: $showPreview)"))
    XCTAssertTrue(
      source.contains(
        "viewModel.mutationRetryMessage = nil\n            dismiss()"
      )
    )
    XCTAssertTrue(source.contains("private struct ReorganizePreviewSheet: View"))
    XCTAssertFalse(source.contains("@FocusState private var focusedPreviewIndex: Int?"))
    XCTAssertFalse(source.contains(".focusable()"))
    XCTAssertFalse(source.contains(".focused($focusedPreviewIndex, equals: index)"))
    XCTAssertTrue(source.contains("Button(action: {})"))
    XCTAssertTrue(source.contains(".buttonStyle(.card)"))
    XCTAssertFalse(source.contains(".scaleEffect(isFocused"))
    XCTAssertTrue(source.contains("color: item.success == false ? .red : .primary"))
    XCTAssertFalse(source.contains("color: item.success == false ? .red : .green"))
    XCTAssertTrue(source.contains(".contentMargins(28, for: .scrollContent)"))
    XCTAssertFalse(source.contains(".scrollClipDisabled()"))
    XCTAssertFalse(source.contains(".padding(20)"))
    XCTAssertTrue(source.contains("Text(\"整理预览\")"))
    XCTAssertFalse(source.contains("Label(\"整理预览\""))
    XCTAssertFalse(source.contains("Button(\"关闭\")"))
    XCTAssertFalse(source.contains("确认整理前后的文件路径"))
    XCTAssertFalse(source.contains("Text(value.formatted())\n          .font("))
    XCTAssertFalse(source.contains("Text(name)\n        .font("))
    XCTAssertFalse(source.contains("Image(systemName: icon)\n        .font("))
    XCTAssertFalse(source.contains("Image(systemName: \"arrow.right\")\n        .font("))
    XCTAssertFalse(source.contains(".font(.title3.bold())"))
    XCTAssertTrue(source.contains("HStack(spacing: 16)"))
    XCTAssertTrue(source.contains(".padding(14)\n    .padding(.leading, 10)"))
    XCTAssertTrue(
      source.contains(
        "    .padding(.top, 28)\n    .frame(width: 1400, height: 820)"
      )
    )
    XCTAssertTrue(source.contains("manualTransferPreviewFileName(from: item.source)"))
    XCTAssertTrue(source.contains("title: \"开始整理\""))
    XCTAssertTrue(source.contains("loadingTitle: \"整理中\""))
    XCTAssertFalse(source.contains("title: \"加入整理队列\""))
    XCTAssertFalse(source.contains("loadingTitle: \"加入中\""))
    XCTAssertFalse(source.contains("title: \"立即整理\""))
    XCTAssertTrue(source.contains("submit(background: true)"))
    XCTAssertFalse(source.contains("submit(background: false)"))
    XCTAssertTrue(source.contains("showMediaSearch = false"))
  }

  func testManualMediaSearchSheetKeepsSearchExplicitAndFocusable() throws {
    let source = try Self.source(at: "MoviePilot-TV/Views/Sheets/ManualMediaSearchSheet.swift")

    XCTAssertTrue(source.contains("NavigationStack {"))
    XCTAssertTrue(source.contains("Text(\"查询 \\(viewModel.source.title) ID\")"))
    XCTAssertFalse(source.contains("Text(\"搜索 \\(viewModel.source.title) 媒体\")"))
    XCTAssertTrue(source.contains("placeholder: \"输入媒体标题后搜索\""))
    XCTAssertFalse(source.contains("placeholder: \"输入标题后搜索\""))
    XCTAssertTrue(source.contains(".labelsHidden()"))
    XCTAssertTrue(source.contains(".focusSection()"))
    XCTAssertFalse(source.contains("Button(\"关闭\")"))
    XCTAssertEqual(source.components(separatedBy: "viewModel.search()").count - 1, 1)
    XCTAssertTrue(source.contains("Button {\n            Task { await viewModel.search() }"))
    XCTAssertTrue(source.contains(".disabled(viewModel.isLoading)"))
    XCTAssertTrue(source.contains("private var searchRevision = 0"))
    XCTAssertTrue(source.contains("searchRevision &+= 1"))
    XCTAssertTrue(source.contains("items = []"))
    XCTAssertTrue(source.contains("guard !title.isEmpty else {"))
    XCTAssertTrue(source.contains("guard searchRevision == revision else { return }"))
    XCTAssertTrue(
      source.contains(
        "if searchRevision == revision {\n        isLoading = false"
      )
    )
    XCTAssertFalse(
      source.contains(
        "keyword.trimmingCharacters(in: .whitespacesAndNewlines) == title"
      )
    )
    XCTAssertFalse(
      source.contains(
        "viewModel.keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty"
      )
    )
    XCTAssertFalse(source.contains(".onSubmit"))
    XCTAssertTrue(source.contains("source: viewModel.source"))
    XCTAssertTrue(source.contains("GridItem(.fixed(500), spacing: 36)"))
    XCTAssertFalse(source.contains(".padding(36)"))
    XCTAssertTrue(source.contains(".contentMargins(.vertical, 28, for: .scrollContent)"))
    XCTAssertFalse(source.contains(".scrollClipDisabled()"))
    XCTAssertEqual(
      source.components(separatedBy: ".padding(.horizontal, 28)").count - 1,
      2
    )
    XCTAssertFalse(source.contains(".padding(.horizontal, 40)"))
    XCTAssertTrue(
      source.contains(
        "      .padding(.top, 40)\n    }\n    .frame(width: 1092, height: 820)"
      )
    )
    XCTAssertFalse(source.contains(".frame(width: 1120, height: 780)"))
    XCTAssertFalse(source.contains(".frame(width: 1140, height: 820)"))
    XCTAssertFalse(source.contains(".frame(width: 1200, height: 820)"))
    XCTAssertFalse(source.contains(".frame(width: 1400, height: 820)"))
  }

  @MainActor
  func testManualMediaSearchClearsExistingResultsForEmptySubmission() async {
    let viewModel = ManualMediaSearchViewModel(source: .themoviedb)
    viewModel.items = [MediaInfo(tmdb_id: 42, title: "旧结果")]
    viewModel.keyword = "  "

    await viewModel.search()

    XCTAssertTrue(viewModel.items.isEmpty)
    XCTAssertFalse(viewModel.isLoading)
  }

  func testHorizontalLoadMoreIndicatorsAlignToPosterArea() throws {
    let detailSource = try Self.source(at: "MoviePilot-TV/Views/Pages/MediaDetailView.swift")
    let searchSource = try Self.source(at: "MoviePilot-TV/Views/Pages/SearchView.swift")

    XCTAssertTrue(detailSource.contains("posterCenteredLoadingIndicator(height: 315)"))
    XCTAssertTrue(detailSource.contains("posterCenteredLoadingIndicator(height: 384)"))
    XCTAssertTrue(searchSource.contains("posterCenteredLoadingIndicator(height: 384)"))
    XCTAssertTrue(searchSource.contains("posterCenteredLoadingIndicator(height: 315)"))
  }

  func testSeasonLoadFailureUsesRetryAndGlobalNotification() throws {
    let source = try Self.source(at: "MoviePilot-TV/Views/Pages/SubscribeSeasonView.swift")

    XCTAssertTrue(source.contains("@EnvironmentObject private var notificationManager: NotificationManager"))
    XCTAssertTrue(source.contains("viewModel.hasSeasonLoadError"))
    XCTAssertTrue(source.contains("Button"))
    XCTAssertTrue(source.contains("重试"))
    XCTAssertTrue(source.contains("await viewModel.retryLoadData()"))
    XCTAssertTrue(source.contains("notificationManager.show(message: message, type: .error)"))
    XCTAssertFalse(source.contains("// Error Banner"))
  }

  func testMediaDetailKeepsFirstRowPeekAndShortContentScrollRange() throws {
    let source = try Self.source(at: "MoviePilot-TV/Views/Pages/MediaDetailView.swift")

    XCTAssertTrue(source.contains(".frame(height: UIScreen.main.bounds.height * 0.94)"))
    XCTAssertTrue(source.contains("Color.clear\n              .frame(height: UIScreen.main.bounds.height)"))
    XCTAssertFalse(source.contains(".frame(minHeight: UIScreen.main.bounds.height, alignment: .top)"))
  }

  func testSystemViewModelRechecksPermissionBeforePublishingCustomRules() throws {
    let source = try Self.source(at: "MoviePilot-TV/ViewModels/SystemViewModel.swift")

    XCTAssertTrue(source.contains("let rules = try await apiService.fetchCustomFilterRules()"))
    XCTAssertTrue(source.contains("guard apiService.canRequestSuperUserEndpoints else {"))
    XCTAssertTrue(source.contains("customFilterRules = rules"))
  }

  func testSystemViewScopesLocalFeatureSettingsByPermission() throws {
    let viewSource = try Self.source(at: "MoviePilot-TV/Views/Pages/SystemView.swift")
    let viewModelSource = try Self.source(at: "MoviePilot-TV/ViewModels/SystemViewModel.swift")

    XCTAssertTrue(viewSource.contains("@ObservedObject private var apiService = APIService.shared"))
    XCTAssertTrue(viewSource.contains("private var canConfigureSubscriptions: Bool"))
    XCTAssertTrue(viewSource.contains("private var canConfigureSearch: Bool"))
    XCTAssertTrue(viewSource.contains("private var canConfigureCustomFilters: Bool"))
    XCTAssertTrue(viewSource.contains("apiService.canRequestSuperUserEndpoints"))
    XCTAssertTrue(viewSource.contains("if canConfigureSubscriptions {"))
    XCTAssertTrue(viewSource.contains("if canConfigureSearch {"))
    XCTAssertTrue(viewSource.contains("if canConfigureCustomFilters {"))
    XCTAssertFalse(viewSource.contains("guard canConfigureSearch else { return }"))
    XCTAssertTrue(viewSource.contains("guard canConfigureCustomFilters else { return }"))
    XCTAssertTrue(viewModelSource.contains("guard apiService.canAccess(.search) else {"))
  }

  func testRecommendBackendCompatibilityScansShelvesIndependently() throws {
    let source = try Self.source(at: "MoviePilot-TV-Tests/BackendCompatibilityTests.swift")

    XCTAssertTrue(source.contains("for shelf in RecommendViewModel.allShelves {"))
    XCTAssertTrue(source.contains("\"recommend shelf \\(shelf.title)\""))
    XCTAssertFalse(source.contains("\"recommend shelves\""))
  }

  func testFilterRuleGroupsCompatibilityProbeUsesSuperUserRequirement() throws {
    let source = try Self.source(at: "MoviePilot-TV-Tests/BackendCompatibilityTests.swift")
    let start = try XCTUnwrap(source.range(of: "\"filter-rule groups\""))
    let end = try XCTUnwrap(source.range(of: "\"custom filter rules\"", range: start.upperBound..<source.endIndex))
    let probe = String(source[start.lowerBound..<end.lowerBound])

    XCTAssertTrue(probe.contains("requirement: .superUser"))
    XCTAssertFalse(probe.contains("requirement: .permission(.subscribe)"))
  }

  private static func source(at path: String) throws -> String {
    let testFileURL = URL(fileURLWithPath: #filePath)
    let repositoryRoot = testFileURL.deletingLastPathComponent().deletingLastPathComponent()
    let sourceURL = repositoryRoot.appendingPathComponent(path)
    return try String(contentsOf: sourceURL)
  }
}
