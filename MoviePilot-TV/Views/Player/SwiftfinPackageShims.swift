import SwiftUI
import UIKit

// 移植自 Swiftfin 的播放器代码用到几个 MoviePilot-TV 没有引入的第三方包。
// 这里按移植代码实际调用到的接口提供最小替身，接口名与原包一致，移植文件无需改动：
// - `HostingController`：nathantannar4/Engine 的托管控制器（这里是 `UIHostingController` 子类）。
// - `CollectionHStack` / `CollectionVGrid`：LePips/CollectionHStack、LePips/CollectionVGrid（这里用 SwiftUI 懒加载栈实现）。
// 若日后引入原包，删除对应替身即可。

// MARK: - HostingController

class HostingController<Content: View>: UIHostingController<Content> {

  // 显式非隔离析构，避开 tvOS 18 的隔离析构回部署崩溃。
  nonisolated deinit {}

  /// 与 Engine 的 `HostingController.content` 相同：读写根视图。
  var content: Content {
    get { rootView }
    set { rootView = newValue }
  }

  /// 与 Engine 相同：不让托管视图再加系统安全区边距。
  var disableSafeArea: Bool = false {
    didSet { safeAreaRegions = disableSafeArea ? [] : .all }
  }

  /// Engine 用来在下一次 SwiftUI 更新中允许 UIKit 动画；`UIHostingController` 默认即允许，这里只保留接口。
  var automaticallyAllowUIKitAnimationsForNextUpdate = false

  init(content: Content) {
    super.init(rootView: content)
  }

  @available(*, unavailable)
  @MainActor required dynamic init?(coder aDecoder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

// MARK: - CollectionHStack

/// 横向一行的集合。`layout` 只支持移植代码用到的 `.minimumWidth`：
/// 每列不窄于 `columnWidth`，并多露出 `columnFraction` 列提示还能滚动。
struct CollectionHStack<Data: RandomAccessCollection, ID: Hashable, Content: View>: View {

  enum Layout {
    case minimumWidth(columnWidth: CGFloat, rows: Int, columnFraction: CGFloat)
  }

  enum ScrollBehavior {
    case continuous
    case continuousLeadingEdge
  }

  private let data: Data
  private let id: KeyPath<Data.Element, ID>
  private let layout: Layout
  private let content: (Data.Element) -> Content
  private var initialID: ID?
  private var clipsContent = true
  private var contentInsets = EdgeInsets()
  private var spacing: CGFloat = 10

  init(
    uniqueElements data: Data,
    id: KeyPath<Data.Element, ID>,
    layout: Layout,
    @ViewBuilder content: @escaping (Data.Element) -> Content
  ) {
    self.data = data
    self.id = id
    self.layout = layout
    self.content = content
  }

  func initialElement(id: ID?) -> Self {
    var copy = self
    copy.initialID = id
    return copy
  }

  func clipsToBounds(_ clips: Bool) -> Self {
    var copy = self
    copy.clipsContent = clips
    return copy
  }

  func insets(_ insets: EdgeInsets) -> Self {
    var copy = self
    copy.contentInsets = insets
    return copy
  }

  func itemSpacing(_ spacing: CGFloat) -> Self {
    var copy = self
    copy.spacing = spacing
    return copy
  }

  func scrollBehavior(_ behavior: ScrollBehavior) -> Self {
    self
  }

  private func columnWidth(for width: CGFloat) -> CGFloat {
    guard case .minimumWidth(let minimum, _, let fraction) = layout else { return width }
    let available = max(0, width - contentInsets.leading - contentInsets.trailing)
    guard minimum > 0, available > 0 else { return minimum }
    var columns = max(1, ((available + spacing) / (minimum + spacing)).rounded(.down))
    while columns > 1 {
      let candidate = (available - spacing * columns) / (columns + fraction)
      if candidate >= minimum { return candidate }
      columns -= 1
    }
    return max(minimum, (available - spacing) / (1 + fraction))
  }

  var body: some View {
    GeometryReader { proxy in
      let itemWidth = columnWidth(for: proxy.size.width)
      ScrollViewReader { reader in
        ScrollView(.horizontal) {
          LazyHStack(alignment: .top, spacing: spacing) {
            ForEach(data, id: id) { element in
              content(element)
                .frame(width: itemWidth)
                .id(element[keyPath: id])
            }
          }
          .padding(contentInsets)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled(!clipsContent)
        .onAppear {
          if let initialID { reader.scrollTo(initialID, anchor: .leading) }
        }
      }
    }
  }
}

// MARK: - CollectionVGrid

/// 纵向网格。`layout` 只支持移植代码用到的 `.columns`。
struct CollectionVGrid<Data: RandomAccessCollection, ID: Hashable, Content: View>: View {

  enum Layout {
    case columns(Int, insets: EdgeInsets, itemSpacing: CGFloat, lineSpacing: CGFloat)
  }

  private let data: Data
  private let id: KeyPath<Data.Element, ID>
  private let layout: Layout
  private let content: (Data.Element, Int) -> Content

  init(
    uniqueElements data: Data,
    id: KeyPath<Data.Element, ID>,
    layout: Layout,
    @ViewBuilder viewProvider: @escaping (Data.Element) -> Content
  ) {
    self.data = data
    self.id = id
    self.layout = layout
    self.content = { element, _ in viewProvider(element) }
  }

  init(
    uniqueElements data: Data,
    id: KeyPath<Data.Element, ID>,
    layout: Layout,
    @ViewBuilder viewProvider: @escaping (Data.Element, Int) -> Content
  ) {
    self.data = data
    self.id = id
    self.layout = layout
    self.content = viewProvider
  }

  var body: some View {
    let (columnCount, insets, itemSpacing, lineSpacing): (Int, EdgeInsets, CGFloat, CGFloat) =
      switch layout {
      case .columns(let count, let insets, let itemSpacing, let lineSpacing):
        (count, insets, itemSpacing, lineSpacing)
      }
    ScrollView {
      LazyVGrid(
        columns: Array(repeating: GridItem(.flexible(), spacing: itemSpacing), count: max(1, columnCount)),
        spacing: lineSpacing
      ) {
        ForEach(Array(data.enumerated()), id: \.offset) { offset, element in
          content(element, offset)
        }
      }
      .padding(insets)
    }
  }
}
