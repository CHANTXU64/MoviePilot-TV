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
    self.isNewSubscription = isNewSubscription && subscribe.id == nil
    self.apiService = apiService
  }

  func loadData() async {
    guard !isLoading else { return }
    guard apiService.canAccess(.subscribe) else {
      clearLoadedOptions()
      return
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
            return
          }
          guard try await prepareCreatedSubscription(id: receipt.id, from: sessionSnapshot) else {
            return
          }
        } else {
          let media = subscribe.navigationMediaInfo()
          guard media.apiMediaId != nil else {
            canRetryLoad = true
            loadErrorMessage = "暂时无法确认订阅状态，请重试。"
            return
          }

          // 该查询不读取状态缓存；查询与 POST 之间不再插入其他异步步骤。
          let existing = try await apiService.fetchSubscriptionLookup(
            media: media,
            season: subscribe.season
          )
          guard canPublishLoadResult(from: sessionSnapshot) else {
            clearLoadedOptions()
            return
          }
          guard !shouldRollbackCreatedSubscription else {
            clearLoadedOptions()
            return
          }

          if let existing {
            let fullSubscribe = try await apiService.fetchSubscription(id: existing.id)
            guard canPublishLoadResult(from: sessionSnapshot), !shouldRollbackCreatedSubscription
            else {
              clearLoadedOptions()
              return
            }
            self.subscribe = fullSubscribe
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
              return
            }
            guard canPublishLoadResult(from: sessionSnapshot) else {
              clearLoadedOptions()
              return
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
              return
            }
            guard try await prepareCreatedSubscription(id: newId, from: sessionSnapshot) else {
              return
            }
          }
        }
      } catch is CancellationError {
        clearLoadedOptions()
        return
      } catch {
        Logger.error("Failed to prepare a new subscription: \(error)")
        canRetryLoad = subscribe.id == nil || currentCreatedSubscriptionReceipt() != nil
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

      let ownsCreatedSubscription = currentCreatedSubscriptionReceipt() != nil
      if ownsCreatedSubscription {
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
