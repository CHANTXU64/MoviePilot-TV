import SwiftUI

/// 按列表位置切页，范围文案优先显示实际编号。
enum DetailPageRanges {
  static func ranges(count: Int, size: Int) -> [Range<Int>] {
    stride(from: 0, to: count, by: size).map { $0..<min($0 + size, count) }
  }

  static func current(count: Int, size: Int, offset: Int) -> Range<Int> {
    let start = min(max(offset, 0), max(count - 1, 0)) / size * size
    return start..<min(start + size, count)
  }

  static func title(for range: Range<Int>, numbers: [Int?], unit: String) -> String {
    let ordered = numbers.compactMap { $0 }
    if ordered.count == range.count, let first = ordered.first, let last = ordered.last,
      first >= 0, zip(ordered, ordered.dropFirst()).allSatisfy({ $0.0 < $0.1 })
    {
      return first == last ? "\(first) \(unit)" : "\(first)–\(last) \(unit)"
    }
    return range.count == 1 ? "第 \(range.upperBound) 项" : "第 \(range.lowerBound + 1)–\(range.upperBound) 项"
  }
}

/// 季和剧集展开页使用同一个网格宽度，卡片比例决定一行放几张。
enum DetailExpansionGridLayout {
  static let columnSpacing: CGFloat = 44

  static func columns(width: CGFloat, count: Int) -> [GridItem] {
    Array(repeating: GridItem(.fixed(width), spacing: columnSpacing, alignment: .top), count: count)
  }

  static func width(columnWidth: CGFloat, columnCount: Int) -> CGFloat {
    columnWidth * CGFloat(columnCount) + columnSpacing * CGFloat(columnCount - 1)
  }
}

struct DetailExpansionHeader<Controls: View>: View {
  let title: String
  /// 网格里卡片图片的尺寸，页头下方按它聚焦时长高的距离留空。
  var cardImageSize: CGSize = MediaCard.defaultPosterSize
  @ViewBuilder let controls: () -> Controls

  var body: some View {
    VStack(spacing: 0) {
      Text(title)
        .font(.title2.bold())
        .foregroundStyle(.secondary)
        .accessibilityAddTraits(.isHeader)
      controls()
    }
    // 第一排卡片聚焦长高后不压住标题下的按钮。
    .padding(.bottom, PosterCardFocus.topClearance(forImageSize: cardImageSize))
  }
}

/// 展开页共用滚动、网格间距、首尾焦点和图片窗口。
struct DetailExpansionGrid<Focus: Hashable, Header: View, Status: View, Card: View>: View {
  let columns: [GridItem]
  let itemIDs: [MediaInfo.ID]
  let cardFocus: FocusState<Focus?>.Binding
  let firstFocus: Focus?
  let lastFocus: Focus?
  @ViewBuilder let header: () -> Header
  @ViewBuilder let status: () -> Status
  @ViewBuilder let card: (Int, @escaping (Bool) -> Void) -> Card

  @EnvironmentObject private var navigationCoordinator: ImageNavigationCoordinator
  @State private var listIdentity: GridListIdentity
  @StateObject private var dom: GridDOMRetentionController
  @StateObject private var images: GridImageLifecycleController
  private var memoryOptimization = MemoryOptimizationSettings()
  @FocusState private var topFocused: Bool
  @FocusState private var bottomFocused: Bool

  init(
    columns: [GridItem],
    itemIDs: [MediaInfo.ID],
    imageLifecycle: PageImageLifecycle,
    cardFocus: FocusState<Focus?>.Binding,
    firstFocus: Focus?,
    lastFocus: Focus?,
    @ViewBuilder header: @escaping () -> Header,
    @ViewBuilder status: @escaping () -> Status,
    @ViewBuilder card: @escaping (Int, @escaping (Bool) -> Void) -> Card
  ) {
    self.columns = columns
    self.itemIDs = itemIDs
    self.cardFocus = cardFocus
    self.firstFocus = firstFocus
    self.lastFocus = lastFocus
    self.header = header
    self.status = status
    self.card = card

    let identity = GridListIdentity.make()
    _listIdentity = State(initialValue: identity)
    _dom = StateObject(wrappedValue: GridDOMRetentionController(
      listIdentity: identity, itemIDs: itemIDs, columnCount: columns.count
    ))
    _images = StateObject(wrappedValue: GridImageLifecycleController(
      listIdentity: identity, itemIDs: itemIDs, columnCount: columns.count, imageLifecycle: imageLifecycle
    ))
  }

  var body: some View {
    ScrollView {
      VStack(spacing: 0) {
        header()
        if itemIDs.isEmpty {
          status()
        } else {
          Color.clear
            .frame(height: 1)
            .focusable(cardFocus.wrappedValue == nil && firstFocus != nil)
            .focused($topFocused)
            .onChange(of: topFocused) { _, focused in
              guard focused else { return }
              cardFocus.wrappedValue = firstFocus
              topFocused = false
            }
            .accessibilityHidden(true)

          let identity = listIdentity
          let retainedCount = dom.retainedItemCount(for: itemIDs.count, listIdentity: identity)
          LazyVGrid(columns: columns, spacing: 56) {
            ForEach(Array(itemIDs.prefix(retainedCount).enumerated()), id: \.element) { index, itemID in
              card(index) { isFocused in
                handleFocus(identity: identity, itemID: itemID, index: index, isFocused: isFocused)
              }
              .environment(
                \.gridImageDemandContext,
                GridImageDemandContext(
                  controller: images, listIdentity: identity,
                  itemIDs: itemIDs, itemID: itemID, itemIndex: index
                )
              )
            }
          }
          .padding()

          Color.clear
            .frame(height: 1)
            .focusable(lastFocus != nil)
            .focused($bottomFocused)
            .onChange(of: bottomFocused) { _, focused in
              guard focused else { return }
              cardFocus.wrappedValue = lastFocus
              bottomFocused = false
            }
            .accessibilityHidden(true)
        }
      }
    }
    .onChange(of: memoryOptimization.isEnabled, initial: true) { _, enabled in
      images.setUsesFocusWindow(enabled)
    }
    .focusSection()
    .onScrollGeometryChange(
      for: CGFloat.self,
      of: { $0.contentOffset.y + $0.contentInsets.top },
      action: { _, offset in dom.scrollPositionChanged(adjustedOffsetY: offset) }
    )
    .onScrollPhaseChange { _, phase in dom.scrollPhaseChanged(phase) }
    .onAppear {
      reconcile()
      dom.setViewActive(true)
      dom.setStackInteractive(navigationCoordinator.isStackInteractive)
    }
    .onChange(of: itemIDs) { old, new in
      if new.count < old.count || !new.prefix(old.count).elementsEqual(old) {
        listIdentity = listIdentity.advanced()
      }
      reconcile()
    }
    .onChange(of: navigationCoordinator.isStackInteractive) { _, interactive in
      dom.setStackInteractive(interactive)
    }
    .onDisappear { dom.setViewActive(false) }
  }

  private func reconcile() {
    dom.reconcile(listIdentity: listIdentity, itemIDs: itemIDs)
    images.reconcile(listIdentity: listIdentity, itemIDs: itemIDs)
  }

  private func handleFocus(identity: GridListIdentity, itemID: MediaInfo.ID, index: Int, isFocused: Bool) {
    images.reconcileEventSnapshot(listIdentity: identity, itemIDs: itemIDs)
    dom.reconcileEventSnapshot(listIdentity: identity, itemIDs: itemIDs)
    guard images.cardFocusChanged(listIdentity: identity, itemID: itemID, itemIndex: index, isFocused: isFocused)
    else { return }
    dom.cardFocusChanged(listIdentity: identity, itemID: itemID, itemIndex: index, isFocused: isFocused)
  }
}
