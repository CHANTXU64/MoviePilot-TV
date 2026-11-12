import SwiftUI

/// 单集卡片剧照上的状态，画在剧照里面，随聚焦一起放大。
///
/// - 能播放、个别集没法对应：左下角一个小图标。已入库的剧可能整季都能播，不能每张都大大地标。
/// - 试看进行中：剧照压暗，正中一个圆环（拿得到下载进度时逐渐填满，否则转圈），下面是这一步的短字和几步的进度点。
///   同一季只能有一集在试看，一行里一般只有一张这样的卡。
/// - 试看结局：剧照轻压暗，正中一个静止的图标和短字。不动表示已经停了，和进行中的圆环分开。
struct EpisodeCardStatusOverlay: View {
  let status: EpisodeEntry.CardStatus
  let stillSize: CGSize

  var body: some View {
    switch status {
    case .playable:
      cornerBadge(AppSymbol.play, tint: .white)
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

  private func cornerBadge(_ symbol: String, tint: Color) -> some View {
    Image(systemName: symbol)
      .font(.caption.bold())
      .foregroundStyle(tint)
      .frame(width: 48, height: 48)
      .background(Circle().fill(Color.black.opacity(0.6)))
      .padding(14)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
  }
}

/// 试看进度的圆环：有下载进度时按进度填满、中间写百分比；没有时在同一个圆里转圈，不在圆环和进度条之间切换。
struct EpisodeTrialRing: View {
  let fraction: Double?
  let diameter: CGFloat

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    let lineWidth = max(4, diameter * 0.08)
    ZStack {
      Circle()
        .stroke(Color.white.opacity(0.25), lineWidth: lineWidth)
      if let fraction {
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
