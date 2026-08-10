import Combine
import Foundation

@MainActor
class SubscribeSheetViewModel: ObservableObject {
  @Published var subscribe: Subscribe
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

  // 标记我们是否正在创建一个新的订阅
  let isNewSubscription: Bool
  // 标记初始的“创建并暂停”操作序列是否成功
  private var isCreatedAndPaused = false
  // 绑定服务器返回的新订阅 ID 与创建它的账号，避免切号后回滚误删同号订阅。
  private var createdSubscriptionOwnerProfileKey: String?
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

  var savePathOptions: [String] {
    var seen = Set<String>()
    return directories.compactMap(\.download_path).filter {
      !$0.isEmpty && seen.insert($0).inserted
    }
  }

  init(
    subscribe: Subscribe,
    isNewSubscription: Bool = false,
    apiService: APIService = .shared
  ) {
    self.subscribe = subscribe
    self.isNewSubscription = isNewSubscription
    self.apiService = apiService
    if isNewSubscription, subscribe.id != nil, apiService.canAccess(.subscribe) {
      createdSubscriptionOwnerProfileKey = apiService.profileKey
    }
  }

  func loadData() async {
    guard apiService.canAccess(.subscribe) else {
      clearLoadedOptions()
      return
    }

    loadErrorMessage = nil
    canRetryLoad = false
    let sessionSnapshot = apiService.sessionSnapshot()
    isLoading = true
    defer { isLoading = false }

    // 1. 如果是新订阅，执行“创建 -> 暂停 -> 获取”序列
    if isNewSubscription && !isCreatedAndPaused {
      do {
        // 创建
        guard
          let newId = try await apiService.addSubscription(
            request: subscribe.addRequest,
            subscribe: subscribe
          )
        else {
          canRetryLoad = true
          loadErrorMessage = "暂时无法创建订阅，请重试。"
          return
        }
        guard canPublishLoadResult(from: sessionSnapshot) else {
          clearLoadedOptions()
          return
        }

        // 更新本地 ID
        createdSubscriptionOwnerProfileKey = apiService.profileKey
        self.subscribe.id = newId

        // 立即暂停
        let pauseResult = try await apiService.updateSubscriptionStatus(
          id: newId,
          state: "S"
        )
        guard pauseResult.success else {
          loadErrorMessage =
            MediaIdentifier.normalizedString(pauseResult.message)
            ?? "订阅没有准备完成，请关闭后重新打开。"
          return
        }
        guard canPublishLoadResult(from: sessionSnapshot) else {
          clearLoadedOptions()
          return
        }

        // 获取完整的订阅详情（以获得服务器端的默认值）
        let fullSubscribe = try await apiService.fetchSubscription(id: newId)
        guard canPublishLoadResult(from: sessionSnapshot) else {
          clearLoadedOptions()
          return
        }
        self.subscribe = fullSubscribe

        isCreatedAndPaused = true
      } catch is CancellationError {
        clearLoadedOptions()
        return
      } catch {
        Logger.error("Failed to prepare a new subscription: \(error)")
        canRetryLoad = subscribe.id == nil
        loadErrorMessage = canRetryLoad
          ? "订阅准备失败，请重试。"
          : "订阅没有准备完成，请关闭后重新打开。"
        return
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
        return
      }
      self.sites = s.filter { $0.is_active?.value == true }
      self.downloaders = d
      self.directories = dir
      self.filterGroups = f

      if subscribe.type == "电视剧", let tmdbId = subscribe.tmdbid {
        let groups = try await apiService.fetchEpisodeGroups(tmdbId: tmdbId)
        guard canPublishLoadResult(from: sessionSnapshot) else {
          clearLoadedOptions()
          return
        }
        self.episodeGroups = groups
      }
    } catch {
      Logger.error("Failed to load subscription options: \(error)")
      clearLoadedOptions()
      canRetryLoad = true
      loadErrorMessage = "订阅设置没有加载完整，请重试。"
    }
  }

  private func canPublishLoadResult(from snapshot: APIServiceSessionSnapshot) -> Bool {
    apiService.isSessionUnchanged(from: snapshot) && apiService.canAccess(.subscribe)
  }

  private func clearLoadedOptions() {
    sites = []
    downloaders = []
    directories = []
    filterGroups = []
    episodeGroups = []
  }

  func save() async -> Bool {
    guard (subscribe.id ?? 0) > 0 else {
      errorMessage = "订阅信息不完整，无法保存。"
      return false
    }
    isSaving = true
    defer { isSaving = false }
    errorMessage = nil

    do {
      guard apiService.canAccess(.subscribe), let ownerProfileKey = apiService.profileKey else {
        return false
      }
      let snapshot = apiService.sessionSnapshot()
      let result = try await apiService.saveSubscription(subscribe)
      guard apiService.isSessionUnchanged(from: snapshot) else { throw CancellationError() }
      guard result.success else {
        errorMessage =
          MediaIdentifier.normalizedString(result.message)
          ?? "暂时无法保存订阅，请稍后重试。"
        return false
      }

      isSaved = true
      publishDeferredSaveSuccessIfNeeded()
      // 保存完成后只在同一账号内继续启用、搜索和刷新订阅状态。
      defer {
        if apiService.profileKey == ownerProfileKey {
          NotificationCenter.default.post(name: .subscriptionDidUpdate, object: nil)
        }
      }

      guard let id = subscribe.id else { return true }

      if isNewSubscription {
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
        } catch is CancellationError {
          return true
        } catch {
          Logger.error("Failed to resume saved subscription \(id): \(error)")
          errorMessage = "订阅已保存，但暂时未能启用。你可以稍后在订阅页面重试。"
          return true
        }
      }

      guard !isNewSubscription || SystemViewModel.shouldAutoSearchNewSubscriptions else {
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
    // 如果我们创建了一个新订阅但用户取消了，我们必须回滚（删除）它
    if isNewSubscription, let id = subscribe.id,
      let ownerProfileKey = createdSubscriptionOwnerProfileKey,
      apiService.profileKey == ownerProfileKey,
      apiService.canAccess(.subscribe)
    {
      do {
        let snapshot = apiService.sessionSnapshot()
        if try await apiService.deleteSubscription(id: id),
          apiService.isSessionUnchanged(from: snapshot)
        {
          NotificationCenter.default.post(name: .subscriptionDidUpdate, object: nil)
        }
      } catch is CancellationError {
        return
      } catch {
        Logger.error("Failed to roll back subscription \(id): \(error)")
      }
    }
  }

  private func publishDeferredSaveSuccessIfNeeded() {
    guard shouldNotifySaveSuccessAfterDismiss else { return }
    shouldNotifySaveSuccessAfterDismiss = false
    NotificationCenter.default.post(name: .subscriptionSaveDidComplete, object: nil)
  }
}
