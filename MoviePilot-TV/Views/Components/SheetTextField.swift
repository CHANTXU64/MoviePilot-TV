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
    LabeledContent {
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
    } label: {
      // 标题不折行（如「TheMovieDb ID」），空间不够时由输入框让出宽度。
      Text(title)
        .lineLimit(1)
        .fixedSize()
    }
  }
}

/// 设置面板里占满一整行的输入框，不在框外放标签。
/// 没填时框内的占位文字就是项名（tvOS 全屏键盘也把它当标题）；
/// 填了以后项名用灰字留在框内左侧、内容靠右，和菜单行一样一眼能看出是哪一项。
/// 项名和内容在一行里放不下时（如很长的识别词）只显示内容，两段文字不会叠在一起。
struct SheetInlineTextField: View {
  let title: String
  @Binding var text: String
  var keyboardType: UIKeyboardType = .default

  @State private var fieldWidth: CGFloat = 0

  /// 与系统输入框内文字的左右缩进一致，项名和占位文字在同一位置。
  static let horizontalInset: CGFloat = 30
  /// 项名和内容之间至少留出的距离。
  static let titleGap: CGFloat = 24

  /// 框内能否同时放下项名和内容：左右缩进 + 项名 + 间距 + 内容不超过框宽。
  /// 按实际字体量宽度，不按字数估算；没填内容时不显示项名（占位文字就是项名）。
  static func showsTitle(title: String, text: String, font: UIFont, fieldWidth: CGFloat) -> Bool {
    guard !text.isEmpty, fieldWidth > 0 else { return false }
    func width(_ string: String) -> CGFloat {
      ceil((string as NSString).size(withAttributes: [.font: font]).width)
    }
    return horizontalInset * 2 + width(title) + titleGap + width(text) <= fieldWidth
  }

  private var showsTitle: Bool {
    // 系统输入框和框外的 Text 一样用 body 字号。
    Self.showsTitle(
      title: title, text: text, font: .preferredFont(forTextStyle: .body), fieldWidth: fieldWidth)
  }

  var body: some View {
    if SheetStyleFix.shouldApply {
      SheetTextFieldRepresentable(
        placeholder: title,
        text: $text,
        keyboardType: keyboardType,
        inlineTitle: title
      )
      .frame(height: 66)
    } else {
      TextField(title, text: $text)
        .keyboardType(keyboardType)
        .multilineTextAlignment(text.isEmpty ? .leading : .trailing)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { fieldWidth = $0 }
        .overlay(alignment: .leading) {
          if showsTitle {
            // 框聚焦时变白、不聚焦时是深色，用中灰在两种底色上都看得清。
            Text(title)
              .foregroundStyle(Color.gray)
              .lineLimit(1)
              .padding(.leading, Self.horizontalInset)
              .allowsHitTesting(false)
          }
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
  // 显式非隔离析构，避开 tvOS 18 的隔离析构回部署崩溃。
  nonisolated deinit {}


  private let backgroundView = UIView()
  private let inlineTitleLabel = UILabel()

  /// 设置面板的整行输入框：填了内容后，项名用灰字显示在框内左侧，内容靠右。
  var inlineTitle: String? {
    didSet { refreshInlineTitle() }
  }

  private var showsInlineTitle: Bool {
    guard let inlineTitle, let font else { return false }
    return SheetInlineTextField.showsTitle(
      title: inlineTitle, text: text ?? "", font: font, fieldWidth: bounds.width)
  }

  /// 整行输入框的文字区：左右留出缩进；显示项名时从项名右边开始，内容不会压到项名上。
  /// 普通输入框（没有项名）保持系统默认。
  private func inlineTextRect(forBounds bounds: CGRect) -> CGRect? {
    guard inlineTitle != nil else { return nil }
    let inset = SheetInlineTextField.horizontalInset
    var leading = inset
    if showsInlineTitle {
      leading += ceil(inlineTitleLabel.intrinsicContentSize.width) + SheetInlineTextField.titleGap
    }
    return CGRect(
      x: bounds.minX + leading, y: bounds.minY,
      width: max(0, bounds.width - leading - inset), height: bounds.height)
  }

  override func textRect(forBounds bounds: CGRect) -> CGRect {
    inlineTextRect(forBounds: bounds) ?? super.textRect(forBounds: bounds)
  }

  override func editingRect(forBounds bounds: CGRect) -> CGRect {
    inlineTextRect(forBounds: bounds) ?? super.editingRect(forBounds: bounds)
  }

  override func placeholderRect(forBounds bounds: CGRect) -> CGRect {
    inlineTextRect(forBounds: bounds) ?? super.placeholderRect(forBounds: bounds)
  }

  func refreshInlineTitle() {
    inlineTitleLabel.text = inlineTitle
    inlineTitleLabel.font = font
    let showsTitle = showsInlineTitle
    if inlineTitleLabel.isHidden == showsTitle {
      inlineTitleLabel.isHidden = !showsTitle
      setNeedsLayout()
    }
    if inlineTitle != nil {
      let alignment: NSTextAlignment = (text ?? "").isEmpty ? .left : .right
      if textAlignment != alignment { textAlignment = alignment }
    }
  }

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

    inlineTitleLabel.isUserInteractionEnabled = false
    inlineTitleLabel.isHidden = true
    addSubview(inlineTitleLabel)

    // 初始样式
    applyUnfocusedStyle()
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    backgroundView.frame = bounds
    sendSubviewToBack(backgroundView)
    // 宽度变化后重新判断放不放得下项名。
    refreshInlineTitle()
    inlineTitleLabel.frame = CGRect(
      x: SheetInlineTextField.horizontalInset, y: 0,
      width: ceil(inlineTitleLabel.intrinsicContentSize.width), height: bounds.height)
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
    inlineTitleLabel.textColor = .gray

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
    inlineTitleLabel.textColor = .gray

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
  var inlineTitle: String? = nil

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
    textField.inlineTitle = inlineTitle

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
    if textField.inlineTitle != inlineTitle {
      textField.inlineTitle = inlineTitle
    } else {
      textField.refreshInlineTitle()
    }
  }

  class Coordinator: NSObject, UITextFieldDelegate {
    // 显式非隔离析构，避开 tvOS 18 的隔离析构回部署崩溃。
    nonisolated deinit {}

    @Binding var text: String

    init(text: Binding<String>) {
      _text = text
    }

    @objc func textFieldDidChange(_ textField: UITextField) {
      text = textField.text ?? ""
      (textField as? NoBlurTextField)?.refreshInlineTitle()
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
