import SwiftUI

/// 图标位加载指示：槽位尺寸始终由真实图标决定，加载时把系统转圈缩到图标大小叠在图标位上。
/// 转圈只放在 overlay 里（不参与布局），加载出现或消失都不会改变按钮/行的高度与宽度。
/// 系统转圈约 40pt，默认按钮字号的图标约 34pt，与 `SheetActionButton` 原有比例一致。
struct LoadingIcon: View {
  let systemImage: String
  var isLoading: Bool

  static let spinnerScale: CGFloat = 0.85

  var body: some View {
    Image(systemName: systemImage)
      .opacity(isLoading ? 0 : 1)
      .overlay {
        if isLoading {
          ProgressView()
            .scaleEffect(Self.spinnerScale)
        }
      }
  }
}

/// 货架行尾的「加载更多」指示：转圈占一张海报的高度，下面预留卡片文字槽，
/// 内容到达时行高不跳。详情页与搜索页的多处行尾共用这一种写法。
struct RowLoadingTail: View {
  let height: CGFloat

  var body: some View {
    VStack(spacing: 10) {
      ProgressView()
        .frame(width: 100, height: height)
      Color.clear
        .frame(width: 100, height: 44)
    }
  }
}

/// 页面/区块首次加载的统一指示：居中裸转圈，不配文字（转圈本身已表示进行中）。
/// minHeight 用于预留区块高度防跳；maxHeight 传 .infinity 时撑满整页。
struct FirstLoadIndicator: View {
  var minHeight: CGFloat? = 200
  var maxHeight: CGFloat? = nil

  var body: some View {
    ProgressView()
      .frame(maxWidth: .infinity, minHeight: minHeight, maxHeight: maxHeight)
  }
}

/// 货架行「还没有内容」时的三态状态卡：加载中 / 加载失败 / 暂无内容。
/// 三态共用同一视图身份，状态切换焦点不丢；尺寸等于正常卡片，内容到达行高不跳。
/// 豆瓣讨论区与剧集货架共用；焦点/无障碍语义由 focusStyle 保留各自原有写法。
struct ShelfStatusCard: View {
  enum Status: Equatable {
    case loading(String)
    case failed(String)
    case empty(String)

    var text: String {
      switch self {
      case .loading(let text), .failed(let text), .empty(let text): return text
      }
    }
  }

  enum FocusStyle {
    /// 豆瓣讨论区：可聚焦 Button，不响应选择键。
    case button
    /// 剧集货架：focusable + 静态文本无障碍语义。
    case focusable(isFocused: Bool)
  }

  let status: Status
  let size: CGSize
  var emptyIcon: String = AppSymbol.noResults
  /// 失败文案加粗且用主色（豆瓣原有样子）；默认常规次色（剧集原有样子）。
  var failedEmphasis = false
  var focusStyle: FocusStyle = .focusable(isFocused: false)

  var body: some View {
    let content = VStack(spacing: 14) {
      switch status {
      case .loading:
        ProgressView()
      case .failed:
        Image(systemName: AppSymbol.warning)
          .font(.title3)
          .foregroundStyle(.secondary)
      case .empty:
        Image(systemName: emptyIcon)
          .font(.title3)
          .foregroundStyle(.secondary)
      }
      Text(status.text)
        .font(isFailed && failedEmphasis ? .caption.bold() : .caption)
        .foregroundStyle(isFailed && failedEmphasis ? .primary : .secondary)
    }
    .frame(width: size.width, height: size.height)

    switch focusStyle {
    case .button:
      Button {
      } label: {
        content
      }
      .buttonStyle(TextCardButtonStyle())
      .accessibilityLabel(status.text)
    case .focusable(let isFocused):
      content
        .textCardFocusAppearance(isFocused: isFocused)
        .focusable()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(status.text)
        .accessibilityAddTraits(.isStaticText)
    }
  }

  private var isFailed: Bool {
    if case .failed = status { return true }
    return false
  }
}