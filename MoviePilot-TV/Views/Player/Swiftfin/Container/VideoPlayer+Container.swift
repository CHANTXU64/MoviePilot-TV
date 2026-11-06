//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//
// 本文件改自 Swiftfin：Shared/Views/VideoPlayer/Container/VideoPlayer+Container.swift
// Modifications for MoviePilot-TV are also licensed under MPL-2.0.
//
// 修改：
// - 删去 `#if os(iOS)` 分支（iOS 手势、缩放、触感反馈）。
// - `PlatformViewControllerRepresentable` / `HostingController` 来自第三方 Engine 包：前者换成 `UIViewControllerRepresentable`，
//   后者用 MoviePilot-TV 的同名最小替身（`UIHostingController` 子类）；工程里已有名为 `Context` 的模型类型，
//   representable 的上下文写成 `UIViewControllerRepresentableContext<Self>`。
// - 托管控制器根视图的环境注入移进 `HostedEnvironment` 视图的 `body`（行为相同；原写法在 lazy 初始化闭包里产生 Swift 6 隔离一致性警告）。
// - `updateProperties()` 是 tvOS 26 的 UIKit 观察回调，部署到 tvOS 18 改用 `ObservationToken` 在可见元素变化时同步补充面板的交互开关。
// - 日志改用工程的 `Logger`；关闭确认（Swiftfin 设置项 `confirmClose`，默认关）换成常量 `VideoPlayerDefaults.confirmClose`。
// - MoviePilot-TV 的 mpv 播放不提供画中画，收尾时不再判断 PiP，直接 `mediaSession.stop()`。
// 补显式非隔离析构 `nonisolated deinit`，避开 tvOS 18 的隔离析构回部署崩溃。
//

import SwiftUI
import UIKit

// TODO: pause when center tapped when overlay dismissed
//       - can be done entirely on playback controls layer
// TODO: account for gesture state active when item changes

extension VideoPlayer {

    struct Container<Player: View, PlaybackControls: View>: UIViewControllerRepresentable {

        private let viewState: ViewState
        private let mediaSession: MediaSession
        private let videoSize: () -> CGSize
        private let player: (VideoLayout) -> Player
        private let playbackControls: PlaybackControls

        init(
            viewState: ViewState,
            mediaSession: MediaSession,
            videoSize: @escaping () -> CGSize,
            @ViewBuilder player: @escaping (VideoLayout) -> Player,
            @ViewBuilder playbackControls: @escaping () -> PlaybackControls
        ) {
            self.viewState = viewState
            self.mediaSession = mediaSession
            self.videoSize = videoSize
            self.player = player
            self.playbackControls = playbackControls()
        }

        func makeUIViewController(context: UIViewControllerRepresentableContext<Self>) -> UIContainerViewController {
            let playerView = { (videoLayout: VideoLayout) in
                player(videoLayout)
                    .eraseToAnyView()
            }

            let playbackControlsView = playbackControls
                .eraseToAnyView()

            return UIContainerViewController(
                viewState: viewState,
                mediaSession: mediaSession,
                videoSize: videoSize,
                player: playerView,
                playbackControls: playbackControlsView
            )
        }

        static func dismantleUIViewController(_ controller: UIContainerViewController, coordinator: ()) {
            // A surface can be rebuilt or handed to PiP without ending its media session.
            controller.detachSurface()
        }

        func updateUIViewController(
            _ uiViewController: UIContainerViewController,
            context: UIViewControllerRepresentableContext<Self>
        ) {}
    }

    // MARK: - UIContainerViewController

    class UIContainerViewController: UIViewController {

        // 显式非隔离析构，避开 tvOS 18 的隔离析构回部署崩溃。
        nonisolated deinit {}

        typealias ViewState = VideoPlayer.ViewState

        private var viewLayout: ViewLayout {
            ViewLayout(size: view.bounds.size, traits: traitCollection)
        }

        private struct LayoutEnvironment: ViewModifier {

            @Environment(ViewState.self)
            private var viewState

            func body(content: Content) -> some View {
                content
                    .layoutContainer(size: viewState.layoutSize)
            }
        }

        /// 注入播放器环境（原版在托管控制器的根视图上链式注入）。`mediaSession` 为 nil 时与原版一样不注入。
        private struct HostedEnvironment<Content: View>: View {

            let viewState: ViewState
            let mediaSession: MediaSession?
            let content: Content

            var body: some View {
                if let mediaSession {
                    content
                        .modifier(LayoutEnvironment())
                        .environment(viewState)
                        .environmentObject(viewState.focusCoordinator)
                        .environment(mediaSession)
                } else {
                    content
                        .modifier(LayoutEnvironment())
                        .environment(viewState)
                        .environmentObject(viewState.focusCoordinator)
                }
            }
        }

        // MARK: - Views

        private struct PlayerContainerView: View {

            @Environment(ViewState.self)
            private var viewState

            let player: (VideoLayout) -> AnyView
            let videoSize: () -> CGSize

            private var shouldPresentDimOverlay: Bool {
                viewState.visibleElements.contains(.dimming)
            }

            var body: some View {
                VideoViewport(videoSize: videoSize) { videoLayout in
                    player(videoLayout)
                }
                .overlay {
                    Group {
                        if viewState.isPresentingFullScreenSupplement {
                            Color.black.opacity(0.8)
                        } else {
                            EasedGradient(
                                colors: [.clear, .black],
                                startPoint: .center,
                                endPoint: .bottom
                            )
                        }
                    }
                    .isVisible(shouldPresentDimOverlay)
                }
                .allowsHitTesting(false)
            }
        }

        private struct PlaybackControlsContainerView: View {

            @Environment(ViewState.self)
            private var viewState

            let playbackControls: AnyView

            private var panGestureDirection: Direction {
                if viewState.canPanZoom {
                    .all
                } else {
                    if viewState.isPresentingSupplement {
                        .vertical
                    } else {
                        if viewState.isPresentingControls {
                            if viewState.supplements.isEmpty {
                                []
                            } else {
                                Direction.up
                            }
                        } else {
                            .allButDown
                        }
                    }
                }
            }

            var body: some View {
                Group {
                    OverlayToastView(proxy: viewState.toastProxy) { playbackControls }
                }
            }
        }


        private lazy var initialHitBlockView: UIView = {
            let view = UIView(frame: .zero)
            view.translatesAutoresizingMaskIntoConstraints = false

            return view
        }()

        private lazy var playerViewController: HostingController<AnyView> = {
            let controller = HostingController(
                content: HostedEnvironment(viewState: viewState, mediaSession: mediaSession, content: PlayerContainerView(player: player, videoSize: videoSize))
                    .eraseToAnyView()
            )

            controller.disableSafeArea = true
            controller.automaticallyAllowUIKitAnimationsForNextUpdate = true
            controller.view.translatesAutoresizingMaskIntoConstraints = false

            return controller
        }()

        private lazy var playbackControlsViewController: HostingController<AnyView> = {
            let controller = HostingController(
                content: HostedEnvironment(viewState: viewState, mediaSession: mediaSession, content: PlaybackControlsContainerView(playbackControls: playbackControls))
                    .eraseToAnyView()
            )

            controller.disableSafeArea = true
            controller.automaticallyAllowUIKitAnimationsForNextUpdate = true
            controller.view.translatesAutoresizingMaskIntoConstraints = false

            return controller
        }()

        private lazy var supplementContainerViewController: HostingController<AnyView> = {
            let content = HostedEnvironment(viewState: viewState, mediaSession: mediaSession, content: SupplementContainerView())
                .eraseToAnyView()

            let controller = HostingController(content: content)
            controller.disableSafeArea = true
            controller.automaticallyAllowUIKitAnimationsForNextUpdate = true
            controller.view.translatesAutoresizingMaskIntoConstraints = false

            return controller
        }()

        private lazy var overlayActionsViewController: HostingController<AnyView> = {
            let controller = HostingController(
                content: HostedEnvironment(viewState: viewState, mediaSession: nil, content: OverlayActions())
                    .eraseToAnyView()
            )

            controller.disableSafeArea = true
            controller.sizingOptions = .intrinsicContentSize
            controller.view.translatesAutoresizingMaskIntoConstraints = false

            return controller
        }()


        private var playerView: UIView {
            playerViewController.view
        }

        func playerLocation(fromControls point: CGPoint) -> CGPoint {
            playerView.convert(point, from: playbackControlsView)
        }

        private var playbackControlsView: UIView {
            playbackControlsViewController.view
        }

        private var supplementContainerView: UIView {
            supplementContainerViewController.view
        }

        private var overlayActionsView: UIView {
            overlayActionsViewController.view
        }


        // MARK: - Constants

        private var availableSupplementHeight: CGFloat {
            max(0, view.bounds.height - view.safeAreaInsets.top)
        }

        private func supplementContainerOffset(
            isCompact: Bool? = nil
        ) -> CGFloat {
            let isCompact = isCompact ?? viewState.isCompact
            let availableHeight = availableSupplementHeight

            if !isCompact, viewState.selectedSupplement?.presentationStyle == .expanded {
                return availableHeight
            }

            if !isCompact, !viewLayout.isLarge {
                return min(availableHeight, 200 + viewLayout.edgePadding * 2)
            }

            let bottomInset = min(view.safeAreaInsets.bottom, availableHeight)
            let contentHeight = availableHeight - bottomInset
            let fraction: CGFloat = isCompact ? 0.6 : 1.0 / 3.0
            let preferredHeight = contentHeight * fraction + bottomInset + viewLayout.edgePadding * 2

            return min(availableHeight, max(dismissedSupplementContainerOffset, preferredHeight))
        }

        private var dismissedSupplementContainerOffset: CGFloat {
            min(availableSupplementHeight, viewLayout.isLarge ? 120 : 50.0 + viewLayout.edgePadding * 2)
        }

        private let compactMinimumTranslation: CGFloat = 100.0
        private let regularMinimumTranslation: CGFloat = 50.0

        // MARK: - Constraints

        private var playerCompactBottomAnchor: NSLayoutConstraint?
        private var playerRegularBottomAnchor: NSLayoutConstraint?
        private var supplementHeightAnchor: NSLayoutConstraint?
        private var supplementBottomAnchor: NSLayoutConstraint?

        private var supplementHeight: CGFloat = 0 {
            didSet {
                supplementHeightAnchor?.constant = supplementHeight
            }
        }

        private var supplementOffset: CGFloat = 0 {
            didSet {
                supplementBottomAnchor?.constant = supplementOffset
            }
        }


        private var compactPlayerAnchorOffset: CGFloat {
            compactPlayerBottomOffset
        }

        private var compactPlayerBottomOffset: CGFloat {
            compactPlayerOverlap ?? dismissedSupplementContainerOffset
        }

        private var compactPlayerOverlap: CGFloat? {
            guard viewState.isCompact, supplementHeight > 0
            else {
                return nil
            }

            let supplementContainerHeight = supplementHeight
            let offsetPercentage = 1 - clamp(supplementOffset.magnitude / supplementContainerHeight, min: 0, max: 1)

            return (dismissedSupplementContainerOffset + viewLayout.edgePadding) * offsetPercentage
        }

        private let mediaSession: MediaSession
        private let videoSize: () -> CGSize
        private let player: (VideoLayout) -> AnyView
        private let playbackControls: AnyView
        let viewState: ViewState

        private var isDismissing = false
        private var didInitiallyAppear: Bool = false
        private var lastSupplementLayout: (layout: ViewLayout, safeAreaInsets: UIEdgeInsets)?

        let onPressEvent = OnPressEvent()
        private var lastTouchPokeTime: CFTimeInterval = 0
        private var pendingPlaybackFocusRequest: UUID?

        init(
            viewState: ViewState,
            mediaSession: MediaSession,
            videoSize: @escaping () -> CGSize,
            player: @escaping (VideoLayout) -> AnyView,
            playbackControls: AnyView
        ) {
            self.viewState = viewState
            self.mediaSession = mediaSession
            self.videoSize = videoSize
            self.player = player
            self.playbackControls = playbackControls

            super.init(nibName: nil, bundle: nil)

            viewState.containerView = self
            viewState.connect(mediaSession: mediaSession)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        private var verticalPanGestureStartConstant: CGFloat?
        private var isPanning: Bool = false
        private var didStartPanningWithSupplement: Bool = false
        private var didStartPanningUpWithoutOverlay: Bool = false

        // MARK: - Supplement Pan Action

        func handleSupplementPanAction(
            translation: CGPoint,
            velocity: CGFloat,
            state: UIGestureRecognizer.State
        ) {
            guard viewState.supplements.isNotEmpty else {
                cancelSupplementPan()
                return
            }
            guard state == .began || isPanning,
                  let playerCompactBottomAnchor
            else { return }

            // The pan owns layout until the final selection is committed below.
            isPanning = true

            if state == .began {
                self.view.layer.removeAllAnimations()
                didStartPanningWithSupplement = viewState.isPresentingSupplement
                verticalPanGestureStartConstant = supplementOffset
                didStartPanningUpWithoutOverlay = !viewState.isPresentingControls

                if didStartPanningUpWithoutOverlay {
                    viewState.showControls()
                }
            }

            if state == .began || state == .changed {
                let minimumTranslation =
                    -((viewState.isCompact ? compactMinimumTranslation : regularMinimumTranslation) +
                        dismissedSupplementContainerOffset
                    )

                let shouldHaveSupplementPresented = supplementOffset < minimumTranslation

                if shouldHaveSupplementPresented, !viewState.isPresentingSupplement {
                    viewState.selectedSupplementID = viewState.supplements.first?.id
                } else if !shouldHaveSupplementPresented, viewState.isPresentingSupplement {
                    viewState.selectedSupplementID = nil
                }

                supplementHeight = supplementContainerOffset()
            } else {
                verticalPanGestureStartConstant = nil

                let translationMin: CGFloat = viewState.isCompact ? compactMinimumTranslation : regularMinimumTranslation
                let shouldActuallyDismissSupplement = didStartPanningWithSupplement && (translation.y > translationMin || velocity > 1000)

                if shouldActuallyDismissSupplement {
                    // If we started with a supplement and panned down more than 100 points, dismiss it
                    viewState.selectedSupplementID = nil
                }

                let shouldActuallyPresentSupplement = !didStartPanningWithSupplement &&
                    (translation.y < -translationMin || velocity < -1000)

                if shouldActuallyPresentSupplement {
                    // If we didn't start with a supplement and panned up more than 100 points, present it
                    viewState.selectedSupplementID = viewState.supplements.first?.id
                }

                isPanning = false
                presentSupplementContainer(viewState.isPresentingSupplement)

                let shouldActuallyDismissOverlay = didStartPanningUpWithoutOverlay && !viewState.isPresentingSupplement

                if shouldActuallyDismissOverlay {
                    viewState.hideControls()
                }

                return
            }

            guard let verticalPanGestureStartConstant else {
                Logger.error("Vertical pan gesture invalid state: verticalPanGestureStartConstant is nil")
                return
            }

            let newOffset = verticalPanGestureStartConstant + translation.y

            let clampedOffset = clamp(
                newOffset,
                min: -supplementHeight,
                max: -dismissedSupplementContainerOffset
            )

            if newOffset < clampedOffset {
                let excess = clampedOffset - newOffset
                let resistance = pow(excess, 0.7)
                supplementOffset = max(-availableSupplementHeight, clampedOffset - resistance)
            } else if newOffset > -dismissedSupplementContainerOffset {
                let excess = newOffset - clampedOffset
                let resistance = pow(excess, 0.5)

                supplementOffset = clamp(
                    clampedOffset + resistance,
                    min: -dismissedSupplementContainerOffset,
                    max: -min(50, dismissedSupplementContainerOffset)
                )
            } else {
                supplementOffset = clampedOffset
            }

            playerCompactBottomAnchor.constant = compactPlayerAnchorOffset
        }

        func cancelSupplementPan() {
            guard isPanning else { return }

            isPanning = false
            verticalPanGestureStartConstant = nil
            viewState.setInteraction(.pan, active: false)


            presentSupplementContainer(viewState.isPresentingSupplement)
        }

        // MARK: - present

        func presentSupplementContainer(_ didPresent: Bool) {
            guard !isPanning, let playerCompactBottomAnchor
            else { return }

            let presentedOffset = supplementContainerOffset()
            supplementHeight = presentedOffset
            supplementOffset = didPresent ? -presentedOffset : -dismissedSupplementContainerOffset

            playerCompactBottomAnchor.constant = compactPlayerAnchorOffset

            let completion: (Bool) -> Void

            let supplementID = viewState.selectedSupplementID
            let playbackFocusRequest = !didPresent && viewState.isPresentingProgress ? UUID() : nil
            pendingPlaybackFocusRequest = playbackFocusRequest

            completion = { [weak self] finished in
                guard let self, finished else { return }

                if let supplementID {
                    viewState.focusSupplementIfNeeded(supplementID)
                } else if let playbackFocusRequest {
                    restorePlaybackFocusIfNeeded(playbackFocusRequest)
                }
            }

            UIView.animate(
                withDuration: viewState.isCompact ? 0.75 : 0.6,
                delay: 0,
                usingSpringWithDamping: 0.8,
                initialSpringVelocity: 0.4,
                options: .allowUserInteraction
            ) { [weak self] in
                self?.view.layoutIfNeeded()
            } completion: { completion($0) }
        }

        // MARK: - viewDidAppear

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)

            view.window?.addGestureRecognizer(windowMenuGesture)

            if !didInitiallyAppear {
                viewState.showControls()
                setupPlayerView()
                initialHitBlockView.removeFromSuperview()
                didInitiallyAppear = true
            }
        }

        // MARK: - viewDidLoad

        override func viewDidLoad() {
            super.viewDidLoad()

            view.backgroundColor = .black

            viewState.isCompact = viewLayout.usesCompactPlayer

            setupOnLoadViews()
            setupOnLoadConstraints()
            observeSupplementInteraction()

            let gesture = UITapGestureRecognizer(target: self, action: #selector(handleMenuEnded))
            gesture.allowedPressTypes = [NSNumber(value: UIPress.PressType.menu.rawValue)]
            view.addGestureRecognizer(gesture)
        }

        // Setup player view separately after view appears to hopefully
        // prevent player playing before the view is done presenting
        private func setupPlayerView() {
            addChild(playerViewController)
            view.addSubview(playerView)
            view.sendSubviewToBack(playerView)
            playerViewController.didMove(toParent: self)
            playerView.backgroundColor = .black

            let compactBottomAnchor = supplementContainerView.topAnchor
            let bottomAnchor = playerView.bottomAnchor.constraint(
                equalTo: compactBottomAnchor,
                constant: compactPlayerAnchorOffset
            )

            playerCompactBottomAnchor = bottomAnchor
            playerRegularBottomAnchor = playerView.bottomAnchor.constraint(equalTo: view.bottomAnchor)

            NSLayoutConstraint.activate([
                playerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                playerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                playerView.topAnchor.constraint(equalTo: view.topAnchor),
            ])

            playerCompactBottomAnchor?.isActive = viewState.isCompact
            playerRegularBottomAnchor?.isActive = !viewState.isCompact
        }

        private func setupOnLoadViews() {
            addChild(playbackControlsViewController)
            view.addSubview(playbackControlsView)
            playbackControlsViewController.didMove(toParent: self)
            playbackControlsView.backgroundColor = .clear

            addChild(supplementContainerViewController)
            view.addSubview(supplementContainerView)
            supplementContainerViewController.didMove(toParent: self)
            supplementContainerView.backgroundColor = .clear

            addChild(overlayActionsViewController)
            view.addSubview(overlayActionsView)
            overlayActionsViewController.didMove(toParent: self)
            overlayActionsView.backgroundColor = .clear

            view.addSubview(initialHitBlockView)
            view.bringSubviewToFront(initialHitBlockView)
        }

        private func setupOnLoadConstraints() {

            supplementHeight = supplementContainerOffset(isCompact: viewLayout.usesCompactPlayer)
            supplementOffset = -dismissedSupplementContainerOffset

            let bottomAnchor = supplementContainerView.topAnchor.constraint(equalTo: view.bottomAnchor, constant: supplementOffset)
            supplementBottomAnchor = bottomAnchor
            let heightAnchor = supplementContainerView.heightAnchor.constraint(equalToConstant: supplementHeight)
            supplementHeightAnchor = heightAnchor

            NSLayoutConstraint.activate([
                supplementContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                supplementContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                bottomAnchor,
                heightAnchor,
            ])

            let playbackControlsBottomAnchor = playbackControlsView.bottomAnchor.constraint(
                equalTo: view.bottomAnchor,
                constant: -dismissedSupplementContainerOffset
            )
            playbackControlsBottomAnchor.priority = .defaultHigh

            NSLayoutConstraint.activate([
                playbackControlsView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                playbackControlsView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                playbackControlsView.topAnchor.constraint(equalTo: view.topAnchor),
                playbackControlsBottomAnchor,
                playbackControlsView.bottomAnchor.constraint(
                    lessThanOrEqualTo: overlayActionsView.topAnchor,
                    constant: -viewLayout.edgePadding
                ),
                overlayActionsView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: viewLayout.edgePadding),
                overlayActionsView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -viewLayout.edgePadding),
                overlayActionsView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -viewLayout.edgePadding),
            ])

            NSLayoutConstraint.activate([
                initialHitBlockView.topAnchor.constraint(equalTo: view.topAnchor),
                initialHitBlockView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                initialHitBlockView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                initialHitBlockView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()

            updateSystemSafeArea()
            let layout = viewLayout
            let safeAreaInsets = view.safeAreaInsets
            guard playerCompactBottomAnchor != nil,
                  lastSupplementLayout?.layout != layout || lastSupplementLayout?.safeAreaInsets != safeAreaInsets
            else { return }

            lastSupplementLayout = (layout, safeAreaInsets)
            if viewState.layoutSize != layout.size {
                viewState.layoutSize = layout.size
            }
            cancelSupplementPan()
            adjustConstraints(isCompact: layout.usesCompactPlayer)
        }

        override func viewSafeAreaInsetsDidChange() {
            super.viewSafeAreaInsetsDidChange()
            updateSystemSafeArea()
        }

        private func updateSystemSafeArea() {
            // Capture system insets before the hosting controller disables them.
            let insets = view.safeAreaInsets
            let isRTL = view.effectiveUserInterfaceLayoutDirection == .rightToLeft
            let system = EdgeInsets(
                top: insets.top,
                leading: isRTL ? insets.right : insets.left,
                bottom: insets.bottom,
                trailing: isRTL ? insets.left : insets.right
            )

            if viewState.systemInsets != system {
                viewState.systemInsets = system
            }
        }

        private func adjustConstraints(isCompact: Bool) {
            viewState.isCompact = isCompact

            guard let playerCompactBottomAnchor
            else { return }

            let presentedOffset = supplementContainerOffset(isCompact: isCompact)

            if isCompact {
                playerRegularBottomAnchor?.isActive = false
                playerCompactBottomAnchor.isActive = true
            } else {
                playerCompactBottomAnchor.isActive = false
                playerRegularBottomAnchor?.isActive = true
            }

            supplementOffset = viewState
                .isPresentingSupplement ? -presentedOffset : -dismissedSupplementContainerOffset
            supplementHeight = presentedOffset

            playerCompactBottomAnchor.constant = compactPlayerAnchorOffset
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)

            // An interactive dismissal can be cancelled.
            isDismissing = false
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)


            isDismissing = false
            var ancestor: UIViewController? = self

            while let controller = ancestor {
                if controller.isBeingDismissed || controller.isMovingFromParent {
                    isDismissing = true
                    break
                }

                ancestor = controller.parent
            }
        }

        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)

            windowMenuGesture.view?.removeGestureRecognizer(windowMenuGesture)

            // Covering the player with a full-screen sheet does not end playback.
            if isDismissing {
                didDismiss()
            }
        }

        func didDismiss() {
            guard !viewState.isBeingDismissed else { return }

            viewState.isBeingDismissed = true
            mediaSession.stop()
        }

        func detachSurface() {
            guard viewState.containerView === self else { return }

            viewState.containerView = nil
            viewState.disconnect()
        }

        // MARK: - tvOS

        private lazy var windowMenuGesture: UITapGestureRecognizer = {
            let gesture = UITapGestureRecognizer()
            gesture.allowedPressTypes = [NSNumber(value: UIPress.PressType.menu.rawValue)]
            gesture.delegate = self
            return gesture
        }()

        override var preferredFocusEnvironments: [UIFocusEnvironment] {
            if viewState.isSupplementFocusPending {
                return [supplementContainerViewController]
            }

            if viewState.isPresentingProgress {
                return [playbackControlsViewController]
            }

            return super.preferredFocusEnvironments
        }

        func focusSupplementContent() {
            // Tabs stay disabled while content focus is pending. Enter the hosting
            // hierarchy from the common ancestor of the current and requested focus.
            setNeedsFocusUpdate()
            updateFocusIfNeeded()
        }

        private func restorePlaybackFocusIfNeeded(_ request: UUID) {
            guard pendingPlaybackFocusRequest == request else { return }

            pendingPlaybackFocusRequest = nil

            // Retry only if the controls could not receive focus during dismissal.
            // They may already be focused when a layout animation starts.
            guard viewState.isPresentingProgress,
                  (UIFocusSystem.focusSystem(for: view)?.focusedItem as? UIView)?.isDescendant(of: playbackControlsView) != true
            else { return }

            view.window?.setNeedsFocusUpdate()
            updateFocusIfNeeded()
        }

        override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
            super.didUpdateFocus(in: context, with: coordinator)

            // Complete the handoff synchronously when focus leaves the supplement.
            // A late animation completion must not undo navigation within the player
            // or into another focus environment, such as a menu.
            if let nextFocusedView = context.nextFocusedView,
               !nextFocusedView.isDescendant(of: supplementContainerView)
            {
                pendingPlaybackFocusRequest = nil
            }
        }

        override func shouldUpdateFocus(in context: UIFocusUpdateContext) -> Bool {
            guard super.shouldUpdateFocus(in: context) else { return false }

            // A lone title is an entry point, not a focus stop. Wait for its content
            // to appear before handing focus to the supplement's preferred control.
            if !viewState.isPresentingSupplement,
               viewState.visibleElements.contains(.supplements),
               let supplement = viewState.singleSupplement,
               context.focusHeading.contains(.down),
               context.nextFocusedView?.isDescendant(of: supplementContainerView) == true
            {
                DispatchQueue.main.async { [weak self] in
                    guard let self,
                          !viewState.isPresentingSupplement,
                          viewState.visibleElements.contains(.supplements),
                          viewState.singleSupplement?.id == supplement.id
                    else { return }

                    viewState.selectedSupplementID = supplement.id
                }

                return false
            }

            return true
        }

        private var supplementInteractionObservation: ObservationToken?

        /// 原版在 tvOS 26 的 `updateProperties()` 里同步；这里在可见元素变化时同步。
        private func observeSupplementInteraction() {
            supplementInteractionObservation = ObservationToken { [weak self] in
                self?.viewState.visibleElements.contains(.supplements) ?? false
            } onChange: { [weak self] isVisible in
                self?.supplementContainerView.isUserInteractionEnabled = isVisible
            }
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesBegan(touches, with: event)

            guard !(viewState.presentation == .hidden && viewState.isPresentingOverlayActions) else { return }

            let now = CACurrentMediaTime()
            guard now - lastTouchPokeTime > 1.0 else { return }

            lastTouchPokeTime = now

            if mediaSession.item.isLiveStream {
                viewState.showControls()
            } else {
                viewState.showProgress()
            }
        }

        private func forwardPressesBegan(
            _ presses: Set<UIPress>,
            event: UIPressesEvent?
        ) {
            super.pressesBegan(presses, with: event)
        }

        private func forwardPressesEnded(
            _ presses: Set<UIPress>,
            event: UIPressesEvent?
        ) {
            super.pressesEnded(presses, with: event)
        }

        override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            for press in presses {
                switch press.type {
                case .playPause, .select, .menu:
                    continue
                default:
                    let defaultAction: () -> Void = { [weak self] in
                        guard let self else { return }

                        self.forwardPressesBegan([press], event: event)
                    }

                    onPressEvent.send(
                        .init(
                            type: press.type,
                            phase: press.phase,
                            defaultAction: defaultAction
                        )
                    )
                }
            }
        }

        override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            for press in presses {
                switch press.type {
                case .playPause:
                    handlePlayPauseEnded()
                case .select:
                    handleSelectEnded(press, event: event)
                case .menu:
                    handleMenuEnded()
                default:
                    let defaultAction: () -> Void = { [weak self] in
                        guard let self else { return }

                        self.forwardPressesEnded([press], event: event)
                    }

                    onPressEvent.send(
                        .init(
                            type: press.type,
                            phase: press.phase,
                            defaultAction: defaultAction
                        )
                    )
                }
            }
        }

        override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            for press in presses {
                onPressEvent.send(
                    .init(type: press.type, phase: .cancelled) { [weak self] in
                        self?.forwardPressesCancelled([press], event: event)
                    }
                )
            }
        }

        private func forwardPressesCancelled(_ presses: Set<UIPress>, event: UIPressesEvent?) {
            super.pressesCancelled(presses, with: event)
        }

        private func handlePlayPauseEnded() {
            guard mediaSession.canControlPlayback else { return }

            if viewState.isScrubbing {
                viewState.cancelScrub()
                return
            }

            if viewState.presentation == .hidden {
                if mediaSession.playbackRequestStatus == .paused {
                    mediaSession.setPlaybackRequestStatus(status: .playing)
                }

                viewState.showControls()
            } else {
                switch mediaSession.playbackRequestStatus {
                case .playing:
                    mediaSession.setPlaybackRequestStatus(status: .paused)
                case .paused:
                    mediaSession.setPlaybackRequestStatus(status: .playing)
                }
            }

            viewState.refreshAutoDismiss()
        }

        private func handleSelectEnded(_ press: UIPress, event: UIPressesEvent?) {
            if viewState.isOverlayActionFocused {
                forwardPressesEnded([press], event: event)
                return
            }

            if viewState.presentation == .hidden {
                viewState.showControls()
                return
            }

            if viewState.isScrubbing {
                viewState.commitScrub(resumePlayback: true)
            } else if viewState.isProgressBarFocused {
                guard mediaSession.canControlPlayback else { return }

                switch mediaSession.playbackRequestStatus {
                case .playing:
                    mediaSession.setPlaybackRequestStatus(status: .paused)
                case .paused:
                    mediaSession.setPlaybackRequestStatus(status: .playing)
                }

                viewState.refreshAutoDismiss()
            } else {
                forwardPressesEnded([press], event: event)
            }
        }

        @objc
        private func handleMenuEnded() {
            // Let a system menu or alert consume Back before dismissing player UI.
            guard !viewState.isFocusOutsidePlayer || viewState.presentation == .hidden else { return }

            if viewState.isScrubbing {
                viewState.cancelScrub()
            } else if viewState.isPresentingSupplement {
                viewState.selectedSupplementID = nil
            } else if viewState.presentation != .hidden {
                viewState.hideControls()
            } else if VideoPlayerDefaults.confirmClose {
                viewState.isPresentingCloseConfirmation = true
            } else {
                mediaSession.stop()
            }
        }
    }
}

// MARK: - tvOS PressEvent

extension VideoPlayer.UIContainerViewController {

    struct PressEvent {

        enum Resolution {

            case handled
            case fallback
        }

        let type: UIPress.PressType
        let phase: UIPress.Phase

        fileprivate let defaultAction: () -> Void

        func resolve(_ resolution: Resolution) {
            if resolution == .fallback {
                defaultAction()
            }
        }
    }

    typealias OnPressEvent = EventPublisher<PressEvent>
}

extension VideoPlayer.UIContainerViewController: UIGestureRecognizerDelegate {

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive press: UIPress) -> Bool {
        let focusedView = UIFocusSystem.focusSystem(for: view)?.focusedItem as? UIView
        return focusedView?.isDescendant(of: view) != true
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
