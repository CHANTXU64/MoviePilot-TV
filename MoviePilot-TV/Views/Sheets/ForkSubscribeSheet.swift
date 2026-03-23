import Kingfisher
import SwiftUI
import Combine
import Foundation

struct ForkSubscribeSheet: View {
  let share: SubscribeShare
  var onFork: (Int) -> Void

  @Environment(\.dismiss) private var dismiss
  @ObservedObject var subscriptionHandler: SubscriptionHandler
  @State private var isImageFailed = false

  var body: some View {
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

        if !isImageFailed, let posterUrl = share.toMediaInfo().imageURLs.poster {
          KFImage(posterUrl)
            .requestModifier(AnyModifier.cookieModifier)
            .onFailure { _ in
              isImageFailed = true
            }
            .placeholder {
              Rectangle()
                .fill(Color(white: 0.12))
                .overlay(ProgressView().tint(.gray))
            }
            .resizing(referenceSize: CGSize(width: 360, height: 540), mode: .aspectFill)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: 360)
            .clipped()
        }
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
          Button(action: {
            // Fork a subscription
            Task {
              let newSubId = await subscriptionHandler.fork(share: share)
              if let newSubId = newSubId {
                onFork(newSubId)
                dismiss()
              }
            }
          }) {
            Text("复用订阅")
          }
          Spacer()
        }
      }
      .frame(width: 900, alignment: .leading)
    }
    .padding(50)
  }
}
