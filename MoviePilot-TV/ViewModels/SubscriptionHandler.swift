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
  @Published private(set) var unsubscribeConfirmationMessage: String?

  private let apiService: APIService
  private let mediaPreloader: MediaPreloader
  private var isCheckingSubscription = false
  /// 最近一次 Fork 的成功收据：POST 已创建订阅、但编辑器（GET）尚未完成。GET 成功后才清除。
  private var pendingForkReceipt: PendingForkReceipt?
  /// 最近一次 fork(share:) 调用的 operation 代际，用于丢弃旧操作的迟到错误与呈现。
  private var activeForkOperation: UUID?
  private var pendingUnsubscribe: (
    item: MediaInfo, mediaId: String, snapshot: APIServiceSessionSnapshot
  )?

  init(
    apiService: APIService = .shared,
    mediaPreloader: MediaPreloader = .shared
  ) {
    self.apiService = apiService
    self.mediaPreloader = mediaPreloader
  }

  func handleSubscribe(_ item: MediaInfo, expectedSubscribed: Bool) {
    guard apiService.canAccess(.subscribe) else { return }
    guard !item.isCollection, item.type != "音乐" else { return }

    if item.canDirectlySubscribe {
      guard !isCheckingSubscription, !isUnsubscribing else { return }
      isCheckingSubscription = true
      Task {
        defer { isCheckingSubscription = false }
        do {
          let snapshot = apiService.sessionSnapshot()
          let latestSubscribed = try await subscriptionExists(for: item, snapshot: snapshot)
          guard apiService.isSessionUnchanged(from: snapshot) else { return }

          // 菜单显示意图与最新状态不一致时只刷新，不把“订阅”反转成取消操作。
          guard latestSubscribed == expectedSubscribed else {
            mediaPreloader.peekTask(for: item)?.isSubscribed = latestSubscribed
            showNotification(message: "订阅状态已变化，请重新操作。", type: .info)
            return
          }

          if latestSubscribed {
            guard
              let subscription = try await deletionTargetLookup(for: item, snapshot: snapshot)
            else {
              guard apiService.isSessionUnchanged(from: snapshot) else { return }
              // 元数据状态查询能跨来源确认“已订阅”，但 DELETE 仍要求精确来源身份。
              // 严格定位失败只代表无法安全删除，不能据此把已订阅状态改成 false。
              mediaPreloader.peekTask(for: item)?.isSubscribed = true
              showUnsubscribeFailure(
                for: item,
                message: "无法定位可安全取消的订阅，请刷新后重试。"
              )
              return
            }
            guard apiService.isSessionUnchanged(from: snapshot) else { return }
            pendingUnsubscribe = (item, subscription.mediaId, snapshot)
            unsubscribeConfirmationMessage = SubscriptionCancelConfirmation.headerMessage(
              for: item
            )
          } else {
            guard apiService.isSessionUnchanged(from: snapshot) else { return }
            // For directly subscribable non-TV media, show edit sheet
            self.sheetIsNewSubscription = true
            self.sheetSubscribe = mediaInfoToSubscribeRequest(item)
          }
        } catch is CancellationError {
          return
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

  func confirmUnsubscribe() {
    guard let pendingUnsubscribe else { return }
    dismissUnsubscribeConfirmation()
    Task {
      await unsubscribe(
        pendingUnsubscribe.item,
        mediaId: pendingUnsubscribe.mediaId,
        snapshot: pendingUnsubscribe.snapshot
      )
    }
  }

  func dismissUnsubscribeConfirmation() {
    pendingUnsubscribe = nil
    unsubscribeConfirmationMessage = nil
  }

  private func unsubscribe(
    _ item: MediaInfo,
    mediaId: String,
    snapshot: APIServiceSessionSnapshot
  ) async {
    guard !isUnsubscribing else { return }
    isUnsubscribing = true
    defer { isUnsubscribing = false }

    do {
      guard apiService.isSessionUnchanged(from: snapshot) else { return }
      let result = try await apiService.deleteSubscriptionResult(
        mediaId: mediaId,
        season: item.season
      )
      guard apiService.isSessionUnchanged(from: snapshot) else { return }
      guard result.success else {
        showUnsubscribeFailure(for: item, message: result.message)
        return
      }
      (mediaPreloader.peekTask(for: item) ?? mediaPreloader.findTask(byMediaId: mediaId))?
        .isSubscribed = false
      NotificationCenter.default.post(name: .subscriptionDidUpdate, object: nil)
    } catch is CancellationError {
      return
    } catch {
      Logger.error("Failed to remove subscription: \(error)")
      showUnsubscribeFailure(for: item, message: error.localizedDescription)
    }
  }

  func fork(share: SubscribeShare) async -> Int? {
    guard apiService.canAccess(.subscribe) else { return nil }
    guard let profileKey = apiService.profileKey else { return nil }

    // POST 已成功但编辑器尚未完成（GET 失败或未执行）时，同一分享再次点击只重试 GET，
    // 不重复创建订阅；仅当收据与当前会话、当前分享匹配时复用。
    if let receipt = pendingForkReceipt,
      receipt.profileKey == profileKey,
      receipt.shareID == share.id
    {
      return receipt.subscriptionId
    }

    let operationID = UUID()
    activeForkOperation = operationID
    forkErrorMessage = nil
    let snapshot = apiService.sessionSnapshot()
    defer {
      if activeForkOperation == operationID {
        activeForkOperation = nil
      }
    }

    do {
      let subscriptionId = try await apiService.forkSubscription(share: share)
      guard apiService.isSessionUnchanged(from: snapshot),
        apiService.profileKey == profileKey,
        activeForkOperation == operationID
      else { return nil }
      pendingForkReceipt = PendingForkReceipt(
        operationID: operationID,
        subscriptionId: subscriptionId,
        profileKey: profileKey,
        shareID: share.id
      )
      NotificationCenter.default.post(name: .subscriptionDidUpdate, object: nil)
      return subscriptionId
    } catch is CancellationError {
      return nil
    } catch {
      guard activeForkOperation == operationID else { return nil }
      Logger.error("Failed to fork subscription: \(error)")
      let title = share.share_title ?? share.name ?? "该订阅"
      forkErrorMessage = "暂时无法复用订阅《\(title)》，请稍后重试。"
      return nil
    }
  }

  func fetchSubscriptionAndShowEditor(subId: Int) async {
    guard apiService.canAccess(.subscribe) else { return }

    do {
      // 本请求是否属于一次已产生收据的 Fork 操作；无收据的调用保持既有直接打开语义。
      let receiptForThisRequest = pendingForkReceipt.flatMap {
        $0.subscriptionId == subId ? $0 : nil
      }
      if let receiptForThisRequest {
        guard receiptForThisRequest.profileKey == apiService.profileKey,
          activeForkOperation == nil
        else {
          throw CancellationError()
        }
      }
      let subscription = try await apiService.fetchSubscription(id: subId)
      // GET 完成后，有收据的请求必须是仍未退休的当前操作，否则视为迟到的旧请求丢弃结果。
      if let receiptForThisRequest {
        guard let currentReceipt = pendingForkReceipt,
          currentReceipt.operationID == receiptForThisRequest.operationID,
          currentReceipt.profileKey == apiService.profileKey,
          activeForkOperation == nil
        else {
          throw CancellationError()
        }
        // 编辑器成功打开后操作完成；再次点击同一分享是新的合法 Fork。
        pendingForkReceipt = nil
      }
      sheetIsNewSubscription = false
      self.sheetSubscribe = subscription
    } catch is CancellationError {
      // 迟到、退休或取消的请求直接终止，不影响当前收据。
      return
    } catch {
      // GET 失败保留收据：同一分享再次点击时只重试 GET，不重复 POST。
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

  /// 回答当前媒体是否存在订阅。v3.0.4 的状态查询允许按标题、年份、类型跨来源匹配。
  private func subscriptionExists(
    for item: MediaInfo,
    snapshot: APIServiceSessionSnapshot
  ) async throws -> Bool {
    let statusMedia = subscriptionStatusMedia(for: item)
    if try await apiService.fetchSubscriptionLookup(
      media: statusMedia,
      season: item.season
    ) != nil {
      return true
    }
    guard apiService.isSessionUnchanged(from: snapshot) else { throw CancellationError() }
    guard item.tmdb_id == nil,
      let tmdbId = mediaPreloader.peekTask(for: item)?.tmdbId
    else {
      return false
    }
    return try await apiService.fetchSubscriptionLookup(
      media: MediaInfo(
        tmdb_id: tmdbId,
        source: "themoviedb",
        media_id: String(tmdbId),
        title: statusMedia.title,
        type: statusMedia.type,
        year: statusMedia.year,
        season: item.season
      ),
      season: item.season
    ) != nil
  }

  /// 状态复查沿用原始来源身份和季号，只补入同一预加载任务已取得的详情查询元数据。
  /// 不能直接使用 fullDetail：详情补出的其他来源 ID 可能改变业务身份和缓存键。
  private func subscriptionStatusMedia(for item: MediaInfo) -> MediaInfo {
    guard let detail = mediaPreloader.peekTask(for: item)?.fullDetail else { return item }
    return MediaInfo(
      tmdb_id: item.tmdb_id,
      douban_id: item.douban_id,
      bangumi_id: item.bangumi_id,
      anilist_id: item.anilist_id,
      imdb_id: item.imdb_id,
      tvdb_id: item.tvdb_id,
      source: item.source,
      mediaid_prefix: item.mediaid_prefix,
      media_id: item.media_id,
      title: detail.title ?? item.title,
      type: detail.type ?? item.type,
      year: detail.year ?? item.year,
      season: item.season
    )
  }

  /// 只回答能否取得可安全执行 DELETE 的精确来源目标，不承担订阅状态判断。
  private func deletionTargetLookup(
    for item: MediaInfo,
    snapshot: APIServiceSessionSnapshot
  ) async throws
    -> SubscriptionLookupResult?
  {
    if let subscription = try await apiService.fetchSubscriptionLookup(
      media: item,
      season: item.season,
      includeVideoMetadataFallback: false
    ) {
      return subscription
    }
    guard apiService.isSessionUnchanged(from: snapshot) else { throw CancellationError() }
    guard item.tmdb_id == nil,
      let tmdbId = mediaPreloader.peekTask(for: item)?.tmdbId
    else {
      return nil
    }
    return try await apiService.fetchSubscriptionLookup(
      media: MediaInfo(
        tmdb_id: tmdbId,
        source: "themoviedb",
        media_id: String(tmdbId),
        title: item.title,
        type: item.type,
        season: item.season
      ),
      season: item.season,
      includeVideoMetadataFallback: false
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

/// Fork 的 POST 成功收据：一次操作创建订阅后，在编辑器（GET）成功打开前持续有效。
private struct PendingForkReceipt {
  let operationID: UUID
  let subscriptionId: Int
  let profileKey: String
  /// 来源分享的稳定标识；同一分享再次点击时用于判定“只重试 GET，不重复 POST”。
  let shareID: String?
}
