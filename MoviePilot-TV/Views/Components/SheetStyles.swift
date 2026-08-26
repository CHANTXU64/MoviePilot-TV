import SwiftUI

enum SheetStyleFix {
  static var shouldApply: Bool {
    let version = ProcessInfo.processInfo.operatingSystemVersion
    // 有Bug的版本：26.0 到 26.3
    return version.majorVersion == 26 && version.minorVersion <= 3
  }
}

struct SheetFeedbackView: View {
  let message: String
  var actionTitle: String?
  var action: (() -> Void)?

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label(message, systemImage: "exclamationmark.circle.fill")
        .font(.callout)
        .foregroundStyle(.orange)
        .lineLimit(3)
        .minimumScaleFactor(0.75)

      if let actionTitle, let action {
        Button(actionTitle, action: action)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal)
  }
}

struct SheetActionButton: View {
  let title: String
  let loadingTitle: String
  let isLoading: Bool
  var isDisabled = false
  var feedbackMessage: String?
  let action: () -> Void

  var body: some View {
    VStack(spacing: 10) {
      Button(action: {
        // 加载中保持按钮可聚焦：tvOS 上聚焦元素一旦被 disabled，
        // 焦点引擎会把焦点移走，ScrollView 随即滚回顶部（“保存后自动上滑”）。
        // 这里只忽略点击，不让焦点状态发生变化。
        guard !isLoading else { return }
        action()
      }) {
        HStack(spacing: 8) {
          if isLoading {
            ProgressView()
          }
          Text(isLoading ? loadingTitle : title)
        }
        .frame(maxWidth: .infinity)
      }
      .disabled(isDisabled)

      if let feedbackMessage {
        SheetFeedbackView(message: feedbackMessage)
      }
    }
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
