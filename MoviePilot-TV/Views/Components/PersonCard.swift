import Kingfisher
import SwiftUI

struct PersonCard: View {
  static let imageSize = CGSize(width: 210, height: 315)

  /// 按卡片实际显示尺寸直接下采样，避免先完整解码人物原图再重绘缩小图。
  static func imageProcessor(for size: CGSize = imageSize) -> any ImageProcessor {
    DownsamplingImageProcessor(size: size)
  }

  let person: Person
  var staffImageUrl: URL? = nil
  let width: CGFloat
  let height: CGFloat
  var loadsImage: Bool = true

  // 卡片被点击时的操作
  var action: (() -> Void)? = nil

  @FocusState private var isFocused: Bool

  init(
    person: Person,
    staffImageUrl: URL? = nil,
    width: CGFloat = imageSize.width,
    height: CGFloat = imageSize.height,
    loadsImage: Bool = true,
    action: (() -> Void)? = nil
  ) {
    self.person = person
    self.staffImageUrl = staffImageUrl
    self.width = width
    self.height = height
    self.loadsImage = loadsImage
    self.action = action
  }

  var body: some View {
    VStack(spacing: 10) {
      Button {
        action?()
      } label: {
        posterContent
          .frame(width: width, height: height)
          .posterCardFocusLift(isFocused: isFocused, width: width)
      }
      .buttonStyle(PosterCardButtonStyle())
      .focusEffectDisabled()
      .focused($isFocused)
      .accessibilityLabel(person.name ?? "未知")

      textInfoView
    }
    .posterCardFocusAnimation(isFocused: isFocused)
    // 放进页头上移的横排时自动参与，见 `FocusLiftRowHeader`。
    .focusLiftCard(isFocused: isFocused)
  }

  private var textInfoView: some View {
    VStack(spacing: 4) {
      VStack {
        Text(person.name ?? "未知")
          .font(.caption)
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
      .frame(maxWidth: isFocused ? width + PosterCardFocus.focusedTextExtraWidth : width, alignment: .center)
    }
    .frame(width: width + PosterCardFocus.focusedTextExtraWidth)
    .padding(.horizontal, -PosterCardFocus.focusedTextExtraWidth / 2)
    .offset(y: isFocused ? PosterCardFocus.focusedTextOffset(forImageSize: CGSize(width: width, height: height)) : 0)
    .posterCardTitleAnimation(isFocused: isFocused)
  }

  private var posterContent: some View {
    let url = staffImageUrl ?? person.imageURLs.profile
    return ZStack {
      Rectangle()
        .fill(Color(white: 0.12))
        .overlay(
          Image(systemName: AppSymbol.person)
            .font(.title2)
            .foregroundColor(.gray)
        )

      PageManagedImage(
        url: url,
        processor: Self.imageProcessor(for: CGSize(width: width, height: height)),
        isEnabled: loadsImage,
        participatesInPageLifecycle: true,
        skipsMemoryCache: true
      )
    }
    .frame(width: width, height: height)
    .clipped()
  }
}
