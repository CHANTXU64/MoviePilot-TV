import Combine
import SwiftUI

@MainActor
class ReorganizeViewModel: ObservableObject {
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

  private let apiService: APIService
  private var cancellables = Set<AnyCancellable>()

  private var logIds: [Int] = []
  private let explicitTargetStorage: String?
  private var directoryInferredTargetStorage: String?

  // 用于视图判断当前是否是对历史记录发起整理
  var isFromHistory: Bool {
    return !logIds.isEmpty
  }

  var isMediaIdValid: Bool {
    MediaIdentifier.isValidManualMediaId(mediaId)
  }

  init(
    logIds: [Int] = [],
    fileItem: FileItem?,
    targetStorage: String? = nil,
    apiService: APIService = .shared
  ) {
    self.apiService = apiService
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

    // 监听 target_path 的变化
    $form
      .map(\.target_path)
      .removeDuplicates()
      .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
      .sink { [weak self] newPath in
        self?.updateForm(for: newPath)
      }
      .store(in: &cancellables)

    $form
      .dropFirst()
      .sink { [weak self] _ in
        self?.previewData = nil
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
    guard apiService.canAccess(.manage) else { return false }
    errorMessage = nil
    guard isMediaIdValid else {
      errorMessage = "媒体 ID 只能包含数字。"
      return false
    }
    isSubmitting = true
    defer { isSubmitting = false }
    do {
      var failureMessages: [String] = []
      for submittedForm in preparedSubmissionForms() {
        let result = try await apiService.manualTransfer(
          form: submittedForm,
          background: background
        )
        if !result.success, let message = result.message?.trimmingCharacters(
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
          backendMessages.isEmpty
          ? (
            logIds.count > 1
              ? "部分文件没有开始整理，请稍后重试。"
              : "整理没有开始，请检查设置后重试。"
          )
          : backendMessages.joined(separator: "；")
        return false
      }
    } catch {
      Logger.error("Failed to reorganize: \(error)")
      errorMessage = "整理没有开始，请稍后重试。"
      return false
    }
  }

  @discardableResult
  func preview() async -> Bool {
    guard apiService.canAccess(.manage) else { return false }
    errorMessage = nil
    guard isMediaIdValid else {
      errorMessage = "媒体 ID 只能包含数字。"
      return false
    }
    isPreviewing = true
    defer { isPreviewing = false }

    var merged = ManualTransferPreviewData.empty
    for submittedForm in preparedSubmissionForms() {
      do {
        let data = try await apiService.previewManualTransfer(form: submittedForm)
        merged.items.append(contentsOf: data.items)
        if let message = data.message, !message.isEmpty {
          merged.message = [merged.message, message].compactMap(\.self).joined(separator: "；")
        }
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

    var seenItems = Set<String>()
    merged.items = merged.items.filter {
      let key = [$0.source ?? "", $0.target ?? "", $0.success == false ? "failed" : "success"]
        .joined(separator: "|")
      return seenItems.insert(key).inserted
    }
    let failures = merged.items.filter { $0.success == false }.count
    merged.summary = ManualTransferPreviewSummary(
      total: merged.items.count,
      success: merged.items.count - failures,
      failed: failures
    )
    previewData = merged
    if failures > 0 {
      errorMessage = "预览完成，其中 \(failures) 项无法整理。"
    }
    return failures == 0
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
    target.media_source = mediaSource.rawValue
    target.media_id = normalized.isEmpty ? nil : normalized
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
      if (form.transfer_type ?? "").isEmpty {
        form.transfer_type = directory.transfer_type
      }
      form.scrape = directory.scraping?.value ?? false
      form.library_category_folder = directory.library_category_folder?.value ?? false
      form.library_type_folder = directory.library_type_folder?.value ?? false
    } else {
      if form.target_storage == directoryInferredTargetStorage {
        form.target_storage = explicitTargetStorage
      }
      directoryInferredTargetStorage = nil
      if (form.transfer_type ?? "").isEmpty {
        form.transfer_type = "copy"
      }
      form.scrape = false
      form.library_category_folder = false
      form.library_type_folder = false
    }
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
