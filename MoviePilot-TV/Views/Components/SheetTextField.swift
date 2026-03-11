import SwiftUI
import UIKit

/// 一个自定义 TextField，用于绕过 SwiftUI 在 tvOS 26.0-26.3 Sheet 中的渲染问题。
/// 底层使用 UITextField 以避免聚焦时的模糊/毛玻璃效果 Bug。
struct SheetTextField: View {
  let title: String
  let placeholder: String
  @Binding var text: String
  var keyboardType: UIKeyboardType = .default

  var body: some View {
    LabeledContent(title) {
      if SheetStyleFix.shouldApply {
        SheetTextFieldRepresentable(
          placeholder: placeholder,
          text: $text,
          keyboardType: keyboardType
        )
        .frame(height: 66)
      } else {
        TextField(placeholder, text: $text)
          .keyboardType(keyboardType)
      }
    }
  }
}

/// 自定义 UITextField，通过拦截系统添加的视觉效果视图
/// 来禁用 tvOS 系统的模糊/毛玻璃聚焦效果
///
/// **视图层级结构 (View Hierarchy):**
/// 1. **最顶层 (Top):** 文本输入光标和文字 (由 UITextField 自身处理)
/// 2. **中间层 (Middle):** 所有的自定义效果
///    - **Layer (self.layer):** 负责 "外发光/阴影" (Shadow) 和 "缩放动画" (Transform)
/// 3. **最底层 (Bottom):** `backgroundView` (我们手动添加的 UIView)
///    - **Background:** 负责 "背景颜色" (Color) 和 "圆角" (CornerRadius)
class NoBlurTextField: UITextField {

  private let backgroundView = UIView()

  override init(frame: CGRect) {
    super.init(frame: frame)
    setupBackgroundView()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    setupBackgroundView()
  }

  private func setupBackgroundView() {
    // 设置背景视图
    backgroundView.isUserInteractionEnabled = false

    // [样式修改] 圆角设置
    // 控制圆角的弯曲程度 (33 是高度 66 的一半，即全圆角/胶囊形)
    backgroundView.layer.cornerRadius = 33
    backgroundView.layer.cornerCurve = .continuous
    insertSubview(backgroundView, at: 0)

    // 初始样式
    applyUnfocusedStyle()
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    backgroundView.frame = bounds
    sendSubviewToBack(backgroundView)
  }

  // 拦截子视图添加以阻止系统模糊视图
  override func addSubview(_ view: UIView) {
    // 阻止 UIVisualEffectView 及相关的模糊视图
    if view is UIVisualEffectView {
      return
    }
    let className = String(describing: type(of: view))
    if className.contains("Backdrop") || className.contains("VisualEffect")
      || className.contains("_UITextFieldCanvasView")
    {
      return
    }
    super.addSubview(view)
  }

  override func didUpdateFocus(
    in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator
  ) {
    // 使用自定义动画曲线 easeOut(duration: 0.2)
    // 不使用 coordinator.addCoordinatedAnimations，因为我们要强制指定时间和曲线
    UIView.animate(
      withDuration: 0.2,
      delay: 0,
      options: .curveEaseOut,
      animations: {
        if self.isFocused {
          self.applyFocusedStyle()
        } else {
          self.applyUnfocusedStyle()
        }
      },
      completion: nil
    )
  }

  override var canBecomeFocused: Bool {
    return true
  }

  // MARK: - 聚焦样式 (当遥控器选中输入框时)
  func applyFocusedStyle() {
    backgroundColor = .clear
    backgroundView.backgroundColor = .white

    textColor = .black
    tintColor = .black

    // 阴影效果
    layer.shadowColor = UIColor.black.cgColor
    layer.shadowOffset = .init(width: 0, height: 5)
    layer.shadowRadius = 10
    layer.shadowOpacity = 0.6
    layer.masksToBounds = false

    // 缩放动画
    transform = CGAffineTransform(scaleX: 1.01, y: 1.01)
  }

  // MARK: - 非聚焦样式 (默认状态/失去焦点时)
  func applyUnfocusedStyle() {
    backgroundColor = .clear
    backgroundView.backgroundColor = UIColor.white.withAlphaComponent(0.2)

    textColor = .white
    tintColor = .white

    // 清除阴影
    layer.shadowOpacity = 0
    layer.masksToBounds = true

    // 恢复原始大小
    transform = .identity
  }

  // MARK: - 编辑样式 (当软键盘弹出/进入编辑模式时)
  func applyEditingStyle() {
    backgroundColor = .clear
    backgroundView.backgroundColor = UIColor.white.withAlphaComponent(0.35)

    textColor = UIColor.white.withAlphaComponent(0.5)
    tintColor = UIColor.white.withAlphaComponent(0.5)

    layer.shadowOpacity = 0
    layer.masksToBounds = true
  }
}

struct SheetTextFieldRepresentable: UIViewRepresentable {
  typealias UIViewType = NoBlurTextField

  let placeholder: String
  @Binding var text: String
  var keyboardType: UIKeyboardType

  func makeCoordinator() -> Coordinator {
    Coordinator(text: $text)
  }

  func makeUIView(context: UIViewRepresentableContext<SheetTextFieldRepresentable>)
    -> NoBlurTextField
  {
    let textField = NoBlurTextField()
    textField.delegate = context.coordinator
    textField.addTarget(
      context.coordinator,
      action: #selector(Coordinator.textFieldDidChange(_:)),
      for: .editingChanged
    )

    // 基础设置
    textField.placeholder = placeholder
    textField.text = text
    textField.keyboardType = keyboardType
    textField.returnKeyType = .done
    textField.textAlignment = .left
    textField.borderStyle = .none
    textField.font = UIFont.systemFont(ofSize: 30, weight: .medium)

    // 应用初始样式
    textField.applyUnfocusedStyle()

    return textField
  }

  func updateUIView(
    _ textField: NoBlurTextField,
    context: UIViewRepresentableContext<SheetTextFieldRepresentable>
  ) {
    // 只在非编辑状态下更新文本，避免干扰用户输入
    if !textField.isEditing && textField.text != text {
      textField.text = text
      // 强制刷新布局以确保文本正确显示
      textField.setNeedsLayout()
    }
    textField.placeholder = placeholder
    textField.keyboardType = keyboardType
  }

  class Coordinator: NSObject, UITextFieldDelegate {
    @Binding var text: String

    init(text: Binding<String>) {
      _text = text
    }

    @objc func textFieldDidChange(_ textField: UITextField) {
      text = textField.text ?? ""
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
      // 先同步文本值
      text = textField.text ?? ""
      // 延迟 resign 以避免与焦点系统冲突
      DispatchQueue.main.async {
        textField.resignFirstResponder()
      }
      return true
    }

    func textFieldDidBeginEditing(_ textField: UITextField) {
      guard let textField = textField as? NoBlurTextField else { return }
      // 动画过渡到编辑状态
      UIView.animate(withDuration: 0.2) {
        textField.applyEditingStyle()
      }
    }

    func textFieldDidEndEditing(_ textField: UITextField, reason: UITextField.DidEndEditingReason) {
      guard let noBlurTextField = textField as? NoBlurTextField else { return }

      // 同步最终文本值
      text = textField.text ?? ""

      // 延迟应用样式，等待焦点系统稳定
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak noBlurTextField] in
        guard let textField = noBlurTextField else { return }

        UIView.animate(withDuration: 0.2) {
          // 根据当前焦点状态决定应用哪种样式
          if textField.isFocused {
            textField.applyFocusedStyle()
          } else {
            textField.applyUnfocusedStyle()
          }
        }

        // 强制刷新布局以确保文本正确显示
        textField.setNeedsLayout()
        textField.layoutIfNeeded()
      }
    }
  }
}
