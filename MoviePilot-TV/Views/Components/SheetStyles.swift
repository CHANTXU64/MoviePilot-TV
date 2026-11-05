import SwiftUI

enum SheetStyleFix {
  static var shouldApply: Bool {
    let version = ProcessInfo.processInfo.operatingSystemVersion
    // 有Bug的版本：26.0 到 26.3
    return version.majorVersion == 26 && version.minorVersion <= 3
  }
}

struct SheetActionButton: View {
  let title: String
  /// 主操作的图标（如下载），只在非加载状态显示。
  var systemImage: String? = nil
  let loadingTitle: String
  let isLoading: Bool
  var isDisabled = false
  /// 需要默认聚焦或由外部控制焦点时传入。
  var focus: FocusState<Bool>.Binding? = nil
  let action: () -> Void

  @FocusState private var ownFocus: Bool

  /// 系统转圈图标约 40pt，同字号的图标约 34pt。
  static let spinnerScale: CGFloat = 0.85

  var body: some View {
    Button(action: {
      // 加载中保持按钮可聚焦：tvOS 上聚焦元素一旦被 disabled，
      // 焦点引擎会把焦点移走，ScrollView 随即滚回顶部（“保存后自动上滑”）。
      // 这里只忽略点击，不让焦点状态发生变化。
      guard !isLoading else { return }
      action()
    }) {
      HStack(spacing: 8) {
        if isLoading || systemImage != nil {
          // 图标位的尺寸始终由同字号的图标决定：系统转圈图标（40pt）比一行文字高，
          // 直接放进来会把按钮撑高，加载结束又缩回。转圈图标叠在上面、缩到和图标一样大。
          Image(systemName: systemImage ?? AppSymbol.unselected)
            .opacity(isLoading ? 0 : 1)
            .overlay {
              if isLoading {
                ProgressView()
                  .scaleEffect(Self.spinnerScale)
              }
            }
        }
        Text(isLoading ? loadingTitle : title)
      }
      .frame(maxWidth: .infinity)
    }
    .disabled(isDisabled)
    .focused(focus ?? $ownFocus)
  }
}

// 复用用户的按钮样式
struct SheetButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    CapsuleFocusBody(configuration: configuration)
  }

  private struct CapsuleFocusBody: View {
    let configuration: Configuration
    @Environment(\.isFocused) var isFocused

    var body: some View {
      configuration.label
        .foregroundStyle(isFocused ? .black : .white)
        .padding()
        .background(
          Capsule()
            .fill(isFocused ? Color.white : Color.white.opacity(0.2))
            .shadow(
              color: isFocused
                ? (configuration.isPressed ? .clear : Color.black.opacity(0.25)) : .clear,
              radius: 10, x: 0, y: 5)
        )
        .scaleEffect(isFocused ? (configuration.isPressed ? 1.0 : 1.01) : 1.0)
        .animation(.easeOut(duration: 0.2), value: isFocused)
        .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
  }
}

// 复用用户的开关样式
struct SheetToggleStyle: ToggleStyle {
  func makeBody(configuration: Configuration) -> some View {
    Button {
      configuration.isOn.toggle()
    } label: {
      HStack {
        configuration.label
        Spacer()
        Image(systemName: configuration.isOn ? AppSymbol.selected : AppSymbol.unselected)
      }
      .padding(.horizontal)
    }
    .buttonStyle(SheetToggleButtonStyle(isOn: configuration.isOn))
  }

  // 开关的内部按钮样式
  private struct SheetToggleButtonStyle: ButtonStyle {
    let isOn: Bool

    func makeBody(configuration: Configuration) -> some View {
      SheetToggleButtonBody(configuration: configuration, isOn: isOn)
    }

    private struct SheetToggleButtonBody: View {
      let configuration: Configuration
      let isOn: Bool
      @Environment(\.isFocused) var isFocused

      var body: some View {
        configuration.label
          .foregroundStyle(isFocused ? .black : .white)
          .tint(isOn ? .green : (isFocused ? .black.opacity(0.6) : .white.opacity(0.6)))
          .padding()
          .background(
            Capsule()
              .fill(isFocused ? Color.white : Color.white.opacity(0.2))
              .shadow(
                color: isFocused
                  ? (configuration.isPressed ? .clear : Color.black.opacity(0.25)) : .clear,
                radius: 10, x: 0, y: 5)
          )
          .scaleEffect(isFocused ? (configuration.isPressed ? 1.0 : 1.01) : 1.0)
          .animation(.easeOut(duration: 0.2), value: isFocused)
          .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
      }
    }
  }
}

// 用于对容器视图条件性应用样式的修饰器
struct SheetContainerStyleModifier: ViewModifier {
  func body(content: Content) -> some View {
    if SheetStyleFix.shouldApply {
      content
        .buttonStyle(SheetButtonStyle())
        .toggleStyle(SheetToggleStyle())
    } else {
      content
    }
  }
}

extension View {
  /// 将按钮样式应用于容器（如 Form、VStack 等）
  func applySheetStyles() -> some View {
    self.modifier(SheetContainerStyleModifier())
  }
}
