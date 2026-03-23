import Kingfisher
import SwiftUI

struct PersonCard: View {
  static let defaultGridColumns = [
    GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 20, alignment: .top)
  ]

  let person: Person
  var staffImageUrl: URL? = nil
  let width: CGFloat = 180
  let height: CGFloat = 270

  // 卡片被点击时的操作
  var action: (() -> Void)? = nil

  @FocusState private var isFocused: Bool
  @State private var isImageFailed: Bool = false

  var body: some View {
    VStack(spacing: 10) {
      if let action = action {
        Button(action: action) {
          posterContent
        }
        .focused($isFocused)
        .frame(width: width, height: height)
        .buttonStyle(.card)
      } else {
        posterContent
      }

      textInfoView
    }
  }

  private var textInfoView: some View {
    VStack(spacing: 4) {
      VStack {
        Text(person.name ?? "未知")
          .font(.caption)
          .fontWeight(.medium)
          .foregroundStyle(isFocused ? .primary : .secondary)

        if let subtitle = (person.job != nil && !person.job!.isEmpty)
          ? person.job : person.character, !subtitle.isEmpty
        {
          Text(subtitle)
            .font(.caption2)
            .foregroundStyle(isFocused ? .secondary : .tertiary)
        }
      }
      .lineLimit(1)
      .compositingGroup()
      .frame(maxWidth: isFocused ? width + 20 : width, alignment: .center)
    }
    .frame(width: width + 20)
    .padding(.horizontal, -10)
    .offset(y: isFocused ? 16 : 0)
    .animation(.easeOut(duration: 0.3), value: isFocused)
  }

  private var posterContent: some View {
    let url = staffImageUrl ?? person.imageURLs.profile
    return ZStack {
      // 1. 背景 / 失败状态
      Rectangle()
        .fill(Color(white: 0.12))
        .overlay(
          Image(systemName: "person.fill")
            .font(.largeTitle)
            .foregroundColor(.gray)
        )

      // 2. 网络图片
      if !isImageFailed, let validUrl = url {
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
          .resizing(referenceSize: CGSize(width: 180, height: 270), mode: .aspectFill)
          .resizable()
          .fade(duration: 0.25)
          .aspectRatio(contentMode: .fill)
          .frame(width: width, height: height)
          .clipped()
      }
    }
    .onChange(of: url) { _, _ in
      isImageFailed = false
    }
  }
}
