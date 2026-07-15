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

  private let apiService = APIService.shared

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

  init(subscribe: Subscribe, isNewSubscription: Bool = false) {
    self.subscribe = subscribe
    self.isNewSubscription = isNewSubscription
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
        let req = SubscribeRequest(
          name: subscribe.name,
          type: subscribe.type,
          year: subscribe.year,
          tmdbid: subscribe.tmdbid,
          doubanid: subscribe.doubanid,
          bangumiid: subscribe.bangumiid,
          mediaid: subscribe.mediaid,
          season: subscribe.season,
          best_version: subscribe.best_version,
          best_version_full: subscribe.best_version_full,
          episode_group: subscribe.episode_group
        )

        guard let newId = try await apiService.addSubscription(request: req, subscribe: subscribe)
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
        self.subscribe.id = newId

        // 立即暂停
        _ = try await apiService.updateSubscriptionStatus(id: newId, state: "S")
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
      self.sites = s
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
    isSaving = true
    defer { isSaving = false }
    errorMessage = nil

    do {
      let success = try await apiService.saveSubscription(subscribe)
      guard success else {
        errorMessage = "暂时无法保存订阅，请稍后重试。"
        return false
      }

      isSaved = true
      NotificationCenter.default.post(name: .subscriptionDidUpdate, object: nil)
    } catch {
      Logger.error("Failed to save subscription: \(error)")
      errorMessage = "暂时无法保存订阅，请稍后重试。"
      return false
    }

    guard let id = subscribe.id else { return true }

    if isNewSubscription {
      do {
        guard try await apiService.updateSubscriptionStatus(id: id, state: "R") else {
          Logger.error("Resuming saved subscription \(id) returned false")
          errorMessage = "订阅已保存，但暂时未能启用。你可以稍后在订阅页面重试。"
          return true
        }
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
      guard try await apiService.searchSubscription(id: id) else {
        Logger.error("Searching saved subscription \(id) returned false")
        errorMessage = "订阅已保存，但没有开始搜索。你可以稍后手动搜索。"
        return true
      }
    } catch {
      Logger.error("Failed to search saved subscription \(id): \(error)")
      errorMessage = "订阅已保存，但没有开始搜索。你可以稍后手动搜索。"
    }
    return true
  }

  func cancel() async {
    guard !isSaved else { return }
    // 如果我们创建了一个新订阅但用户取消了，我们必须回滚（删除）它
    if isNewSubscription, let id = subscribe.id {
      do {
        _ = try await apiService.deleteSubscription(id: id)
      } catch {
        Logger.error("Failed to roll back subscription \(id): \(error)")
      }
    }
  }
}
