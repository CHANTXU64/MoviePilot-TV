import SwiftUI

/// 单集卡片剧照上的状态，画在剧照里面，随聚焦一起放大。
///
/// - 能播放：左下角播放图标，后面跟这一集的时长；个别集没法对应：左下角一个警告图标。
///   没聚焦时用次一级的亮度，聚焦时才全亮。已入库的剧可能整季都能播，不能每张都大大地标。
///   托底的浅渐变由卡片每张都铺（见 `EpisodeCardContent`），不随能不能播出现或消失。
/// - 试看进行中：剧照压暗，正中是进度（拿得到下载进度时是逐渐填满的圆环，否则只转圈），下面是这一步的短字和几步的进度点。
///   同一季只能有一集在试看，一行里一般只有一张这样的卡。
/// - 试看结局：剧照轻压暗，正中一个静止的图标和短字。不动表示已经停了，和进行中的圆环分开。
struct EpisodeCardStatusOverlay: View {
  let status: EpisodeEntry.CardStatus
  let stillSize: CGSize
  /// 能播放时跟在播放图标后面的时长，例如「45 分钟」。
  var runtimeText: String? = nil
  var isFocused = false

  var body: some View {
    switch status {
    case .playable:
      cornerBadge(AppSymbol.play, tint: .white, text: runtimeText)
    case .attention:
      cornerBadge(AppSymbol.warning, tint: .yellow)
    case .trialInProgress(let indicator):
      ZStack {
        Color.black.opacity(0.55)
        VStack(spacing: 12) {
          EpisodeTrialRing(fraction: indicator.fraction, diameter: ringDiameter)
          Text(indicator.label)
            .font(.caption.bold())
            .lineLimit(1)
            // 下载剩余时间按小时写时字多，展开页的小卡片上缩一点也要放得下。
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 12)
          if let stage = indicator.stage {
            EpisodeTrialStageDots(current: stage)
          }
        }
        .foregroundStyle(.white)
      }
    case .trialStopped(let ending):
      ZStack {
        Color.black.opacity(0.35)
        VStack(spacing: 10) {
          Image(systemName: ending.isHandledElsewhere ? AppSymbol.info : AppSymbol.warning)
            .font(.title3)
          if let label = ending.shortLabel {
            Text(label)
              .font(.caption.bold())
              .lineLimit(1)
          }
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
      }
    }
  }

  /// 展开页的卡片比剧集行小，圆环跟着缩小。
  private var ringDiameter: CGFloat {
    min(76, stillSize.height * 0.33)
  }

  /// 左下角的小图标（和可选的短字）直接压在剧照上，不垫底座。
  private func cornerBadge(_ symbol: String, tint: Color, text: String? = nil) -> some View {
    HStack(spacing: 10) {
      Image(systemName: symbol)
        .imageScale(.small)
        .foregroundStyle(tint)
      if let text {
        Text(text)
          .foregroundStyle(.white)
          .monospacedDigit()
          .lineLimit(1)
      }
    }
    // 和海报四角徽标同一级（caption2，tvOS 最小字号），比卡片下面的单集标题（caption）小一级。
    .font(.caption2.bold())
    // 只改透明度：没聚焦时次一级，聚焦时全亮，跟着卡片的聚焦动画变化。
    .opacity(isFocused ? 1 : 0.65)
    .padding(ImageBadgeScrim.inset)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
  }
}

/// 试看进度：有下载进度时是按进度填满的圆环、中间写百分比；没有时只转圈，不画空的底圈（空底圈像卡在 0%）。
/// 两种都是圆形、占同样大小，从转圈换成圆环时不跳动。
struct EpisodeTrialRing: View {
  let fraction: Double?
  let diameter: CGFloat

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    let lineWidth = max(4, diameter * 0.08)
    ZStack {
      if let fraction {
        Circle()
          .stroke(Color.white.opacity(0.25), lineWidth: lineWidth)
        Circle()
          .trim(from: 0, to: max(0.02, fraction))
          .stroke(Color.white, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
          .rotationEffect(.degrees(-90))
          .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: fraction)
        Text("\(Int((fraction * 100).rounded()))%")
          .font(.caption2.bold())
          .monospacedDigit()
          .minimumScaleFactor(0.6)
          .lineLimit(1)
          .padding(lineWidth)
      } else {
        ProgressView()
          .tint(.white)
      }
    }
    .frame(width: diameter, height: diameter)
  }
}

/// 试看几步的进度点：当前这一步和之前的点亮。
struct EpisodeTrialStageDots: View {
  let current: EpisodeTrialStage

  var body: some View {
    HStack(spacing: 8) {
      ForEach(EpisodeTrialStage.allCases, id: \.self) { stage in
        Capsule()
          .fill(Color.white.opacity(stage <= current ? 1 : 0.3))
          .frame(width: 20, height: 6)
      }
    }
    .accessibilityHidden(true)
  }
}
