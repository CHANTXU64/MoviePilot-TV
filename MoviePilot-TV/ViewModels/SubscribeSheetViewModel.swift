import Combine
import Foundation

@MainActor
class SubscribeSheetViewModel: ObservableObject {
  // 显式非隔离析构，避开 tvOS 18 的隔离析构回部署崩溃。
  nonisolated deinit {}

  @Published var subscribe: Subscribe
  private var original: Subscribe
  @Published var sites: [Site] = []
  @Published var downloaders: [DownloaderConf] = []
  @Published var directories: [TransferDirectoryConf] = []
  @Published var filterGroups: [FilterRuleGroup] = []
  @Published var episodeGroups: [EpisodeGroup] = []
  @Published var isLoading = false
  @Published var isSaving = false
  @Published var isSaved = false
  @Published var errorMessage: String?
  @Published var loadErrorMessage: String?
  @Published var canRetryLoad = false

  // 最后一次查询确认不存在时才保持为新订阅；查到既有记录后切换为编辑。
  @Published private(set) var isNewSubscription: Bool
  // 标记初始的“创建并暂停”操作序列是否成功
  private var isCreatedAndPaused = false
  private struct CreatedSubscriptionReceipt {
    let id: Int
    let profileKey: String
    let session: APIServiceSessionSnapshot
  }
  // 仅在最后一次查询明确不存在后，绑定本次 POST 返回的 ID、账号与会话。
  private var createdSubscriptionReceipt: CreatedSubscriptionReceipt?
  private var shouldRollbackCreatedSubscription = false
  private var isRollingBackCreatedSubscription = false
  // 用户在保存期间返回时，保存成功后只提示一次。
  private var shouldNotifySaveSuccessAfterDismiss = false

  private let apiService: APIService

  let qualityOptions = [
    (title: "全部", value: ""),
    (title: "蓝光原盘", value: "Blu-?Ray.+VC-?1|Blu-?Ray.+AVC|UHD.+blu-?ray.+HEVC|MiniBD"),
    (title: "Remux", value: "Remux"),
    (title: "蓝光", value: "Blu-?Ray"),
    (title: "UHD", value: "UHD|UltraHD"),
    (title: "WEB-DL", value: "WEB-?DL|WEB-?RIP"),
    (title: "HDTV", value: "HDTV"),
    (title: "H265", value: "[Hx].?265|HEVC"),
    (title: "H264", value: "[Hx].?264|AVC"),
  ]

  let resolutionOptions = [
    (title: "全部", value: ""),
    (title: "4K", value: "4K|2160p|x2160"),
    (title: "1080P", value: "1080[pi]|x1080"),
    (title: "720P", value: "720[pi]|x720"),
  ]

  let effectOptions = [
    (title: "全部", value: ""),
    (title: "杜比视界", value: "Dolby[\\s.]+Vision|DOVI|[\\s.]+DV[\\s.]+"),
    (title: "杜比全景声", value: "Dolby[\\s.]*\\+?Atmos|Atmos"),
    (title: "HDR", value: "[\\s.]+HDR[\\s.]+|HDR10|HDR10\\+"),
    (title: "SDR", value: "[\\s.]+SDR[\\s.]+"),
  ]

  var seasonOptions: [Int] {
    Array(0...100)
  }

  var totalEpisodeText: String {
    get { subscribe.total_episode.map(String.init) ?? "" }
    // 总集数只接受非负整数；空白、非法文本和负数都恢复为后端的自动值 nil。
    set { subscribe.total_episode = Int(newValue).flatMap { $0 >= 0 ? $0 : nil } }
  }

  var downloaderSelection: String {
    get { subscribe.downloader ?? "" }
    set { subscribe.downloader = newValue.isEmpty ? nil : newValue }
  }

  /// 订阅方式：沿用 Web「选择订阅方式」的三种说法，映射到 `best_version` / `best_version_full`。
  enum SubscribeMode: Hashable {
    case normal
    case bestVersion
    case bestVersionFull
  }

  private var isTV: Bool { subscribe.type == "电视剧" }

  /// 电视剧：普通订阅 / 分集洗版 / 全集洗版；其他类型只有普通订阅 / 洗版（与 Web 一致）。
  var subscribeModeOptions: [(title: String, value: SubscribeMode)] {
    isTV
      ? [("普通订阅", .normal), ("分集洗版", .bestVersion), ("全集洗版", .bestVersionFull)]
      : [("普通订阅", .normal), ("洗版", .bestVersion)]
  }

  /// 只在用户选择时写回；打开后不改动直接保存，两个字段保持原值。
  var subscribeMode: SubscribeMode {
    get {
      guard subscribe.best_version == 1 else { return .normal }
      return isTV && subscribe.best_version_full == 1 ? .bestVersionFull : .bestVersion
    }
    set {
      switch newValue {
      case .normal:
        subscribe.best_version = 0
        subscribe.best_version_full = 0
      case .bestVersion:
        subscribe.best_version = 1
        subscribe.best_version_full = 0
      case .bestVersionFull:
        subscribe.best_version = 1
        subscribe.best_version_full = 1
      }
    }
  }

  var subscribeModeTitle: String {
    let mode = subscribeMode
    return subscribeModeOptions.first { $0.value == mode }?.title ?? "普通订阅"
  }

  /// 集数范围，例如「1–6 集」「3–6 集」；没有总集数时不显示。
  /// 开始集数没填或为 0 时从 1 算（后端同样按 1 处理）；超出 1…总集数时照实写出，
  /// 不改成别的范围，免得和实际保存的开始集数对不上。
  var episodeRangeText: String? {
    guard isTV, let total = subscribe.total_episode, total > 0 else { return nil }
    let start = subscribe.start_episode.flatMap { $0 == 0 ? nil : $0 } ?? 1
    return (1...total).contains(start) ? "\(start)–\(total) 集" : "第 \(start) 集起，共 \(total) 集"
  }

  /// 编辑订阅的进度，例如「已有 3 / 6 集」，按已保存的记录算，不随正在改的设置变化。
  /// 与 Web 订阅卡一致：已有 = 总集数 − 缺失集数，限定在 0…总集数；没有总集数时不显示。
  var progressText: String? {
    guard original.type == "电视剧", let total = original.total_episode, total > 0 else {
      return nil
    }
    let downloaded = min(max(total - (original.lack_episode ?? 0), 0), total)
    return "已有 \(downloaded) / \(total) 集"
  }

  /// 订阅状态，与 Web 订阅卡一致：S 已暂停、P 待定中，其余为订阅中。按已保存的记录。
  enum SavedState {
    case active, paused, pending

    var title: String {
      switch self {
      case .active: "订阅中"
      case .paused: "已暂停"
      case .pending: "待定中"
      }
    }

    var systemImage: String {
      switch self {
      case .active: AppSymbol.subscriptionActive
      case .paused: AppSymbol.subscriptionPaused
      case .pending: AppSymbol.subscriptionPending
      }
    }
  }

  var savedState: SavedState {
    switch original.state {
    case "S": .paused
    case "P": .pending
    default: .active
    }
  }

  /// 站点摘要：不选表示使用默认站点；选了一个显示站点名，找不到名字或选了多个时显示数量。
  /// 菜单行和设置标签共用这一套规则，只是文案不同。
  func sitesSummary(empty: String = "默认", count: (Int) -> String = { "已选 \($0) 个" }) -> String {
    let ids = subscribe.sites ?? []
    if ids.isEmpty { return empty }
    if ids.count == 1, let site = sites.first(where: { $0.id == ids[0] }) { return site.name }
    return count(ids.count)
  }

  /// 规则组摘要：不选表示使用默认规则。
  var filterGroupsSummary: String {
    let groups = subscribe.filter_groups ?? []
    if groups.isEmpty { return "默认" }
    return groups.count == 1 ? groups[0] : "已选 \(groups.count) 个"
  }

  /// 分辨率的显示名；值不在选项里时照原样显示。
  var resolutionTitle: String? {
    guard let value = MediaIdentifier.normalizedString(subscribe.resolution) else { return nil }
    return resolutionOptions.first { $0.value == value }?.title ?? value
  }

  var mediaCategoryText: String {
    get { subscribe.media_category ?? "" }
    set {
      // 输入框确认时会回写原文本；内容未变时不能顺带清掉隐藏的分类 ID。
      guard newValue != mediaCategoryText else { return }
      subscribe.media_category = newValue.isEmpty ? nil : newValue
      subscribe.media_category_id =
        subscribe.media_category == nil ? nil : original.media_category_id
    }
  }

  /// 身份字段与 `SubscriptionWriteDTO` 的差量写入一致。新建订阅不确认。
  /// 已解析且低于 v3.2.0 的后端不会清空进度，直接保存。
  var willResetSubscriptionProgressOnSave: Bool {
    guard !isNewSubscription, (subscribe.id ?? 0) > 0 else { return false }
    guard SubscribeIdentityResetConfirmation.backendResetsProgress(
      backendVersion: apiService.settings?.BACKEND_VERSION
    ) else { return false }
    return subscribe.type != original.type
      || subscribe.media_source != original.media_source
      || subscribe.media_id != original.media_id
      || subscribe.season != original.season
      || subscribe.episode_group != original.episode_group
      || subscribe.music_type != original.music_type
  }

  // F-135：与 `AddDownloadViewModel.targetDirectories` 同一套规范化 —— 先 trim、再丢空、
  // 最后去重。原实现先去重、从不 trim，于是纯空白路径会被当成合法项留在列表里。
  var savePathOptions: [String] {
    var seen = Set<String>()
    return directories.compactMap {
      $0.download_path?.trimmingCharacters(in: .whitespacesAndNewlines)
    }.filter {
      !$0.isEmpty && seen.insert($0).inserted
    }
  }

  init(
    subscribe: Subscribe,
    isNewSubscription: Bool = false,
    apiService: APIService = .shared
  ) {
    self.subscribe = subscribe
    self.original = subscribe
    self.isNewSubscription = isNewSubscription && subscribe.id == nil
    self.apiService = apiService
  }

  /// 返回这次是否真正加载完成（订阅已就绪、选项已加载）。
  /// 失败、被取消、会话变了、Sheet 已关闭要回滚时都返回 false，调用方不能只看有没有错误信息。
  @discardableResult
  func loadData() async -> Bool {
    guard !isLoading else { return false }
    guard apiService.canAccess(.subscribe) else {
      clearLoadedOptions()
      return false
    }

    loadErrorMessage = nil
    canRetryLoad = false
    let sessionSnapshot = apiService.sessionSnapshot()
    isLoading = true
    defer { isLoading = false }

    // 1. 如果是新订阅，最后确认不存在后再执行“创建 -> 暂停 -> 获取”序列
    if isNewSubscription && !isCreatedAndPaused {
      do {
        if let receipt = currentCreatedSubscriptionReceipt() {
          if shouldRollbackCreatedSubscription {
            await rollbackCreatedSubscriptionIfNeeded()
            clearLoadedOptions()
            return false
          }
          guard try await prepareCreatedSubscription(id: receipt.id, from: sessionSnapshot) else {
            return false
          }
        } else {
          let media = subscribe.navigationMediaInfo()
          guard media.apiMediaId != nil else {
            canRetryLoad = true
            loadErrorMessage = "暂时无法确认订阅状态，请重试。"
            return false
          }

          // 该查询不读取状态缓存；查询与 POST 之间不再插入其他异步步骤。
          let existing = try await apiService.fetchSubscriptionLookup(
            media: media,
            season: subscribe.season
          )
          guard canPublishLoadResult(from: sessionSnapshot) else {
            clearLoadedOptions()
            return false
          }
          guard !shouldRollbackCreatedSubscription else {
            clearLoadedOptions()
            return false
          }

          if let existing {
            let fullSubscribe = try await apiService.fetchSubscription(id: existing.id)
            guard canPublishLoadResult(from: sessionSnapshot), !shouldRollbackCreatedSubscription
            else {
              clearLoadedOptions()
              return false
            }
            self.subscribe = fullSubscribe
            self.original = fullSubscribe
            isNewSubscription = false
            isCreatedAndPaused = true
          } else {
            guard let profileKey = apiService.profileKey,
              let newId = try await apiService.addSubscription(
                request: subscribe.addRequest,
                subscribe: subscribe
              )
            else {
              canRetryLoad = true
              loadErrorMessage = "暂时无法创建订阅，请重试。"
              return false
            }
            guard canPublishLoadResult(from: sessionSnapshot) else {
              clearLoadedOptions()
              return false
            }

            self.subscribe.id = newId
            createdSubscriptionReceipt = CreatedSubscriptionReceipt(
              id: newId,
              profileKey: profileKey,
              session: sessionSnapshot
            )
            if shouldRollbackCreatedSubscription {
              await rollbackCreatedSubscriptionIfNeeded()
              clearLoadedOptions()
              return false
            }
            guard try await prepareCreatedSubscription(id: newId, from: sessionSnapshot) else {
              return false
            }
          }
        }
      } catch is CancellationError {
        clearLoadedOptions()
        return false
      } catch {
        Logger.error("Failed to prepare a new subscription: \(error)")
        canRetryLoad = subscribe.id == nil || currentCreatedSubscriptionReceipt() != nil
        loadErrorMessage = canRetryLoad
          ? "订阅准备失败，请重试。"
          : "订阅没有准备完成，请关闭后重新打开。"
        return false
      }
    }

    // 2. 加载配置选项
    do {
      async let sitesTask = apiService.fetchSites()
      async let downloadersTask = apiService.fetchDownloadClients()
      async let directoriesTask = apiService.fetchDirectories()

      let (s, d, dir) = try await (sitesTask, downloadersTask, directoriesTask)
      let f = apiService.canRequestSuperUserEndpoints
        ? try await apiService.fetchFilterRuleGroups()
        : []
      guard canPublishLoadResult(from: sessionSnapshot) else {
        clearLoadedOptions()
        return false
      }
      self.sites = s.filter { $0.is_active?.value == true }
      self.downloaders = d
      self.directories = dir
      self.filterGroups = f

      if subscribe.type == "电视剧",
        let tmdbId = Self.tmdbEpisodeGroupID(from: subscribe)
      {
        let groups = try await apiService.fetchEpisodeGroups(tmdbId: tmdbId)
        guard canPublishLoadResult(from: sessionSnapshot) else {
          clearLoadedOptions()
          return false
        }
        self.episodeGroups = groups
      }
    } catch {
      Logger.error("Failed to load subscription options: \(error)")
      clearLoadedOptions()
      canRetryLoad = true
      loadErrorMessage = "订阅设置没有加载完整，请重试。"
      return false
    }
    return true
  }

  /// 加载失败且不能重试（已创建的订阅不再属于当前登录），只能关掉重新打开。
  var mustClose: Bool {
    loadErrorMessage != nil && !canRetryLoad
  }

  /// 出错后按「订阅」「订阅设置」时先重新加载。只有真正加载完成、并且没有从新增变成编辑
  /// （重新查询发现这部片已经订阅过）时才返回 true，调用方才接着做原来的操作。
  func reloadBeforeContinuing() async -> Bool {
    let wasNew = isNewSubscription
    guard await loadData() else { return false }
    return isNewSubscription == wasNew
  }

  private func canPublishLoadResult(from snapshot: APIServiceSessionSnapshot) -> Bool {
    apiService.isSessionUnchanged(from: snapshot) && apiService.canAccess(.subscribe)
  }

  /// v3 订阅主身份是 `media_source` + `media_id`；剧集组接口仍要 TMDB 数字 ID。
  /// 从 identity 取正整数，兼容旧响应里只有 `tmdbid` 的记录。
  static func tmdbEpisodeGroupID(from subscribe: Subscribe) -> Int? {
    guard subscribe.identity?.source == "themoviedb",
      let mediaId = subscribe.identity?.mediaId
    else {
      return nil
    }
    return MediaIdentifier.validNumericIdentifier(Int(mediaId))
  }

  private func currentCreatedSubscriptionReceipt() -> CreatedSubscriptionReceipt? {
    guard let receipt = createdSubscriptionReceipt,
      subscribe.id == receipt.id,
      apiService.profileKey == receipt.profileKey,
      apiService.isSessionUnchanged(from: receipt.session)
    else {
      return nil
    }
    return receipt
  }

  private func prepareCreatedSubscription(
    id: Int,
    from snapshot: APIServiceSessionSnapshot
  ) async throws -> Bool {
    let pauseResult = try await apiService.updateSubscriptionStatus(id: id, state: "S")
    guard pauseResult.success else {
      canRetryLoad = true
      loadErrorMessage =
        MediaIdentifier.normalizedString(pauseResult.message)
        ?? "订阅没有准备完成，请重试。"
      return false
    }
    guard canPublishLoadResult(from: snapshot) else {
      clearLoadedOptions()
      return false
    }
    if shouldRollbackCreatedSubscription {
      await rollbackCreatedSubscriptionIfNeeded()
      clearLoadedOptions()
      return false
    }

    let fullSubscribe = try await apiService.fetchSubscription(id: id)
    guard canPublishLoadResult(from: snapshot) else {
      clearLoadedOptions()
      return false
    }
    if shouldRollbackCreatedSubscription {
      await rollbackCreatedSubscriptionIfNeeded()
      clearLoadedOptions()
      return false
    }
    self.subscribe = fullSubscribe
    self.original = fullSubscribe
    isCreatedAndPaused = true
    return true
  }

  private func clearLoadedOptions() {
    sites = []
    downloaders = []
    directories = []
    filterGroups = []
    episodeGroups = []
  }

  /// 最近一次 `save()` 是否真的写入了订阅（发了保存请求）。
  /// 已保存后只补做启用、搜索时为 false，调用方据此决定是否再回写缓存。
  @Published private(set) var didWriteInLastSave = false
  /// 本次新建的订阅已经启用过；保存后重试时不再重复启用。
  private var hasResumedCreatedSubscription = false

  /// 保存订阅，然后启用（仅本次新建的）并搜索。
  ///
  /// 已经保存成功、只是后面的启用或搜索失败时，再调用不会重新保存：设置没改过就只补做没完成的步骤；
  /// 保存后又改了设置，才只写这次的改动。
  func save() async -> Bool {
    guard !isSaving else { return false }
    guard (subscribe.id ?? 0) > 0 else {
      errorMessage = "订阅信息不完整，无法保存。"
      return false
    }
    isSaving = true
    defer { isSaving = false }
    errorMessage = nil
    didWriteInLastSave = false

    do {
      guard apiService.canAccess(.subscribe), let ownerProfileKey = apiService.profileKey else {
        return false
      }
      let snapshot = apiService.sessionSnapshot()
      if !isSaved || subscribe != original {
        let savedDraft = subscribe
        let result = try await apiService.saveSubscription(original: original, draft: savedDraft)
        guard apiService.isSessionUnchanged(from: snapshot) else { throw CancellationError() }
        guard result.success else {
          errorMessage =
            MediaIdentifier.normalizedString(result.message)
            ?? "暂时无法保存订阅，请稍后重试。"
          return false
        }

        original = savedDraft
        isSaved = true
        didWriteInLastSave = true
        publishDeferredSaveSuccessIfNeeded()
      }
      // 保存完成后只在同一账号内继续启用、搜索和刷新订阅状态。
      defer {
        if apiService.profileKey == ownerProfileKey {
          NotificationCenter.default.post(name: .subscriptionDidUpdate, object: nil)
        }
      }

      guard let id = subscribe.id else { return true }

      let ownsCreatedSubscription = currentCreatedSubscriptionReceipt() != nil
      if ownsCreatedSubscription && !hasResumedCreatedSubscription {
        do {
          guard apiService.isSessionUnchanged(from: snapshot) else { return true }
          let result = try await apiService.updateSubscriptionStatus(
            id: id,
            state: "R"
          )
          guard apiService.isSessionUnchanged(from: snapshot) else { return true }
          guard result.success else {
            errorMessage =
              MediaIdentifier.normalizedString(result.message)
              ?? "订阅已保存，但暂时未能启用。你可以稍后在订阅页面重试。"
            return true
          }
          hasResumedCreatedSubscription = true
        } catch is CancellationError {
          return true
        } catch {
          Logger.error("Failed to resume saved subscription \(id): \(error)")
          errorMessage = "订阅已保存，但暂时未能启用。你可以稍后在订阅页面重试。"
          return true
        }
      }

      guard !ownsCreatedSubscription || SystemViewModel.shouldAutoSearchNewSubscriptions else {
        return true
      }

      do {
        guard apiService.isSessionUnchanged(from: snapshot) else { return true }
        guard try await apiService.searchSubscription(id: id) else {
          errorMessage = "订阅已保存，但没有开始搜索。你可以稍后手动搜索。"
          return true
        }
        guard apiService.isSessionUnchanged(from: snapshot) else { return true }
      } catch is CancellationError {
        return true
      } catch {
        Logger.error("Failed to search saved subscription \(id): \(error)")
        errorMessage = "订阅已保存，但没有开始搜索。你可以稍后手动搜索。"
      }
      return true
    } catch is CancellationError {
      return false
    } catch {
      Logger.error("Failed to save subscription: \(error)")
      errorMessage = "暂时无法保存订阅，请稍后重试。"
      return false
    }
  }

  func cancel(wasSavingOnDismiss: Bool = false) async {
    if wasSavingOnDismiss || isSaving {
      shouldNotifySaveSuccessAfterDismiss = true
      if isSaved {
        publishDeferredSaveSuccessIfNeeded()
      }
      return
    }
    guard !isSaved else { return }
    shouldRollbackCreatedSubscription = true
    await rollbackCreatedSubscriptionIfNeeded()
  }

  private func rollbackCreatedSubscriptionIfNeeded() async {
    guard !isRollingBackCreatedSubscription,
      !isSaved,
      let receipt = currentCreatedSubscriptionReceipt(),
      apiService.canAccess(.subscribe)
    else {
      return
    }
    isRollingBackCreatedSubscription = true
    defer { isRollingBackCreatedSubscription = false }

    do {
      guard try await apiService.deleteSubscription(id: receipt.id),
        currentCreatedSubscriptionReceipt()?.id == receipt.id
      else {
        return
      }
      createdSubscriptionReceipt = nil
      NotificationCenter.default.post(name: .subscriptionDidUpdate, object: nil)
    } catch is CancellationError {
      return
    } catch {
      Logger.error("Failed to roll back subscription \(receipt.id): \(error)")
    }
  }

  private func publishDeferredSaveSuccessIfNeeded() {
    guard shouldNotifySaveSuccessAfterDismiss else { return }
    shouldNotifySaveSuccessAfterDismiss = false
    NotificationCenter.default.post(name: .subscriptionSaveDidComplete, object: nil)
  }
}
