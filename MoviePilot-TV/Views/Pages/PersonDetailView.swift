import Kingfisher
import SwiftUI

struct PersonDetailView: View {
  @StateObject private var viewModel: PersonDetailViewModel
  @Binding var navigationPath: NavigationPath

  init(person: Person, navigationPath: Binding<NavigationPath>) {
    _viewModel = StateObject(
      wrappedValue: PersonDetailViewModel(person: person))
    _navigationPath = navigationPath
  }

  @State private var showFullBio = false
  @State private var isImageFailed: Bool = false
  @StateObject private var subscriptionHandler = SubscriptionHandler()
  @EnvironmentObject private var mediaActionHandler: MediaActionHandler

  var body: some View {
    MediaGridView(
      items: viewModel.credits,
      isLoading: viewModel.isLoading,
      isLoadingMore: viewModel.isLoadingMore,
      onLoadMore: {_ in 
        Task { await viewModel.loadMoreData() }
      },
      navigationPath: $navigationPath,
      header: {
        VStack(alignment: .leading, spacing: 40) {
          let person = viewModel.person
          // 头部区域
          HStack(alignment: .top, spacing: 40) {
            // 个人照片 - 不可交互，无焦点效果
            let imageUrl = APIService.shared.getPersonImage(person)
            ZStack {
              // 背景 / 占位符
              Rectangle()
                .fill(Color(white: 0.12))
                .overlay(
                  Image(systemName: "person.fill")
                    .font(.system(size: 100))
                    .foregroundColor(.gray)
                )

              if !isImageFailed, let validUrl = imageUrl {
                KFImage(validUrl)
                  .requestModifier(AnyModifier.cookieModifier)
                  .onFailure { _ in
                    isImageFailed = true
                  }
                  .placeholder {
                    Rectangle()
                      .fill(Color(white: 0.12))
                      .overlay(ProgressView().tint(.gray))
                  }
                  .resizing(referenceSize: CGSize(width: 400, height: 600), mode: .aspectFill)
                  .resizable()
                  .aspectRatio(contentMode: .fill)
              }
            }
            .onChange(of: imageUrl) { _, _ in
              isImageFailed = false
            }
            .frame(width: 400, height: 600)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(radius: 10)

            VStack(alignment: .leading, spacing: 20) {
              Text(person.name ?? "未知")
                .font(.title.bold())

              if let originalName = person.original_name, originalName != person.name {
                Text(originalName)
                  .font(.headline)
                  .foregroundColor(.secondary)
                  .padding(.top, -10)
              }

              VStack(alignment: .leading, spacing: 10) {
                if let birthday = person.birthday {
                  InfoRow(label: "生日", value: birthday)
                }
                if let place = person.place_of_birth {
                  InfoRow(label: "出生地", value: place)
                }
              }

              if viewModel.isLoading {
                // 加载期间保持布局稳定的占位符
                RoundedRectangle(cornerRadius: 12)
                  .fill(Color.secondary.opacity(0.1))
                  .frame(height: 150)
                  .overlay(ProgressView())
              } else if let biography = person.biography, !biography.isEmpty {
                Button(action: {
                  showFullBio = true
                }) {
                  VStack(alignment: .leading, spacing: 8) {
                    Text("个人简介")
                      .font(.callout.bold())

                    Text(biography)
                      .font(.caption)
                      .multilineTextAlignment(.leading)
                  }
                  .frame(maxWidth: 1100)
                  .padding()
                }
                .buttonStyle(.card)
              } else {
                // 无简介时的可聚焦占位符 — 确保头部有焦点目标
                Text("暂无简介")
                  .font(.callout.bold())
                  .foregroundColor(.secondary)
                  .focusable()
              }
              Spacer(minLength: 0)
            }
            .frame(height: 600)
            Spacer()
          }
          .focusSection()

          // 作品区域标题
          VStack(alignment: .leading, spacing: 20) {
            Text("参演作品")
              .font(.callout)
              .fontWeight(.bold)
              .foregroundStyle(.secondary)
              .padding(.leading, 8)
          }
          .padding(.bottom, -16)
        }
      },
      contextMenu: { item in
        MediaContextMenuItems(
          item: item,
          navigationPath: $navigationPath,
          subscriptionHandler: subscriptionHandler
        )
      }
    )
    .task {
      await viewModel.loadCredits()
    }
    .sheet(isPresented: $showFullBio) {
      let person = viewModel.person
      if let biography = person.biography {
        ScrollView {
          VStack(alignment: .leading, spacing: 20) {
            Text(person.name ?? "个人简介")
              .font(.title2.bold())

            Text(biography)
              .font(.caption)
          }
          .padding(30)
        }
      }
    }
    .mediaSubscriptionAlerts(using: subscriptionHandler, navigationPath: $navigationPath)
  }
}

struct InfoRow: View {
  let label: String
  let value: String

  var body: some View {
    HStack(alignment: .top) {
      Text("\(label):")
        .foregroundColor(.secondary)
        .frame(width: 140, alignment: .leading)
      Text(value)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .lineLimit(1)
  }
}
