import Kingfisher
import SwiftUI
import Combine
import Foundation

struct ForkSubscribeSheet: View {
  let share: SubscribeShare
  var onFork: (Int) -> Void

  @Environment(\.dismiss) private var dismiss
  @ObservedObject private var apiService = APIService.shared
  @ObservedObject var subscriptionHandler: SubscriptionHandler
  @State private var isImageFailed = false
  @State private var isUsingFallback = false
  @State private var isForking = false

  var body: some View {
    let media = share.toMediaInfo()
    HStack(alignment: .top, spacing: 60) {
      // Poster
      ZStack {
        Rectangle()
          .fill(Color(white: 0.12))
          .overlay(
            Image(systemName: "film")
              .font(.title2)
              .foregroundColor(.gray)
          )

        PageManagedImage(
          url: isUsingFallback ? media.imageURLs.posterFallback : media.imageURLs.poster,
          processor: ResizingImageProcessor(
            referenceSize: CGSize(width: 360, height: 540),
            mode: .aspectFill
          ),
          isEnabled: !isImageFailed,
          role: .activePage,
          participatesInPageLifecycle: true,
          skipsMemoryCache: true,
          fadeDuration: 0,
          onFailure: {
            // 降尺寸海报加载失败时回退到原始 URL 重试一次，仍失败才隐藏。
            if !isUsingFallback, media.imageURLs.posterFallback != nil {
              isUsingFallback = true
            } else {
              isImageFailed = true
            }
          }
        )
        .frame(width: 360)
        .clipped()
      }
      .frame(width: 360)
      .cornerRadius(20)

      // Info
      VStack(alignment: .leading, spacing: 30) {
        VStack(alignment: .leading, spacing: 10) {
          Text(share.share_title ?? "复用订阅")
            .font(.title3)

          if let description = share.description, !description.isEmpty {
            Text(description)
              .font(.body)
              .foregroundColor(.secondary)
              .lineLimit(4)
          }
        }

        if let comment = share.share_comment, !comment.isEmpty {
          Text(
            comment.replacingOccurrences(of: #"\n{2,}"#, with: "\n", options: .regularExpression)
          )
          .font(.body)
            .foregroundColor(.secondary)
        }

        HStack(spacing: 30) {
          Text("分享人：\(share.share_user ?? "未知")")

          if let date = share.date, !date.isEmpty {
            Text("时间： \(date.toRelativeDateString())")
          }

          if let count = share.count {
            Text("共 \(count) 次复用")
          }
        }
        .font(.body)
        .foregroundColor(.secondary)

        Spacer()

        HStack {
          Spacer()
          SheetActionButton(
            title: "复用订阅",
            loadingTitle: "复用中",
            isLoading: isForking,
            feedbackMessage: subscriptionHandler.forkErrorMessage
          ) {
            Task {
              guard !isForking else { return }
              isForking = true
              defer { isForking = false }
              let newSubId = await subscriptionHandler.fork(share: share)
              if let newSubId = newSubId {
                onFork(newSubId)
                dismiss()
              }
            }
          }
          .frame(width: 520)
          Spacer()
        }
      }
      .frame(width: 900, alignment: .leading)
    }
    .padding(50)
  }
}
