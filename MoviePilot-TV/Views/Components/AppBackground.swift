import SwiftUI

/// 全 App 共用的页面底色：仿 Apple TV App，接近黑的深灰底略带蓝，
/// 中部有一团不规则的柔和光晕（主光偏左上、次光偏右下），四角渐暗。
/// 播放器仍保持纯黑，不使用这里的颜色。
struct AppBackground: View {
  /// 主光晕最亮处。
  static let highlight = Color(red: 0.153, green: 0.173, blue: 0.208)  // #272C35
  /// 次光晕。
  static let glow = Color(red: 0.125, green: 0.141, blue: 0.169)  // #20242B
  /// 光晕向外过渡的中间色。
  static let mid = Color(red: 0.094, green: 0.102, blue: 0.122)  // #181A1F
  /// 靠边的暗色。
  static let dark = Color(red: 0.067, green: 0.075, blue: 0.086)  // #111316
  /// 四角最暗处。
  static let edge = Color(red: 0.043, green: 0.047, blue: 0.055)  // #0B0C0E

  var body: some View {
    // 4×4 网格：边上的点只沿边移动以铺满画面，内部点错开摆放，让光晕成不规则的形状。
    MeshGradient(
      width: 4,
      height: 4,
      points: [
        [0, 0], [0.30, 0], [0.70, 0], [1, 0],
        [0, 0.38], [0.36, 0.30], [0.68, 0.40], [1, 0.30],
        [0, 0.72], [0.28, 0.68], [0.74, 0.64], [1, 0.70],
        [0, 1], [0.40, 1], [0.66, 1], [1, 1],
      ],
      colors: [
        Self.edge, Self.dark, Self.dark, Self.edge,
        Self.mid, Self.highlight, Self.glow, Self.dark,
        Self.dark, Self.mid, Self.glow, Self.mid,
        Self.edge, Self.edge, Self.dark, Self.edge,
      ]
    )
    .ignoresSafeArea()
    .accessibilityHidden(true)
  }
}
