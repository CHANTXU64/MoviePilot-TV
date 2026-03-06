import SwiftUI

enum SheetStyleFix {
  static var shouldApply: Bool {
    let version = ProcessInfo.processInfo.operatingSystemVersion
    // 用户请求的范围：26.0 到 26.x
    // return version.majorVersion == 26 && version.minorVersion <= 3
    return version.majorVersion >= 26
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
        Image(systemName: configuration.isOn ? "checkmark.circle.fill" : "circle")
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
