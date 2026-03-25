import Kingfisher
import SwiftUI

struct PersonCard: View {
  let person: Person
  var staffImageUrl: URL? = nil
  let width: CGFloat = 210
  let height: CGFloat = 315

  // 卡片被点击时的操作
  var action: (() -> Void)? = nil

  @FocusState private var isFocused: Bool

  var body: some View {
    VStack(spacing: 10) {
      posterContent
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(
          color: .black.opacity(isFocused ? 0.5 : 0),
          radius: 20,
          y: 10
        )
        .scaleEffect(isFocused ? 1.1 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isFocused)
        .focusable(true)
        .focused($isFocused)
        .onTapGesture {
          action?()
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
    .animation(.easeInOut(duration: 0.2), value: isFocused)
  }

  private var posterContent: some View {
    let url = staffImageUrl ?? person.imageURLs.profile
    return KFImage(url)
      .requestModifier(AnyModifier.cookieModifier)
      .placeholder {
        Rectangle()
          .fill(Color(white: 0.12))
          .overlay(
            Image(systemName: "person.fill")
              .font(.largeTitle)
              .foregroundColor(.gray)
          )
      }
      .resizing(referenceSize: CGSize(width: 210, height: 315), mode: .aspectFill)
      .resizable()
      .fade(duration: 0.25)
      .aspectRatio(contentMode: .fill)
      .frame(width: width, height: height)
      .clipped()
  }
}
