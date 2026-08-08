import Combine
import SwiftUI

@MainActor
class SubscriptionHandler: ObservableObject {
  @Published var sheetSubscribe: Subscribe?
  @Published var sheetIsNewSubscription = false
  @Published var tvSubscribeRequest: SubscribeSeasonRequest?
  @Published var forkSheetRequest: SubscribeShare?
  @Published private(set) var isUnsubscribing = false

  @Published var notificationMessage = ""
  @Published var notificationType: NotificationType = .info
  @Published var notificationSerial = 0
  @Published private(set) var forkErrorMessage: String?

  private let apiService = APIService.shared
  private var isCheckingSubscription = false

  func handleSubscribe(_ item: MediaInfo) {
    guard apiService.canAccess(.subscribe) else { return }

    if item.canDirectlySubscribe {
      guard !isCheckingSubscription, !isUnsubscribing else { return }
      isCheckingSubscription = true
      Task {
        defer { isCheckingSubscription = false }
        do {
          if let subscription = try await subscriptionLookup(for: item) {
            await unsubscribe(item, mediaId: subscription.mediaId)
          } else {
            // For movies or direct-subscribable TV, show edit sheet
            self.sheetIsNewSubscription = true
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

  private func unsubscribe(_ item: MediaInfo, mediaId: String) async {
    guard !isUnsubscribing else { return }
    isUnsubscribing = true
    defer { isUnsubscribing = false }

    do {
      let result = try await apiService.deleteSubscriptionResult(
        mediaId: mediaId,
        season: item.season
      )
      guard result.success else {
        showUnsubscribeFailure(for: item, message: result.message)
        return
      }
      MediaPreloader.shared.findTask(byMediaId: mediaId)?.isSubscribed = false
      NotificationCenter.default.post(name: .subscriptionDidUpdate, object: nil)
    } catch {
      Logger.error("Failed to remove subscription: \(error)")
      showUnsubscribeFailure(for: item, message: error.localizedDescription)
    }
  }

  func fork(share: SubscribeShare) async -> Int? {
    forkErrorMessage = nil
    guard apiService.canAccess(.subscribe) else { return nil }

    do {
      let subscriptionId = try await apiService.forkSubscription(share: share)
      NotificationCenter.default.post(name: .subscriptionDidUpdate, object: nil)
      return subscriptionId
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
      sheetIsNewSubscription = false
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
      anilistid: item.anilist_id,
      media_source: item.identity?.source,
      media_id: item.identity?.mediaId,
      mediaid: item.apiMediaId
    )
  }

  private func subscriptionLookup(for item: MediaInfo) async throws
    -> SubscriptionLookupResult?
  {
    if let subscription = try await apiService.fetchSubscriptionLookup(
      media: item,
      season: item.season
    ) {
      return subscription
    }
    guard item.tmdb_id == nil,
      let tmdbId = MediaPreloader.shared.peekTask(for: item)?.tmdbId
    else {
      return nil
    }
    return try await apiService.fetchSubscriptionLookup(
      media: MediaInfo(
        tmdb_id: tmdbId,
        title: item.title,
        type: item.type,
        season: item.season
      ),
      season: item.season
    )
  }

  private func showUnsubscribeFailure(for item: MediaInfo, message: String?) {
    let title = item.cleanedTitle ?? item.title ?? ""
    let reason = MediaIdentifier.normalizedString(message)
    showNotification(
      message: reason.map { "《\(title)》取消订阅失败：\($0)" } ?? "《\(title)》取消订阅失败。",
      type: .error
    )
  }

  /// 通用消息提示
  func showNotification(message: String, type: NotificationType) {
    notificationMessage = message
    notificationType = type
    notificationSerial += 1
  }
}
