import SwiftUI

// MARK: - Action Semantics & Descriptor

/// 定义操作按钮的语义角色，主要用于区分普通操作和可能产生破坏性后果的操作。
enum ActionRole {
  case normal
  case destructive
}

/// `ActionButton` 的蓝图或配方。
/// 它是一个纯数据结构，用于描述一个操作按钮，包括其文本、图标、角色和要执行的闭包。
/// `ActionRow` 使用这些描述来动态生成实际的按钮。
struct ActionDescriptor {
  let id: String
  let title: String
  let icon: String
  var role: ActionRole = .normal
  let action: () -> Void
}

// MARK: - ActionButton & Style

/// 一个完全透明的按钮样式，旨在移除 tvOS 默认会添加的所有系统级按钮背景和焦点效果。
/// 这允许我们从头开始构建自定义的按钮外观和动画，如 `ActionButton` 中所示。
private struct NakedButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      // 按下时提供轻微的视觉反馈
      .opacity(configuration.isPressed ? 0.6 : 1.0)
  }
}

/// 一个标准化的、可聚焦的按钮，设计用于 `ActionRow`。
/// 它根据 `ActionDescriptor` 构建，并根据焦点状态（`isFocused`）和角色（`role`）来改变自身外观。
struct ActionButton: View {
  let title: String
  let icon: String
  let role: ActionRole
  let isFocused: Bool
  let action: () -> Void

  init(descriptor: ActionDescriptor, isFocused: Bool = false) {
    self.title = descriptor.title
    self.icon = descriptor.icon
    self.role = descriptor.role
    self.isFocused = isFocused
    self.action = descriptor.action
  }

  var body: some View {
    Button(action: action) {
      VStack(spacing: 6) {
        Image(systemName: icon)
          .font(.system(size: 22))
          .frame(width: 24, height: 24)
        Text(title)
          .font(.caption)
      }
      .padding(.horizontal, 24)
      .padding(.vertical, 12)
      .foregroundColor(foregroundColor)
      .background(
        RoundedRectangle(cornerRadius: 30)
          .fill(backgroundColor)
      )
      // 焦点动画：放大并添加阴影
      .scaleEffect(isFocused ? 1.1 : 1.0)
      .shadow(color: .black.opacity(isFocused ? 0.3 : 0), radius: 10, x: 0, y: 8)
      .animation(.easeIn(duration: 0.2), value: isFocused)
    }
    .buttonStyle(NakedButtonStyle())
  }

  /// 根据角色和焦点状态计算前景颜色（文本和图标）。
  private var foregroundColor: Color {
    if role == .destructive {
      isFocused ? .white : .red
    } else {
      isFocused ? .black : .white
    }
  }

  /// 根据角色和焦点状态计算背景颜色。
  private var backgroundColor: Color {
    if role == .destructive {
      isFocused ? Color.red : Color.white.opacity(0.1)
    } else {
      isFocused ? Color.white : Color.white.opacity(0.1)
    }
  }
}

// MARK: - ActionRow

/// 一个可重用的 SwiftUI 容器视图，它包装任何内容，并在用户聚焦到该行时，
/// 以动画形式从右侧“揭示”一组操作按钮。
///
/// 这个视图内部管理焦点：
/// 1. 初始焦点落在主内容上。
/// 2. 用户可以向右导航，将焦点逐一移动到操作按钮上。
/// 3. 当焦点离开整行（包括内容和所有按钮）时，操作按钮会平滑地隐藏。
struct ActionRow<Content: View, Background: View, ProgressBar: View>: View {

  // MARK: - 焦点管理
  private enum FocusField: Hashable {
    case content
    case action(String)
  }
  @FocusState private var focusedField: FocusField?

  // MARK: - Properties
  let actions: [ActionDescriptor]
  @ViewBuilder let content: (Bool) -> Content
  @ViewBuilder let background: () -> Background
  @ViewBuilder let progressBar: () -> ProgressBar

  private let cornerRadius: CGFloat = 20

  /// 存储测量到的操作按钮容器的总宽度。
  /// 此值用于确定当行激活时，主内容需要向左移动多少距离。
  @State private var measuredActionsWidth: CGFloat = 0

  /// 如果行的任何部分（主内容或任何操作按钮）具有焦点，则为 true。
  /// 这是触发“揭示”动画的主要条件。
  private var isRowActive: Bool {
    focusedField != nil
  }

  /// 仅当主内容区域获得焦点时为 true。
  private var isContentFocused: Bool {
    focusedField == .content
  }

  // MARK: - Initializer
  init(
    actions: [ActionDescriptor],
    @ViewBuilder content: @escaping (Bool) -> Content,
    @ViewBuilder background: @escaping () -> Background,
    @ViewBuilder progressBar: @escaping () -> ProgressBar
  ) {
    self.actions = actions
    self.content = content
    self.background = background
    self.progressBar = progressBar
  }

  // MARK: - Body
  var body: some View {
    ZStack(alignment: .trailing) {
      // 图层 1: 操作按钮 (底层, 右对齐)
      HStack(spacing: 16) {
        ForEach(actions, id: \.id) { actionDesc in
          ActionButton(
            descriptor: actionDesc,
            isFocused: focusedField == .action(actionDesc.id)
          )
          .focused($focusedField, equals: .action(actionDesc.id))
        }
      }
      .padding(.horizontal, 16)
      // 使用 PreferenceKey 测量操作按钮行的实际渲染宽度
      .background(
        GeometryReader { geo in
          Color.clear
            .preference(key: ActionsWidthPreferenceKey.self, value: geo.size.width)
        }
      )
      .onPreferenceChange(ActionsWidthPreferenceKey.self) { width in
        // 将测量到的宽度存储起来，用于后续的 padding 计算
        // 使用非常小的阈值避免不必要的无限重绘
        if abs(measuredActionsWidth - width) > 0.5 {
          measuredActionsWidth = width
        }
      }
      .opacity(isRowActive ? 1 : 0)  // 非激活状态时完全透明

      // 图层 2: 主内容 (顶层, 可聚焦)
      content(isRowActive)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focusable()
        .focused($focusedField, equals: .content)
        .background(Color.white.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        // 自定义阴影效果：
        // 由于 content 背景是半透明的，原生的 .shadow 效果不佳。
        // 这里通过带模糊效果的描边(stroke)来模拟一个更清晰的阴影，
        // 这种方式不会被背景内容遮挡，并且在 tvOS 上效果更好。
        .background(
          RoundedRectangle(cornerRadius: cornerRadius)
            .stroke(isContentFocused ? Color.black.opacity(0.7) : Color.clear, lineWidth: 10)
            .blur(radius: 10)
        )
        // ✨ 核心动画 ✨
        // 当 `isRowActive` 变为 true 时，为此视图的尾部添加一个等于操作按钮宽度的 padding。
        // 这会“挤压”主内容的宽度，使其向左收缩，从而优雅地揭示出下方的操作按钮。
        .padding(.trailing, isRowActive ? measuredActionsWidth : 0)
    }
    // 整体背景 (包含海报图和进度条)
    .background(
      ZStack {
        // 背景层 (静态, 经过裁剪)
        Color.clear
          .overlay(background())

        // 进度条层 (静态)
        VStack {
          Spacer()
          progressBar()
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    )
    .scaleEffect(isRowActive ? 1.02 : 1.0)
    .animation(.easeInOut(duration: 0.2), value: isRowActive)
    .animation(.easeInOut(duration: 0.2), value: focusedField)
  }
}

// MARK: - Convenience Initializers
// 提供便捷初始化器，允许在不提供 background 或 progressBar 时省略它们
extension ActionRow where Background == EmptyView, ProgressBar == EmptyView {
  init(actions: [ActionDescriptor], @ViewBuilder content: @escaping (Bool) -> Content) {
    self.init(
      actions: actions, content: content, background: { EmptyView() }, progressBar: { EmptyView() })
  }
}

extension ActionRow where ProgressBar == EmptyView {
  init(
    actions: [ActionDescriptor], @ViewBuilder content: @escaping (Bool) -> Content,
    @ViewBuilder background: @escaping () -> Background
  ) {
    self.init(
      actions: actions, content: content, background: background, progressBar: { EmptyView() })
  }
}

extension ActionRow where Background == EmptyView {
  init(
    actions: [ActionDescriptor], @ViewBuilder content: @escaping (Bool) -> Content,
    @ViewBuilder progressBar: @escaping () -> ProgressBar
  ) {
    self.init(
      actions: actions, content: content, background: { EmptyView() }, progressBar: progressBar)
  }
}

// MARK: - Helper PreferenceKey
/// 用于从子视图（操作按钮容器）向父视图（ActionRow）传递其计算出宽度的 PreferenceKey。
struct ActionsWidthPreferenceKey: PreferenceKey {
  static var defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    // 确保我们总是取最大值，以防在视图渲染过程中宽度发生变化。
    value = max(value, nextValue())
  }
}
