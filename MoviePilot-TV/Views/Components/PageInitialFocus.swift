import SwiftUI

extension View {
  /// 本页第一次出现时由 `claimsInitialFocus()` 标出的控件接管焦点，焦点进了本页（含用户主动移动）就停，之后不再抢。
  ///
  /// 从上一页的菜单项直接打开本页时，系统菜单收起后要把焦点还给已被本页盖住的菜单按钮，焦点就落到
  /// Tab 栏上（这时按 Menu 会退出 App）。和 Top Shelf 直达详情页一样，等本页呈现完、在栈顶且没有转场
  /// 或菜单盖着时再写（见 `PresentationReadyAction`）。焦点在 Tab 栏上时只能写到具体控件，写给整页容器不生效。
  ///
  /// 是否已接管记在页面上：加载中的「取消」在转场结束前就换成结果或失败界面时，由当前显示的控件接着认领。
  func providesInitialFocusClaim() -> some View {
    modifier(InitialFocusClaimProvider())
  }

  /// 本页还没接管过焦点时，这个控件认领首个焦点（见 `providesInitialFocusClaim()`）。
  /// 不在提供方页面里（如搜索页内嵌的结果）时不做任何事。同一时刻一页只标一个显示中的控件。
  func claimsInitialFocus() -> some View {
    modifier(InitialFocusClaim())
  }
}

@Observable
final class InitialFocusClaimState {
  var hasClaimed = false
  nonisolated deinit {}
}

extension EnvironmentValues {
  @Entry var initialFocusClaimState: InitialFocusClaimState? = nil
}

private struct InitialFocusClaimProvider: ViewModifier {
  @State private var state = InitialFocusClaimState()

  func body(content: Content) -> some View {
    content.environment(\.initialFocusClaimState, state)
  }
}

private struct InitialFocusClaim: ViewModifier {
  @Environment(\.initialFocusClaimState) private var state
  @Environment(\.scenePhase) private var scenePhase
  @FocusState private var isFocused: Bool

  func body(content: Content) -> some View {
    if let state {
      content
        .focused($isFocused)
        .background(PresentationReadyAction(
          isEnabled: !state.hasClaimed && scenePhase == .active,
          requiresNavigationTop: true,
          contentFocusMatches: true,
          onContentFocus: { state.hasClaimed = true },
          action: { isFocused = true }
        ))
    } else {
      content
    }
  }
}
