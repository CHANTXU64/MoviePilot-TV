import Combine
import SwiftUI

enum ReorganizePreviewOutcome: Equatable {
  case notGenerated
  case generated(allSucceeded: Bool)

  var shouldPresent: Bool {
    if case .generated = self { return true }
    return false
  }
}

/// 手动整理方式的版本能力。`reflink`（引用链接）从后端 v3.1.9 起由整理链路支持；
/// 更早的版本会以「不支持的整理方式」拒绝执行，因此不在旧后端上展示该选项。
enum ReorganizeTransferCapability {
  static let reflinkMinimumBackendVersion = "v3.1.9"

  static func supportsReflink(backendVersion: String?) -> Bool {
    guard let version = MoviePilotVersion(backendVersion),
      let minimum = MoviePilotVersion(reflinkMinimumBackendVersion)
    else { return false }
    return version >= minimum
  }

  /// 手动整理可选的整理方式，顺序与 Web 整理对话框一致；`reflink` 仅在 v3.1.9+ 出现。
  static func availableTransferTypes(backendVersion: String?) -> [String] {
    var types = ["", "copy", "move", "link", "softlink"]
    if supportsReflink(backendVersion: backendVersion) {
      types.append("reflink")
    }
    return types
  }

  static func normalizedTransferType(_ transferType: String?) -> String {
    transferType?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
  }

  /// 空字符串表示「自动」，始终视为当前可选；具体方式必须出现在当前版本的选项里。
  static func allows(_ transferType: String?, backendVersion: String?) -> Bool {
    availableTransferTypes(backendVersion: backendVersion)
      .contains(normalizedTransferType(transferType))
  }

  static func title(for transferType: String) -> String {
    switch normalizedTransferType(transferType) {
    case "": return "自动"
    case "copy": return "复制"
    case "move": return "移动"
    case "link": return "硬链接"
    case "softlink": return "软链接"
    case "reflink": return "引用链接"
    default:
      let normalized = normalizedTransferType(transferType)
      return normalized.isEmpty ? transferType : normalized
    }
  }
}

@MainActor
class ReorganizeViewModel: ObservableObject {
  // 显式非隔离析构，避开 tvOS 18 的隔离析构回部署崩溃。
  nonisolated deinit {}

  @Published var form: ReorganizeForm
  @Published var directories: [TransferDirectoryConf] = []
  @Published var storages: [StorageConf] = []
  @Published var targetDirectoryOptions: [PickerOption<String>] = []
  @Published var isLoading = true
  @Published var isSubmitting = false
  @Published var isPreviewing = false
  @Published var previewData: ManualTransferPreviewData?
  @Published var episodeGroups: [EpisodeGroup] = []
  @Published var isEpisodeGroupsLoading = false
  @Published var isEpisodeDetailDisabled = false  // 视图绑定，表示“指定集数”是否禁用
  @Published var mediaSource: MediaSearchSource
  @Published var mediaId: String

  @Published var errorMessage: String?
  @Published var loadErrorMessage: String?
  @Published var mutationRetryMessage: String?

  private let apiService: APIService
  private let validateBeforeSubmit: (() async throws -> String?)?
  private let previewRequest: (ReorganizeForm) async throws -> ManualTransferPreviewData
  private let sourceSession: APIServiceSessionSnapshot?
  private var cancellables = Set<AnyCancellable>()

  private var logIds: [Int] = []
  private let explicitTargetStorage: String?
  private var directoryInferredTargetStorage: String?
  /// 已经处理过的后端版本。同版本的设置刷新不是“刚变为支持”，不能借此覆盖用户的「自动」。
  private var didObserveBackendVersion = false
  private var observedBackendVersion: String?
  /// 上一轮门禁文案。用户改到合法方式后，只清掉仍然等于这句的底部错误，避免提示残留。
  private var presentedTransferTypeGateMessage: String?

  // 用于视图判断当前是否是对历史记录发起整理
  var isFromHistory: Bool {
    return !logIds.isEmpty
  }

  var isMediaIdValid: Bool {
    mediaSource.isValidManualId(mediaId)
  }

  /// 手动整理可选的整理方式；`reflink` 仅后端 v3.1.9 起出现，旧版本或版本未知时不展示。
  var transferTypes: [String] {
    ReorganizeTransferCapability.availableTransferTypes(
      backendVersion: apiService.settings?.BACKEND_VERSION)
  }

  /// 选择器实际列出的整理方式。目录配置的方式当前不可用时去掉「自动」：
  /// 请求省略整理方式后，服务端会改用该目录的 `transfer_type`。
  var selectableTransferTypes: [String] {
    var types = transferTypes
    if unavailableDirectoryTransferType != nil {
      types.removeAll { $0.isEmpty }
    }
    let explicit = ReorganizeTransferCapability.normalizedTransferType(form.transfer_type)
    if !explicit.isEmpty, !types.contains(explicit) {
      types.append(explicit)
    }
    return types
  }

  /// 选了当前后端不支持的整理方式，或目录配置的方式不受支持且表单仍是「自动」时，阻止预览和提交。
  var transferTypeGateMessage: String? {
    transferTypeGateMessage(
      transferType: form.transfer_type,
      backendVersion: apiService.settings?.BACKEND_VERSION
    )
  }

  init(
    logIds: [Int] = [],
    fileItem: FileItem?,
    targetStorage: String? = nil,
    validateBeforeSubmit: (() async throws -> String?)? = nil,
    sourceSession: APIServiceSessionSnapshot? = nil,
    previewRequest: ((ReorganizeForm) async throws -> ManualTransferPreviewData)? = nil,
    apiService: APIService = .shared
  ) {
    self.apiService = apiService
    self.validateBeforeSubmit = validateBeforeSubmit
    self.previewRequest = previewRequest ?? { form in
      try await apiService.previewManualTransfer(form: form)
    }
    self.sourceSession = sourceSession
    self.logIds = logIds
    self.explicitTargetStorage = targetStorage?.trimmingCharacters(in: .whitespacesAndNewlines)
      .nonEmpty
    let defaultMediaSource =
      MediaSearchSource(rawValue: apiService.settings?.RECOGNIZE_SOURCE ?? "")
      ?? .themoviedb
    self.mediaSource = defaultMediaSource
    self.mediaId = ""

    // 在 init() 中初始化 form，为必须的属性提供默认值
    self.form = ReorganizeForm(
      fileitem: fileItem,
      logid: logIds.first ?? 0,
      target_storage: explicitTargetStorage,
      transfer_type: nil,
      target_path: "",
      min_filesize: 0,
      scrape: nil,
      from_history: false,
      media_source: defaultMediaSource.rawValue
    )

    $form
      .dropFirst()
      .sink { [weak self] form in
        guard let self else { return }
        self.previewData = nil
        // 用发布出来的表单。订阅回调里再读 `self.form` 可能仍是写入前的值。
        self.syncTransferTypeGateFeedback(
          transferType: form.transfer_type,
          backendVersion: self.apiService.settings?.BACKEND_VERSION
        )
      }
      .store(in: &cancellables)

    $mediaId
      .dropFirst()
      .sink { [weak self] _ in
        self?.previewData = nil
        self?.form.episode_group = nil
        self?.episodeGroups = []
      }
      .store(in: &cancellables)

    // 监听表单变化以更新“指定集数”的禁用状态
    $form
      // 只关心影响禁用逻辑的字段
      .map(\.episode_format)
      .removeDuplicates()
      .sink { [weak self] _ in
        self?.updateEpisodeDetailDisabledState()
      }
      .store(in: &cancellables)

    // 初始化禁用状态
    updateEpisodeDetailDisabledState()

    // 用这次发布的版本判断是否刚变为支持。同版本的设置刷新不能覆盖用户选的「自动」。
    apiService.$settings.sink { [weak self] settings in
      guard let self else { return }
      let backendVersion = settings?.BACKEND_VERSION
      self.reapplySupportedDirectoryTransferType(backendVersion: backendVersion)
      self.syncTransferTypeGateFeedback(
        transferType: self.form.transfer_type,
        backendVersion: backendVersion
      )
      self.objectWillChange.send()
    }.store(in: &cancellables)
  }

  func loadConfig() async {
    guard apiService.canAccess(.manage) else {
      clearLoadedConfig()
      isLoading = false
      return
    }
    let sessionSnapshot = apiService.sessionSnapshot()
    loadErrorMessage = nil
    isLoading = true
    defer { isLoading = false }
    do {
      async let dirsTask = apiService.fetchDirectories()
      async let storagesTask = apiService.fetchStorages()

      let (loadedDirectories, loadedStorages) = try await (dirsTask, storagesTask)
      guard apiService.isSessionUnchanged(from: sessionSnapshot),
        apiService.canAccess(.manage)
      else {
        clearLoadedConfig()
        return
      }

      self.directories = loadedDirectories
      self.storages = loadedStorages

      self.targetDirectoryOptions =
        [PickerOption(title: "自动", value: "")]
        + Array(
          Set(self.directories.compactMap { $0.library_path })
        ).sorted().map {
          PickerOption(title: $0, value: $0)
        }

    } catch {
      Logger.error("Failed to load reorganize options: \(error)")
      clearLoadedConfig()
      loadErrorMessage = "整理设置加载失败，请重试。"
    }
  }

  private func clearLoadedConfig() {
    directories = []
    storages = []
    targetDirectoryOptions = [PickerOption(title: "自动", value: "")]
  }

  func submit(background: Bool) async -> Bool {
    guard !isSubmitting else { return false }
    guard sourceSession.map({ apiService.isSessionUnchanged(from: $0) }) ?? true,
      apiService.canAccess(.manage)
    else { return false }
    errorMessage = nil
    mutationRetryMessage = nil
    if blockedTransferTypeMessage() != nil {
      return false
    }
    guard isMediaIdValid else {
      errorMessage = "媒体 ID 格式无效。"
      return false
    }
    isSubmitting = true
    defer { isSubmitting = false }
    // 记录已受理成功的批次数，用于部分成功时给出准确反馈（与 Web 对齐，不改变重试范围）。
    var acceptedCount = 0
    do {
      if let message = try await validateBeforeSubmit?() {
        mutationRetryMessage = message
        return false
      }

      let snapshot = sourceSession ?? apiService.sessionSnapshot()
      guard apiService.isSessionUnchanged(from: snapshot) else {
        throw CancellationError()
      }
      var failureMessages: [String] = []
      for submittedForm in preparedSubmissionForms() {
        guard apiService.isSessionUnchanged(from: snapshot) else {
          throw CancellationError()
        }
        let result = try await apiService.manualTransfer(
          form: submittedForm,
          background: background
        )
        guard apiService.isSessionUnchanged(from: snapshot) else {
          throw CancellationError()
        }
        if result.success {
          acceptedCount += 1
        } else if let message = result.message?.trimmingCharacters(
          in: .whitespacesAndNewlines
        ), !message.isEmpty {
          failureMessages.append(message)
        } else if !result.success {
          failureMessages.append("")
        }
      }

      if failureMessages.isEmpty {
        return true
      } else {
        Logger.error("Reorganize request returned false")
        let backendMessages = failureMessages.filter { !$0.isEmpty }
        errorMessage =
          acceptedCount > 0
          ? "部分文件已提交整理，其余失败，请重试。"
            + (backendMessages.isEmpty ? "" : "失败原因：" + backendMessages.joined(separator: "；"))
          : (
            backendMessages.isEmpty
              ? "整理没有开始，请检查设置后重试。"
              : backendMessages.joined(separator: "；")
          )
        return false
      }
    } catch is CancellationError {
      return false
    } catch {
      Logger.error("Failed to reorganize: \(error)")
      errorMessage =
        acceptedCount > 0
        ? "部分文件已提交整理，其余失败，请重试。"
        : "整理没有开始，请稍后重试。"
      return false
    }
  }

  @discardableResult
  func preview() async -> ReorganizePreviewOutcome {
    guard !isPreviewing else { return .notGenerated }
    guard apiService.canAccess(.manage) else { return .notGenerated }
    errorMessage = nil
    if blockedTransferTypeMessage() != nil {
      return .notGenerated
    }
    guard isMediaIdValid else {
      errorMessage = "媒体 ID 格式无效。"
      return .notGenerated
    }
    isPreviewing = true
    defer { isPreviewing = false }

    let snapshot = apiService.sessionSnapshot()
    var merged = ManualTransferPreviewData.empty
    for submittedForm in preparedSubmissionForms() {
      do {
        guard apiService.isSessionUnchanged(from: snapshot) else { return .notGenerated }
        let data = try await previewRequest(submittedForm)
        guard apiService.isSessionUnchanged(from: snapshot) else { return .notGenerated }
        merged.items.append(contentsOf: data.items)
        if let message = data.message, !message.isEmpty {
          merged.message = [merged.message, message].compactMap(\.self).joined(separator: "；")
        }
      } catch is CancellationError {
        return .notGenerated
      } catch {
        let batchItems = submittedForm.fileitems ?? []
        let batchSource =
          batchItems.count == 1
          ? batchItems[0].path
          : (batchItems.isEmpty ? nil : "共 \(batchItems.count) 个文件")
        merged.items.append(
          ManualTransferPreviewItem(
            source: submittedForm.fileitem?.path ?? batchSource
              ?? "历史记录 \(submittedForm.logid)",
            target: nil,
            target_dir: nil,
            success: false,
            message: error.localizedDescription,
            type: submittedForm.fileitem?.type ?? batchItems.first?.type,
            title: submittedForm.fileitem?.name
              ?? (batchItems.count == 1 ? batchItems.first?.name : nil),
            season: nil,
            episode: nil,
            episode_end: nil,
            part: nil,
            org_string: nil,
            apply_words: nil,
            resource_team: nil,
            customization: nil
          ))
      }
    }

    var seenItems = Set<PreviewItemIdentity>()
    merged.items = merged.items.filter { seenItems.insert(PreviewItemIdentity($0)).inserted }
    let failures = merged.items.filter { $0.success == false }.count
    merged.summary = ManualTransferPreviewSummary(
      total: merged.items.count,
      success: merged.items.count - failures,
      failed: failures
    )
    guard apiService.isSessionUnchanged(from: snapshot) else { return .notGenerated }
    previewData = merged
    if failures > 0 {
      errorMessage = "预览完成，其中 \(failures) 项无法整理。"
    }
    return .generated(allSucceeded: failures == 0)
  }

  private struct PreviewItemIdentity: Hashable {
    let storage: String
    let source: String
    let target: String
    let success: Bool

    init(_ item: ManualTransferPreviewItem) {
      // v3.1.0 的源存储是身份的一部分；旧响应缺少它时保持原来的单存储语义。
      storage = item.source_storage ?? item.source_item?.storage ?? ""
      source = item.source ?? ""
      target = item.target ?? ""
      success = item.success
    }
  }

  func selectTargetPath(_ path: String) {
    guard form.target_path != path else { return }
    form.target_path = path
    updateForm(for: path)
  }

  func selectMediaSource(_ source: MediaSearchSource) {
    guard mediaSource != source else { return }
    mediaSource = source
    mediaId = ""
    form.tmdbid = nil
    form.doubanid = nil
    form.bangumiid = nil
    form.anilistid = nil
    form.media_source = source.rawValue
    form.media_id = nil
    form.episode_group = nil
    episodeGroups = []
  }

  func selectMediaType(_ type: String?) {
    form.type_name = type
    if type != "电视剧" {
      form.episode_group = nil
      episodeGroups = []
    }
  }

  func selectManualMedia(_ media: MediaInfo, mediaId: String) {
    self.mediaId = mediaId
    if let typeName = ManualMediaSelection.typeName(for: media) {
      selectMediaType(typeName)
    }
  }

  var episodeGroupQueryKey: String {
    "\(mediaSource.rawValue)|\(form.type_name ?? "")|\(mediaId)"
  }

  var episodeGroupOptions: [PickerOption<String>] {
    [PickerOption(title: "默认剧集组", value: "")]
      + episodeGroups.map {
        PickerOption(
          title: "\($0.name)（\($0.group_count) 季 · \($0.episode_count) 集）",
          value: $0.id
        )
      }
  }

  func loadEpisodeGroups() async {
    let requestedKey = episodeGroupQueryKey
    let normalizedId = mediaId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard mediaSource == .themoviedb,
      form.type_name == "电视剧",
      let tmdbId = Int(normalizedId),
      tmdbId > 0
    else {
      episodeGroups = []
      isEpisodeGroupsLoading = false
      return
    }

    isEpisodeGroupsLoading = true
    do {
      let groups = try await apiService.fetchEpisodeGroups(tmdbId: tmdbId)
      guard requestedKey == episodeGroupQueryKey else { return }
      episodeGroups = groups
    } catch {
      guard requestedKey == episodeGroupQueryKey else { return }
      episodeGroups = []
    }
    if requestedKey == episodeGroupQueryKey {
      isEpisodeGroupsLoading = false
    }
  }

  func preparedSingleSubmissionForm() -> ReorganizeForm {
    var submittedForm = form
    applyManualIdentity(to: &submittedForm)
    return submittedForm
  }

  func preparedSubmissionForms() -> [ReorganizeForm] {
    if logIds.count > 1 {
      return logIds.map { id in
        var batchForm = form
        batchForm.logid = id
        batchForm.fileitem = nil
        batchForm.fileitems = nil
        applyManualIdentity(to: &batchForm)
        return batchForm
      }
    }
    return [preparedSingleSubmissionForm()]
  }

  private func applyManualIdentity(to target: inout ReorganizeForm) {
    let normalized = mediaId.trimmingCharacters(in: .whitespacesAndNewlines)
    target.tmdbid = nil
    target.doubanid = nil
    target.bangumiid = nil
    target.anilistid = nil
    if normalized.isEmpty {
      // MoviePilot 的可选媒体身份要求 source/id 成对出现；自动识别时两者都省略。
      target.media_source = nil
      target.media_id = nil
    } else {
      target.media_source = mediaSource.rawValue
      target.media_id = normalized
    }
    if mediaSource != .themoviedb || target.type_name != "电视剧" {
      target.episode_group = nil
    }
  }

  private func updateForm(for newPath: String?) {
    guard let newPath = newPath, !newPath.isEmpty else {
      // 路径为空时, 恢复到`自动`整理条件；只保留历史记录或用户显式传入的目标存储。
      form.target_storage = explicitTargetStorage
      directoryInferredTargetStorage = nil
      form.transfer_type = nil
      form.scrape = nil
      form.library_type_folder = nil
      form.library_category_folder = nil
      return
    }

    if let directory = directories.first(where: { $0.library_path == newPath }) {
      form.target_storage = directory.library_storage
      directoryInferredTargetStorage = directory.library_storage
      // 不改目录配置本身。当前后端不支持该目录的整理方式时也不写入表单：
      // 留空会被服务端当成「用目录里的方式」，旧后端会在执行时拒绝 reflink。
      if ReorganizeTransferCapability.normalizedTransferType(form.transfer_type).isEmpty {
        let directoryType = ReorganizeTransferCapability.normalizedTransferType(
          directory.transfer_type)
        if directoryType.isEmpty
          || ReorganizeTransferCapability.allows(directoryType, backendVersion: backendVersion)
        {
          form.transfer_type = directoryType.isEmpty ? nil : directoryType
        }
      }
      form.scrape = directory.scraping?.value ?? false
      form.library_category_folder = directory.library_category_folder?.value ?? false
      form.library_type_folder = directory.library_type_folder?.value ?? false
    } else {
      if form.target_storage == directoryInferredTargetStorage {
        form.target_storage = explicitTargetStorage
      }
      directoryInferredTargetStorage = nil
      if ReorganizeTransferCapability.normalizedTransferType(form.transfer_type).isEmpty {
        form.transfer_type = "copy"
      }
      form.scrape = false
      form.library_category_folder = false
      form.library_type_folder = false
    }
  }

  private var backendVersion: String? {
    apiService.settings?.BACKEND_VERSION
  }

  private var matchedDirectory: TransferDirectoryConf? {
    let path = form.target_path
    guard !path.isEmpty else { return nil }
    return directories.first { $0.library_path == path }
  }

  /// 目录配置里非空、且当前版本不能提交的整理方式。
  private var unavailableDirectoryTransferType: String? {
    unavailableDirectoryTransferType(for: backendVersion)
  }

  private func unavailableDirectoryTransferType(for backendVersion: String?) -> String? {
    guard let directory = matchedDirectory else { return nil }
    let directoryType = ReorganizeTransferCapability.normalizedTransferType(directory.transfer_type)
    guard !directoryType.isEmpty,
      !ReorganizeTransferCapability.allows(directoryType, backendVersion: backendVersion)
    else { return nil }
    return directoryType
  }

  private func transferTypeGateMessage(
    transferType: String?,
    backendVersion: String?
  ) -> String? {
    let explicit = ReorganizeTransferCapability.normalizedTransferType(transferType)
    if !explicit.isEmpty,
      !ReorganizeTransferCapability.allows(explicit, backendVersion: backendVersion)
    {
      let title = ReorganizeTransferCapability.title(for: explicit)
      return "当前后端不支持整理方式「\(title)」，请改选其他方式。"
    }
    if explicit.isEmpty, let directoryType = unavailableDirectoryTransferType(for: backendVersion) {
      let title = ReorganizeTransferCapability.title(for: directoryType)
      return "该目录的整理方式是「\(title)」，当前后端不支持。请改选其他整理方式。"
    }
    return nil
  }

  /// 版本变为支持目录里的整理方式时，只补写仍为空的表单。不重跑 `updateForm`，以免覆盖刮削和目录开关。
  private func reapplySupportedDirectoryTransferType(backendVersion: String?) {
    let previous = didObserveBackendVersion ? observedBackendVersion : nil
    let versionChanged = didObserveBackendVersion && previous != backendVersion
    didObserveBackendVersion = true
    observedBackendVersion = backendVersion
    guard versionChanged,
      ReorganizeTransferCapability.normalizedTransferType(form.transfer_type).isEmpty,
      let directoryType = unavailableDirectoryTransferType(for: previous),
      ReorganizeTransferCapability.allows(directoryType, backendVersion: backendVersion)
    else { return }
    form.transfer_type = directoryType
  }

  private func syncTransferTypeGateFeedback(transferType: String?, backendVersion: String?) {
    let message = transferTypeGateMessage(
      transferType: transferType,
      backendVersion: backendVersion
    )
    if let previous = presentedTransferTypeGateMessage,
      errorMessage == previous,
      message != previous
    {
      errorMessage = nil
    }
    presentedTransferTypeGateMessage = message
  }

  private func blockedTransferTypeMessage() -> String? {
    guard let message = transferTypeGateMessage else { return nil }
    errorMessage = message
    presentedTransferTypeGateMessage = message
    return message
  }

  /// 根据表单状态更新“指定集数”输入框的禁用状态
  private func updateEpisodeDetailDisabledState() {
    // 如果指定了剧集格式，则应允许用户输入指定的集数
    if let format = form.episode_format, !format.isEmpty {
      isEpisodeDetailDisabled = false
      return
    }
    // 如果是从历史记录模式进入，意味着没有实体文件，应允许用户手动指定
    if isFromHistory {
      isEpisodeDetailDisabled = false
      return
    }
    // 对于文件整理模式，如果是文件夹类型，则禁用此功能
    isEpisodeDetailDisabled = (form.fileitem?.type == "dir")
  }
}

private extension String {
  var nonEmpty: String? {
    isEmpty ? nil : self
  }
}
