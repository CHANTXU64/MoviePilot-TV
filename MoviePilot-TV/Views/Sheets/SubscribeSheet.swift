import SwiftUI

struct SubscribeSheet: View {
  @Environment(\.dismiss) var dismiss
  @Environment(\.isPresented) private var isPresented
  @StateObject private var viewModel: SubscribeSheetViewModel
  @State private var hasAppeared = false
  @State private var costlyToken = CostlyModalToken()
  @State private var isSaveAttemptInFlight = false
  @State private var showingIdentityResetConfirmation = false

  var onSave: ((Subscribe) -> Void)?

  init(
    subscribe: Subscribe,
    isNewSubscription: Bool = false,
    onSave: ((Subscribe) -> Void)? = nil
  ) {
    _viewModel = StateObject(
      wrappedValue: SubscribeSheetViewModel(
        subscribe: subscribe,
        isNewSubscription: isNewSubscription
      ))
    self.onSave = onSave
  }

  init(
    subscribe: Subscribe,
    isNewSubscription: Bool = false,
    onSave: @escaping () -> Void
  ) {
    _viewModel = StateObject(
      wrappedValue: SubscribeSheetViewModel(
        subscribe: subscribe,
        isNewSubscription: isNewSubscription
      ))
    self.onSave = { _ in onSave() }
  }

  /// 新增和编辑都用 `SubscribePanel`：新增先是快速面板，编辑直接是大面板。
  var body: some View {
    SubscribePanel(
      viewModel: viewModel,
      isSaving: isSaveAttemptInFlight,
      onSubscribe: attemptSave
    )
    .alert(
      SubscribeIdentityResetConfirmation.title,
      isPresented: $showingIdentityResetConfirmation
    ) {
      Button(SubscribeIdentityResetConfirmation.cancelButtonTitle, role: .cancel) {
        showingIdentityResetConfirmation = false
      }
      Button(SubscribeIdentityResetConfirmation.confirmButtonTitle, role: .destructive) {
        showingIdentityResetConfirmation = false
        performSave()
      }
    } message: {
      Text(SubscribeIdentityResetConfirmation.message)
    }
    .episodeTrialNotice(
      isPresented: Binding(
        get: { viewModel.isHeldByEpisodeTrial },
        set: { isPresented in
          guard !isPresented, viewModel.isHeldByEpisodeTrial else { return }
          viewModel.acknowledgeEpisodeTrialHold()
          dismiss()
        }
      ),
      context: .subscribe, isCancelling: viewModel.isHeldTrialCancelling, canCancel: viewModel.canCancelEpisodeTrial
    ) {
      viewModel.cancelEpisodeTrialAndContinue()
    }
    .onAppear {
      guard !hasAppeared else { return }
      hasAppeared = true
      Task {
        await viewModel.loadData()
      }
    }
    .cancelOnExternalNavigation()
    // 用 isPresented 注册贵弹窗令牌：退后台不变；令牌由 @State 持有，视图销毁即释放、
    // 登记自动失效，即使注销回调未触发也不残留。
    .onChange(of: isPresented, initial: true) { _, presented in
      if presented {
        CostlyModalPresentation.register(costlyToken)
      } else {
        CostlyModalPresentation.unregister(costlyToken)
      }
    }
    .onDisappear {
      let wasSaving = viewModel.isSaving
      Task {
        await viewModel.cancel(wasSavingOnDismiss: wasSaving)
      }
    }
  }

  private func attemptSave() {
    guard !isSaveAttemptInFlight else { return }
    if viewModel.willResetSubscriptionProgressOnSave {
      showingIdentityResetConfirmation = true
      return
    }
    performSave()
  }

  private func performSave() {
    guard !isSaveAttemptInFlight else { return }
    isSaveAttemptInFlight = true
    Task {
      if await viewModel.save() {
        // 保存后只补做启用、搜索时没有写入，不再回写缓存。
        if viewModel.didWriteInLastSave {
          onSave?(viewModel.subscribe)
        }
        if viewModel.errorMessage == nil {
          dismiss()
          return
        }
      }
      isSaveAttemptInFlight = false
    }
  }
}
