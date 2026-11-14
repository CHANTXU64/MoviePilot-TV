import SwiftUI

/// 横向卡片行的页头随聚焦上移。
///
/// 页头里每一块（标题文字、按钮组）各自判断：聚焦的卡片正好在这一块下方时，这一块上移卡片长高的距离，
/// 与放大后的卡片保持原来的间距；焦点移出这一块的宽度，它就落回原位。左边的选择器和右边的按钮互不牵连。
/// 宽度和卡片位置都在运行时量，按钮多少、季名长短不用另算。
///
/// 用法：
/// - 行容器挂 `focusLiftRow(cardImageSize:)`，上移距离取卡片图片聚焦时往上长出的高度；
/// - 页头里实际有内容的每一块挂 `focusLiftHeaderPart()`（中间有 `Spacer` 的左右两块分别挂）；
/// - 每张卡挂 `focusLiftCard(isFocused:)`。
///
/// 位置按行坐标系量，整页上下滚动时不变；卡片只在跨进、跨出某一块时上报，滚动途中不逐帧刷新页头。
/// 只有聚焦的那张卡量位置，其余卡片横向滚动时不写状态。
///
/// 焦点移到屏幕外的卡片时，横排要滚一段才把它带进来。这段时间卡片还在行外，直接比位置会先判成
/// 「下方没有卡片」、页头落下，滚到位后又顶起来，来回弹一下。所以比之前先把卡片挪回行的可见宽度内，
/// 按滚动结束后的位置判断。
nonisolated private let focusLiftRowSpace = "FocusLiftRow"

private nonisolated struct FocusLiftSpan: Equatable, Sendable {
  var minX: CGFloat
  var maxX: CGFloat

  init(_ frame: CGRect) {
    minX = frame.minX
    maxX = frame.maxX
  }

  func overlaps(_ other: FocusLiftSpan) -> Bool {
    minX < other.maxX && maxX > other.minX
  }

  /// 挪进 0…`width` 之内：超出右边就贴右边，超出左边就贴左边，相当于横排把它滚进来后的位置。
  func shifted(into width: CGFloat) -> FocusLiftSpan {
    guard width > 0 else { return self }
    var span = self
    if span.maxX > width {
      let shift = span.maxX - width
      span.minX -= shift
      span.maxX -= shift
    }
    if span.minX < 0 {
      let shift = -span.minX
      span.minX += shift
      span.maxX += shift
    }
    return span
  }
}

private nonisolated struct FocusLiftHeaderPartFrame: Equatable, Sendable {
  let id: UUID
  let span: FocusLiftSpan
}

private nonisolated struct FocusLiftHeaderPartsKey: PreferenceKey {
  static let defaultValue: [FocusLiftHeaderPartFrame] = []
  static func reduce(value: inout [FocusLiftHeaderPartFrame], nextValue: () -> [FocusLiftHeaderPartFrame]) {
    value.append(contentsOf: nextValue())
  }
}

private nonisolated struct FocusLiftLiftedPartsKey: PreferenceKey {
  static let defaultValue: Set<UUID> = []
  static func reduce(value: inout Set<UUID>, nextValue: () -> Set<UUID>) {
    value.formUnion(nextValue())
  }
}

private nonisolated struct FocusLiftHeaderPartsEnvironmentKey: EnvironmentKey {
  static let defaultValue: [FocusLiftHeaderPartFrame] = []
}

private nonisolated struct FocusLiftLiftedPartsEnvironmentKey: EnvironmentKey {
  static let defaultValue: Set<UUID> = []
}

private nonisolated struct FocusLiftDistanceEnvironmentKey: EnvironmentKey {
  static let defaultValue: CGFloat = 0
}

private nonisolated struct FocusLiftRowWidthEnvironmentKey: EnvironmentKey {
  static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
  fileprivate var focusLiftHeaderParts: [FocusLiftHeaderPartFrame] {
    get { self[FocusLiftHeaderPartsEnvironmentKey.self] }
    set { self[FocusLiftHeaderPartsEnvironmentKey.self] = newValue }
  }

  fileprivate var focusLiftLiftedParts: Set<UUID> {
    get { self[FocusLiftLiftedPartsEnvironmentKey.self] }
    set { self[FocusLiftLiftedPartsEnvironmentKey.self] = newValue }
  }

  fileprivate var focusLiftDistance: CGFloat {
    get { self[FocusLiftDistanceEnvironmentKey.self] }
    set { self[FocusLiftDistanceEnvironmentKey.self] = newValue }
  }

  fileprivate var focusLiftRowWidth: CGFloat {
    get { self[FocusLiftRowWidthEnvironmentKey.self] }
    set { self[FocusLiftRowWidthEnvironmentKey.self] = newValue }
  }
}

private struct FocusLiftRowContainer: ViewModifier {
  let lift: CGFloat
  @State private var headerParts: [FocusLiftHeaderPartFrame] = []
  @State private var liftedParts: Set<UUID> = []
  /// 卡片最近一次上报的集合；落下要等一小会儿，期间以它为准。
  @State private var reportedParts: Set<UUID> = []
  @State private var dropTask: Task<Void, Never>?
  @State private var rowWidth: CGFloat = 0

  func body(content: Content) -> some View {
    content
      .environment(\.focusLiftHeaderParts, headerParts)
      .environment(\.focusLiftLiftedParts, liftedParts)
      .environment(\.focusLiftDistance, lift)
      .environment(\.focusLiftRowWidth, rowWidth)
      .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rowWidth = $0 }
      .onPreferenceChange(FocusLiftHeaderPartsKey.self) { headerParts = $0 }
      .onPreferenceChange(FocusLiftLiftedPartsKey.self) { reportLiftedParts($0) }
      .coordinateSpace(.named(focusLiftRowSpace))
      .onDisappear { dropTask?.cancel() }
  }

  /// 上移立即生效，落下稍等再生效：焦点从一张卡换到下一张时，新卡的位置晚一拍才量到，
  /// 中间会短暂上报「下方没有卡片」。马上落下再顶起就是那一下弹动，等一小会儿就被下一次上报盖掉了。
  private func reportLiftedParts(_ parts: Set<UUID>) {
    reportedParts = parts
    dropTask?.cancel()
    dropTask = nil
    liftedParts.formUnion(parts)
    guard liftedParts != parts else { return }
    dropTask = Task {
      try? await Task.sleep(for: .milliseconds(150))
      guard !Task.isCancelled else { return }
      liftedParts = reportedParts
    }
  }
}

private struct FocusLiftHeaderPart: ViewModifier {
  @State private var id = UUID()
  @State private var span: FocusLiftSpan?
  @Environment(\.focusLiftLiftedParts) private var liftedParts
  @Environment(\.focusLiftDistance) private var lift
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func body(content: Content) -> some View {
    let isLifted = liftedParts.contains(id)
    content
      .onGeometryChange(for: FocusLiftSpan.self) { proxy in
        FocusLiftSpan(proxy.frame(in: .named(focusLiftRowSpace)))
      } action: { span = $0 }
      // 空的按钮区宽度为 0，不算页头内容。
      .preference(
        key: FocusLiftHeaderPartsKey.self,
        value: span.map { $0.maxX - $0.minX >= 1 ? [FocusLiftHeaderPartFrame(id: id, span: $0)] : [] } ?? []
      )
      .offset(y: isLifted ? -lift : 0)
      .animation(reduceMotion ? nil : PosterCardFocus.animation, value: isLifted)
  }
}

private struct FocusLiftCard: ViewModifier {
  let isFocused: Bool
  @Environment(\.focusLiftHeaderParts) private var headerParts
  @Environment(\.focusLiftRowWidth) private var rowWidth
  @State private var span: FocusLiftSpan?

  func body(content: Content) -> some View {
    content
      // 没聚焦时恒为 nil，横向滚动时不触发 action、不写状态；聚焦变化本身会让结果变化，取到当前位置。
      .onGeometryChange(for: FocusLiftSpan?.self) { [isFocused] proxy in
        isFocused ? FocusLiftSpan(proxy.frame(in: .named(focusLiftRowSpace))) : nil
      } action: { span = $0 }
      .preference(key: FocusLiftLiftedPartsKey.self, value: liftedParts)
  }

  /// 聚焦时，自己（按滚进可见宽度后的位置）正下方覆盖到的页头块；集合只在跨进、跨出某一块时变化。
  private var liftedParts: Set<UUID> {
    guard isFocused, let span else { return [] }
    let settled = span.shifted(into: rowWidth)
    return Set(headerParts.filter { $0.span.overlaps(settled) }.map(\.id))
  }
}

extension View {
  /// 横向卡片行的容器：收集页头各块宽度和聚焦卡片位置，决定哪一块上移。
  /// `cardImageSize` 是行里卡片图片的尺寸，上移距离等于它聚焦时往上长出的高度。
  func focusLiftRow(cardImageSize: CGSize) -> some View {
    modifier(FocusLiftRowContainer(lift: PosterCardFocus.focusedVerticalGrowth(forImageSize: cardImageSize)))
  }

  /// 页头里实际有内容的一块（标题、按钮组）；聚焦卡片在它正下方时只有这一块上移。
  func focusLiftHeaderPart() -> some View {
    modifier(FocusLiftHeaderPart())
  }

  /// 行里的一张卡片；`isFocused` 用行自己的焦点状态判断。
  func focusLiftCard(isFocused: Bool) -> some View {
    modifier(FocusLiftCard(isFocused: isFocused))
  }
}
