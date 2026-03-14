import Combine
import SwiftUI

@MainActor
class SubscriptionHandler: ObservableObject {
  @Published var sheetSubscribe: Subscribe?
  @Published var tvSubscribeRequest: SubscribeSeasonRequest?
  @Published var forkSheetRequest: SubscribeShare?

  // Alert properties
  @Published var showAlert = false
  @Published var alertTitle = ""
  @Published var alertMessage = ""

  private let apiService = APIService.shared

  func handleSubscribe(_ item: MediaInfo) {
    if item.canDirectlySubscribe {
      Task {
        let isSubscribed = try? await apiService.checkSubscription(media: item)
        if isSubscribed == true {
          self.showAlert(title: item.title ?? "", message: "已订阅，请勿重复操作")
        } else {
          // For movies or direct-subscribable TV, show edit sheet
          self.sheetSubscribe = mediaInfoToSubscribeRequest(item)
        }
      }
    } else {
      // 多季电视剧：导航到 SubscribeSeasonView
      self.tvSubscribeRequest = SubscribeSeasonRequest(mediaInfo: item, initialSeason: nil)
    }
  }

  func fork(share: SubscribeShare) async -> Int? {
    do {
      let newSubId = try await apiService.forkSubscription(share: share)
      showAlert(title: share.share_title ?? "", message: "复用订阅成功！")
      return newSubId
    } catch {
      showAlert(title: "复用失败", message: error.localizedDescription)
      return nil
    }
  }

  func fetchSubscriptionAndShowEditor(subId: Int) async {
    do {
      let subscription = try await apiService.fetchSubscription(id: subId)
      self.sheetSubscribe = subscription
    } catch {
      showAlert(title: "加载订阅失败", message: error.localizedDescription)
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
      bangumiid: item.bangumi_id
    )
  }

  /// 通用消息提示
  func showAlert(title: String, message: String) {
    self.alertTitle = title
    self.alertMessage = message
    self.showAlert = true
  }
}
