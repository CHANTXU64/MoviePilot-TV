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
          season: subscribe.season,
          best_version: subscribe.best_version ?? 0,
          episode_group: subscribe.episode_group
        )

        guard let newId = try await apiService.addSubscription(request: req) else {
          print("Failed to create subscription")
          return  // TODO: 处理错误状态（例如，关闭页面或显示警报）
        }

        // 更新本地 ID
        self.subscribe.id = newId

        // 立即暂停
        _ = try await apiService.updateSubscriptionStatus(id: newId, state: "S")

        // 获取完整的订阅详情（以获得服务器端的默认值）
        let fullSubscribe = try await apiService.fetchSubscription(id: newId)
        self.subscribe = fullSubscribe

        isCreatedAndPaused = true
      } catch {
        print("Error during new subscription initialization: \(error)")
        return
      }
    }

    // 2. 加载配置选项
    do {
      async let sitesTask = apiService.fetchSites()
      async let downloadersTask = apiService.fetchDownloadClients()
      async let directoriesTask = apiService.fetchDirectories()
      async let filtersTask = apiService.fetchFilterRuleGroups()

      let (s, d, dir, f) = try await (sitesTask, downloadersTask, directoriesTask, filtersTask)
      self.sites = s
      self.downloaders = d
      self.directories = dir
      self.filterGroups = f

      if subscribe.type == "电视剧", let tmdbId = subscribe.tmdbid {
        self.episodeGroups = try await apiService.fetchEpisodeGroups(tmdbId: tmdbId)
      }
    } catch {
      print("Failed to load subscribe options: \(error)")
    }
  }

  func save() async -> Bool {
    isSaving = true
    defer { isSaving = false }
    do {
      // 保存更改
      let success = try await apiService.saveSubscription(subscribe)

      if success {
        if let id = subscribe.id {
          // 如果是新订阅，在搜索前恢复（取消暂停）该订阅
          if isNewSubscription {
            _ = try await apiService.updateSubscriptionStatus(id: id, state: "R")
          }
          // 立即触发对该订阅的搜索
          _ = try await apiService.searchSubscription(id: id)
        }
        self.isSaved = true
      }
      return success
    } catch {
      print("Save error: \(error)")
      return false
    }
  }

  func cancel() async {
    // 如果我们创建了一个新订阅但用户取消了，我们必须回滚（删除）它
    if isNewSubscription, let id = subscribe.id {
      do {
        _ = try await apiService.deleteSubscription(id: id)
        print("Rolled back new subscription \(id)")
      } catch {
        print("Failed to rollback subscription \(id): \(error)")
      }
    }
  }
}
