//
// 播放界面浮在画面上的控件共用的玻璃外观：工具栏按钮、面板标签、简介面板、面板里的按钮、画面上的操作按钮、
// 提示条、进度条底槽，以及剧照卡没有图时的占位。下面不压暗画面。
//
// 用哪一种 Liquid Glass、加不加色调，只在 `PlayerGlass.variant` / `PlayerGlass.tint` 改，所有控件跟着变。
// 系统只给两种玻璃，没有“强度”可调：
// - clear：最透明，但边缘折射很强（画面在边上明显弯曲）；画面亮时整块发白，上面的白字和图标看不清。
// - regular（现在用的）：把后面的画面模糊开，并按画面明暗自动调深浅，字在亮暗画面上都看得清，边缘也平和得多。
//   深色下它偏黑，所以再加 20% 的白色调，整体浅一些，白字仍看得清。调得越白越浅，但亮画面上白字的对比也越低。
// 「辅助功能」里的降低透明度、增强对比度会由系统自动改玻璃的样子，不用这里处理。
//
// Liquid Glass 从 tvOS 26 起才有，Apple TV HD 和第一代 Apple TV 4K 升到 tvOS 26 也没有；这些情况退回浅色半透明的模糊底，
// 形状、尺寸和各状态都一样，只是材质不同。
// 状态按 HIG 的 tvOS 聚焦规范：未聚焦是玻璃、白字；聚焦时放大，换成不透明白底黑字并加投影；
// 按下时回到原大小；选中但没聚焦（当前面板的标签）叠一层淡白；不可用时变淡。
//

import Foundation
import SwiftUI

enum PlayerGlass {

    enum Variant {
        case regular
        case clear
    }

    /// 所有玻璃用哪一种，见文件开头的说明。
    static let variant = Variant.regular
    /// 给玻璃加的色调；nil 为无色。用很淡的白色调浅、黑色调深，见文件开头的说明。
    static let tint: Color? = .white.opacity(0.2)

    @available(tvOS 26.0, *)
    static var glass: Glass {
        let base: Glass =
            switch variant {
            case .regular: .regular
            case .clear: .clear
            }
        return base.tint(tint)
    }

    /// 选中但没聚焦时叠的白色。
    static let selectedFillOpacity = 0.25
    static let disabledOpacity = 0.45
    static let focusedShadowOpacity = 0.35
    static let animation = Animation.easeOut(duration: 0.15)

    /// 这台设备能显示 Liquid Glass。
    nonisolated static let isLiquidGlassAvailable: Bool = {
        guard #available(tvOS 26.0, *) else { return false }

        var systemInfo = utsname()
        uname(&systemInfo)
        let model = withUnsafeBytes(of: systemInfo.machine) { buffer in
            String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
        }
        // Apple TV HD、第一代 Apple TV 4K 能装 tvOS 26，但没有 Liquid Glass（https://support.apple.com/en-us/106336 脚注 2）。
        return !["AppleTV5,3", "AppleTV6,2"].contains(model)
    }()
}

/// 玻璃底。
struct PlayerGlassBackground<S: InsettableShape>: View {

    let shape: S

    var body: some View {
        if #available(tvOS 26.0, *), PlayerGlass.isLiquidGlassAvailable {
            Color.clear
                .glassEffect(PlayerGlass.glass, in: shape)
        } else {
            shape
                .fill(Color.white.opacity(0.14))
                .background { shape.fill(.ultraThinMaterial) }
                .overlay { shape.strokeBorder(Color.white.opacity(0.22), lineWidth: 1) }
        }
    }
}

/// 屏幕底部「简介 / 章节 / 选集」标签和下面面板的尺寸与位置。
/// 面板里的图片圆角 + 内边距 = 外框圆角，两层圆角同心。
enum PlayerPanelLayout {

    /// 简介面板：内边距 20，图片圆角 20，外框圆角 40（同 Apple TV App 播放界面的简介面板）。
    static let padding: CGFloat = 20
    static let contentCornerRadius: CGFloat = 20
    static let cornerRadius: CGFloat = padding + contentCornerRadius
    /// 面板、卡片行和上面标签之间的距离。
    static let tabGap: CGFloat = 40
    /// 标签上方的留白：没打开面板时是标签和进度条下面那行时间的距离。
    static let tabTopInset: CGFloat = 20
    /// 标签一行的高度（玻璃胶囊按钮：body 字一行，上下各留 12）。
    static let tabHeight: CGFloat = 60
    /// 简介面板里海报的高度：标题两行、简介三行加信息行正好放得下，面板高度不随文字变。
    static let infoPosterHeight: CGFloat = 226
    static let infoPanelHeight: CGFloat = infoPosterHeight + padding * 2

    /// 没打开面板时标签区域露出的高度：标签底边落在底部安全区上。
    static func collapsedHeight(bottomInset: CGFloat) -> CGFloat {
        tabTopInset + tabHeight + bottomInset
    }

    /// 打开面板后标签区域的高度：几种面板里最高的简介面板底边落在底部安全区上，
    /// 章节、选集卡片行和其他面板与它顶边对齐。
    static func expandedHeight(bottomInset: CGFloat) -> CGFloat {
        tabTopInset + tabHeight + tabGap + infoPanelHeight + bottomInset
    }
}

/// 简介面板：内容四周留 `PlayerPanelLayout.padding`，下面垫一块圆角玻璃。
struct PlayerGlassPanel<Content: View>: View {

    @ViewBuilder
    let content: Content

    var body: some View {
        content
            .padding(PlayerPanelLayout.padding)
            .background {
                PlayerGlassBackground(
                    shape: RoundedRectangle(cornerRadius: PlayerPanelLayout.cornerRadius, style: .continuous)
                )
            }
    }
}

/// 画面上的玻璃控件：聚焦、选中、按下、不可用的外观都在这里，标签的大小和留白由调用方决定。
struct PlayerGlassControl<S: InsettableShape, Label: View>: View {

    @Environment(\.isFocused)
    private var isFocused
    @Environment(\.isEnabled)
    private var isEnabled
    @Environment(\.isSelected)
    private var isSelected
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    let shape: S
    let isPressed: Bool
    /// 聚焦时放大的倍数；宽按钮放大得少一些，免得压到旁边。
    var focusedScale: CGFloat = 1.1
    @ViewBuilder
    let label: Label

    private var isHighlighted: Bool {
        isEnabled && isFocused
    }

    private var scale: CGFloat {
        isHighlighted && !isPressed ? focusedScale : 1
    }

    private var whiteFillOpacity: Double {
        isHighlighted ? 1 : (isSelected && isEnabled ? PlayerGlass.selectedFillOpacity : 0)
    }

    var body: some View {
        label
            .foregroundStyle(isHighlighted ? Color.black : Color.white)
            .background {
                // 玻璃一直挂着，聚焦时在上面盖不透明白底；只改透明度，焦点移动时不重建玻璃。
                PlayerGlassBackground(shape: shape)
                    .overlay {
                        shape
                            .fill(Color.white)
                            .opacity(whiteFillOpacity)
                    }
            }
            .contentShape(shape)
            .scaleEffect(scale)
            .shadow(color: .black.opacity(isHighlighted ? PlayerGlass.focusedShadowOpacity : 0), radius: 14, y: 8)
            .opacity(isEnabled ? 1 : PlayerGlass.disabledOpacity)
            .animation(reduceMotion ? nil : PlayerGlass.animation, value: isFocused)
            .animation(reduceMotion ? nil : PlayerGlass.animation, value: isPressed)
            .animation(reduceMotion ? nil : PlayerGlass.animation, value: isSelected)
    }
}

/// 有文字的玻璃胶囊按钮：面板标签、「从头播放」、「跳过片头」、偏移调整的预设值等。
struct PlayerGlassCapsuleButtonStyle: ButtonStyle {

    func makeBody(configuration: Configuration) -> some View {
        PlayerGlassControl(shape: Capsule(), isPressed: configuration.isPressed, focusedScale: 1.06) {
            configuration.label
                .font(.body)
                .fontWeight(.semibold)
                .lineLimit(1)
                .symbolRenderingMode(.monochrome)
                .padding(.horizontal, 28)
                .padding(.vertical, 12)
                .frame(minHeight: ViewLayout.platformDefault.controlMinimumSize)
        }
    }
}

/// 只有图标的玻璃圆形按钮，尺寸同工具栏按钮。
struct PlayerGlassCircleButtonStyle: ButtonStyle {

    func makeBody(configuration: Configuration) -> some View {
        let size = ViewLayout.platformDefault.toolbarButtonSize

        PlayerGlassControl(shape: Circle(), isPressed: configuration.isPressed) {
            configuration.label
                .labelStyle(.iconOnly)
                .font(.system(size: ViewLayout.platformDefault.toolbarIconSize, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .frame(width: size, height: size)
        }
    }
}

extension ButtonStyle where Self == PlayerGlassCapsuleButtonStyle {

    static var playerGlass: PlayerGlassCapsuleButtonStyle {
        PlayerGlassCapsuleButtonStyle()
    }
}

extension ButtonStyle where Self == PlayerGlassCircleButtonStyle {

    static var playerGlassCircle: PlayerGlassCircleButtonStyle {
        PlayerGlassCircleButtonStyle()
    }
}
