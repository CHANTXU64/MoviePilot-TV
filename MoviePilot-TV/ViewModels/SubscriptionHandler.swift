import Combine
import SwiftUI

@MainActor
class SubscriptionHandler: ObservableObject {
  @Published var sheetSubscribe: Subscribe?
  @Published var tvSubscribeRequest: SubscribeSeasonRequest?
  @Published var forkSheetRequest: SubscribeShare?

  @Published var notificationMessage = ""
  @Published var notificationType: NotificationType = .info
  @Published var notificationSerial = 0
  @Published private(set) var forkErrorMessage: String?

  private let apiService = APIService.shared

  func handleSubscribe(_ item: MediaInfo) {
    guard apiService.canAccess(.subscribe) else { return }

    if item.canDirectlySubscribe {
      Task {
        do {
          var isSubscribed = try await apiService.checkSubscription(media: item)
          // 豆瓣/Bangumi 来源：后端可能用 TMDB ID 存储订阅，用预加载识别的 tmdbId 补查
          if !isSubscribed, item.tmdb_id == nil,
            let tmdbId = MediaPreloader.shared.peekTask(for: item)?.tmdbId
          {
            let tmdbMedia = MediaInfo(tmdb_id: tmdbId, type: item.type)
            isSubscribed = try await apiService.checkSubscription(media: tmdbMedia)
          }
          if isSubscribed {
            self.showNotification(message: "已订阅，请勿重复操作", type: .warning)
          } else {
            // For movies or direct-subscribable TV, show edit sheet
            self.sheetSubscribe = mediaInfoToSubscribeRequest(item)
          }
        } catch {
          Logger.error("Failed to check subscription before opening editor: \(error)")
          self.showNotification(message: "暂时无法确认订阅状态，请稍后重试。", type: .error)
        }
      }
    } else {
      // 多季电视剧：导航到 SubscribeSeasonView
      self.tvSubscribeRequest = SubscribeSeasonRequest(
        mediaInfo: item,
        initialSeason: nil,
        initialEpisodeGroup: nil
      )
    }
  }

  func fork(share: SubscribeShare) async -> Int? {
    forkErrorMessage = nil
    guard apiService.canAccess(.subscribe) else { return nil }

    do {
      return try await apiService.forkSubscription(share: share)
    } catch {
      Logger.error("Failed to fork subscription: \(error)")
      forkErrorMessage = "暂时无法复用订阅，请稍后重试。"
      return nil
    }
  }

  func fetchSubscriptionAndShowEditor(subId: Int) async {
    guard apiService.canAccess(.subscribe) else { return }

    do {
      let subscription = try await apiService.fetchSubscription(id: subId)
      self.sheetSubscribe = subscription
    } catch {
      showNotification(message: "加载订阅失败: \(error.localizedDescription)", type: .error)
    }
  }

  /// 转换为订阅请求对象
  /// 根据当前的媒体基础信息，预填一份后端所需的订阅请求结构体
  private func mediaInfoToSubscribeRequest(_ item: MediaInfo) -> Subscribe {
    return Subscribe(
      id: nil,
      name: item.title ?? "",
      year: item.year,
      type: item.type ?? "电影",
      season: item.season,
      poster: item.poster_path,
      state: "N",  // 默认状态为 'N' (New)
      last_update: nil,
      tmdbid: item.tmdb_id,
      doubanid: item.douban_id,
      bangumiid: item.bangumi_id,
      mediaid: MediaIdentifier.apiMediaId(
        tmdbId: nil,
        doubanId: nil,
        bangumiId: nil,
        mediaIdPrefix: item.mediaid_prefix,
        mediaId: item.media_id
      )
    )
  }

  /// 通用消息提示
  func showNotification(message: String, type: NotificationType) {
    notificationMessage = message
    notificationType = type
    notificationSerial += 1
  }
}
