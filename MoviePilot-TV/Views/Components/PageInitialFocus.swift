import SwiftUI

extension View {
  /// 页面第一次出现时把焦点写到这个控件上，焦点进了本页（含用户主动移动）就停，之后不再抢焦点。
  ///
  /// 从上一页的菜单项直接打开本页时，系统菜单收起后要把焦点还给已被本页盖住的菜单按钮，焦点就落到
  /// Tab 栏上（这时按 Menu 会退出 App）。和 Top Shelf 直达详情页一样，等本页呈现完、在栈顶且没有转场
  /// 或菜单盖着时再写（见 `PresentationReadyAction`）。焦点在 Tab 栏上时只能写到具体控件，写给整页容器不生效。
  func claimsInitialFocus(_ isEnabled: Bool = true) -> some View {
    modifier(InitialFocusClaim(isEnabled: isEnabled))
  }
}

extension EnvironmentValues {
  /// 结果页从别的页面打开时为 true：共用的加载视图（搜索页里也用）据此决定「取消」要不要认领首个焦点。
  @Entry var claimsInitialLoadingFocus = false
}

private struct InitialFocusClaim: ViewModifier {
  let isEnabled: Bool
  @FocusState private var isFocused: Bool
  @State private var hasClaimed = false
  @Environment(\.scenePhase) private var scenePhase

  func body(content: Content) -> some View {
    content
      .focused($isFocused)
      .background(PresentationReadyAction(
        isEnabled: isEnabled && !hasClaimed && scenePhase == .active,
        requiresNavigationTop: true,
        contentFocusMatches: true,
        onContentFocus: { hasClaimed = true },
        action: { isFocused = true }
      ))
  }
}
