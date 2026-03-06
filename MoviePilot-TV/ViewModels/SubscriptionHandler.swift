import Combine
import SwiftUI

@MainActor
class SubscriptionHandler: ObservableObject {
  @Published var sheetSubscribe: Subscribe?
  @Published var tvSubscribeRequest: SubscribeSeasonRequest?
  @Published var showSubscribedAlert = false
  func handleSubscribe(_ item: MediaInfo) {
    if item.canDirectlySubscribe {
      Task {
        let isSubscribed = try? await APIService.shared.checkSubscription(media: item)
        if isSubscribed == true {
          self.showSubscribedAlert = true
        } else {
          self.sheetSubscribe = mediaInfoToSubscribeRequest(item)
        }
      }
    } else {
      // 电视剧：导航到 SubscribeSeasonView
      self.tvSubscribeRequest = SubscribeSeasonRequest(mediaInfo: item, initialSeason: nil)
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
      state: "N", // 默认状态为 'N' (New)
      tmdbid: item.tmdb_id,
      doubanid: item.douban_id,
      bangumiid: item.bangumi_id
    )
  }
}
