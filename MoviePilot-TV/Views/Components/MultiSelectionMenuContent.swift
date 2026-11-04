import SwiftUI

/// 多选的共用语义。
enum MultiSelection {
  /// 已选但不在可选项中的值（旧配置/已停用项）。
  nonisolated static func unavailableSelections<T, ID: Hashable>(
    in selected: Set<ID>,
    options: [T],
    id: KeyPath<T, ID>
  ) -> Set<ID> {
    selected.subtracting(options.map { $0[keyPath: id] })
  }
}

/// 多选系统菜单的内容：每个选项一行系统 `Toggle`，外加不可选分组和「清除不可用选择」。
///
/// SwiftUI 的 `Picker` 只有单选，系统菜单里的多选就是一组 `Toggle`。放在 `Menu { }` 里使用，
/// 并配合 `.menuActionDismissBehavior(.disabled)`：点一项立即生效、菜单不收起，选好按 Menu 键关闭。
///
/// `emptySelectionTitle` 在最上面放一项「不选」（如「全部」），没有选择时它打勾。系统菜单只在有
/// 打勾项时才留出对勾位置，始终有一项打勾，才不会在第一次勾选时整列右移。
struct MultiSelectionMenuContent<T, ID: Hashable, Header: View>: View {
  let options: [T]
  let id: KeyPath<T, ID>
  @Binding var selected: Set<ID>
  let label: (T) -> String
  var disabledOptions: Set<ID> = []
  var disabledOptionsTitle: String? = nil
  /// 最上面「不选」那一项的名称；nil 时不显示（调用方自己提供了等价项，如搜索站点的「默认」）。
  var emptySelectionTitle: String? = nil
  /// 有值时，可选项放进这个标题的分组。
  var sectionTitle: String? = nil
  /// 放在可选项前面的说明（如加载中、加载失败）。
  @ViewBuilder var header: () -> Header

  var body: some View {
    if let emptySelectionTitle {
      Section {
        Toggle(emptySelectionTitle, isOn: Binding(
          get: { selected.isEmpty },
          set: { if $0 { selected = [] } }
        ))
      }
    }

    if let sectionTitle {
      Section(sectionTitle) {
        header()
        rows(enabledOptions)
      }
    } else {
      header()
      rows(enabledOptions)
    }

    let disabledItems = options.filter { disabledOptions.contains($0[keyPath: id]) }
    if !disabledItems.isEmpty {
      Section(disabledOptionsTitle ?? "") {
        rows(disabledItems)
          .disabled(true)
      }
    }

    // 可选项为空（还没加载或加载失败）时无法判断哪些已失效，不提供清除，免得误删有效选择。
    let unavailableSelections = options.isEmpty
      ? []
      : MultiSelection.unavailableSelections(in: selected, options: options, id: id)
    if !unavailableSelections.isEmpty {
      Section {
        Button(role: .destructive) {
          selected.subtract(unavailableSelections)
        } label: {
          Text("清除不可用选择（\(unavailableSelections.count)）")
        }
      }
    }
  }

  private var enabledOptions: [T] {
    options.filter { !disabledOptions.contains($0[keyPath: id]) }
  }

  private func rows(_ items: [T]) -> some View {
    ForEach(items, id: id) { item in
      let itemID = item[keyPath: id]
      Toggle(label(item), isOn: Binding(
        get: { selected.contains(itemID) },
        set: { isSelected in
          if isSelected { selected.insert(itemID) }
          else { selected.remove(itemID) }
        }
      ))
    }
  }
}

extension MultiSelectionMenuContent where Header == EmptyView {
  init(
    options: [T],
    id: KeyPath<T, ID>,
    selected: Binding<Set<ID>>,
    label: @escaping (T) -> String,
    disabledOptions: Set<ID> = [],
    disabledOptionsTitle: String? = nil,
    emptySelectionTitle: String? = nil
  ) {
    self.init(
      options: options, id: id, selected: selected, label: label,
      disabledOptions: disabledOptions, disabledOptionsTitle: disabledOptionsTitle,
      emptySelectionTitle: emptySelectionTitle,
      header: { EmptyView() }
    )
  }
}

/// 页面上的多选筛选菜单：菜单里勾选只改草稿，菜单关闭、焦点回到按钮时才提交一次。
///
/// 菜单打开时焦点移进菜单、按钮失去焦点，关闭后焦点回到按钮（tvOS 18.5 / 26.5 / 27 实测一致）。
/// 用在提交代价高的入口（重新请求、整页重新过滤），避免每勾一项就刷新一次。
/// 兜底：万一焦点没在按钮上停留就直接移到同页其他控件，只要 UIKit 报告焦点回到了按钮所在
/// 页面控制器的视图里，也提交；菜单项不在其中，菜单开着时不会误提交。
/// 菜单开着时页面被移除，也在消失时提交。
struct DeferredMultiSelectionMenu<T, ID: Hashable, ButtonLabel: View>: View {
  let options: [T]
  let id: KeyPath<T, ID>
  /// 已提交的选择；菜单里显示的是草稿。
  let selected: Set<ID>
  let label: (T) -> String
  var disabledOptions: Set<ID> = []
  var disabledOptionsTitle: String? = nil
  var emptySelectionTitle: String? = nil
  let onCommit: (Set<ID>) -> Void
  @ViewBuilder let buttonLabel: () -> ButtonLabel

  @State private var draft: Set<ID>?
  @FocusState private var isFocused: Bool

  var body: some View {
    Menu {
      MultiSelectionMenuContent(
        options: options, id: id,
        selected: Binding(get: { draft ?? selected }, set: { draft = $0 }),
        label: label,
        disabledOptions: disabledOptions, disabledOptionsTitle: disabledOptionsTitle,
        emptySelectionTitle: emptySelectionTitle
      )
    } label: {
      buttonLabel()
    }
    .menuActionDismissBehavior(.disabled)
    .focused($isFocused)
    .onChange(of: isFocused) { _, focused in
      if focused { commit() }
    }
    .background(MenuFocusReturnObserver(onFocusReturned: commit))
    .onDisappear { commit() }
  }

  private func commit() {
    guard let pending = draft else { return }
    draft = nil
    if pending != selected { onCommit(pending) }
  }
}

/// 焦点回到自己所在的视图树时回调，用来发现「菜单已关闭」。
///
/// 菜单打开时焦点在系统菜单项上，菜单项不在页面控制器的视图里；关闭后焦点回到页面
/// （按钮本身或同页其他控件），就落在页面控制器的视图里（tvOS 18.5 / 27 页面与 Sheet 内实测一致）。
private struct MenuFocusReturnObserver: UIViewRepresentable {
  let onFocusReturned: () -> Void

  func makeUIView(context _: UIViewRepresentableContext<MenuFocusReturnObserver>) -> ObserverView {
    ObserverView()
  }

  func updateUIView(_ view: ObserverView, context _: UIViewRepresentableContext<MenuFocusReturnObserver>) {
    view.onFocusReturned = onFocusReturned
  }

  final class ObserverView: UIView {
    var onFocusReturned: (() -> Void)?

    override init(frame: CGRect) {
      super.init(frame: frame)
      isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didMoveToWindow() {
      super.didMoveToWindow()
      let center = NotificationCenter.default
      center.removeObserver(self, name: UIFocusSystem.didUpdateNotification, object: nil)
      guard window != nil else { return }
      center.addObserver(
        self, selector: #selector(focusDidUpdate(_:)),
        name: UIFocusSystem.didUpdateNotification, object: nil
      )
    }

    @objc private func focusDidUpdate(_ notification: Notification) {
      guard
        let context = notification.userInfo?[UIFocusSystem.focusUpdateContextUserInfoKey] as? UIFocusUpdateContext,
        let next = context.nextFocusedView,
        let pageView = owningViewController?.view,
        next.isDescendant(of: pageView)
      else { return }
      onFocusReturned?()
    }

    /// 承载这个按钮的页面控制器（沿响应链向上找）。同一页面的其他控件都在它的视图里，
    /// 系统菜单项不在（另挂在窗口上）。
    private var owningViewController: UIViewController? {
      var responder: UIResponder? = next
      while let current = responder {
        if let controller = current as? UIViewController { return controller }
        responder = current.next
      }
      return nil
    }
  }
}
