//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//
// 本文件改自 Swiftfin：Shared/Views/VideoPlayer/Container/VideoPlayer+ViewState.swift
// Modifications for MoviePilot-TV are also licensed under MPL-2.0.
//
// 修改：
// - 删去 `#if os(iOS)` 分支（iOS 的点击/平移手势状态）。
// - 补充面板列表的 Swiftfin 设置项换成 `VideoPlayerDefaults.supplements`（取 Swiftfin 默认值）。
// - 直播节目单（EPGSupplement）只在直播条目且开启实验设置时出现，依赖整个 Jellyfin 直播电视模块，未移植：去掉追加它的分支。
// - Swiftfin 的 `isolated deinit` 改为 `nonisolated deinit`：tvOS 18 上隔离析构的回部署会崩溃（工程约定）。
// - 章节不在条目上，取 `MediaSession.chapters` 传给面板；章节有无变化时与换条目一样检查选中的面板还在不在
//   （检查抽成 `supplementsDidChange`）。
// - 遥控器行为按系统播放器：去掉长按右键的 2 倍速，改为按住左右键快退、快进（`Scan`，见 VideoPlayer+RemoteCommands.swift）；
//   拖动分「确认」「取消（回到原处）」「丢弃（换集、退出时直接清掉）」三种结束方式。
// - 控制条不再压黑色渐变，只有打开面板时才压暗画面；控制条 5 秒、只显示进度条时 2 秒后自动收起。
//

import Combine
import Foundation
import Observation
import SwiftUI

extension VideoPlayer {

    @MainActor
    @Observable
    final class ViewState {

        var layoutSize: CGSize = .zero
        var systemInsets: EdgeInsets = .zero

        var supplementInsets: EdgeInsets {
            systemInsets.max(ViewLayout.platformDefault.edgePadding)
        }


        enum Presentation: Equatable {

            case hidden
            case progress
            case controls
            case supplement(String, showsPlaybackButtons: Bool = true)
        }

        enum Element {

            case overlayActions
            case progress
            case toolbar
            case playbackButtons
            case supplements
        }

        enum AspectFillBehavior {

            case fit
            case fill
        }

        enum Interaction: Hashable {

            case pan
            case pinch
            case button(UUID)
            case menu(UUID)
        }

        enum Focus {

            static let progress = "player.progress"
            static let controls = "player.controls"
            static let supplementTabs = "player.supplementTabs"

            static func action(_ id: String) -> String {
                "player.action.\(id)"
            }

            static func supplementContent(_ id: String) -> String {
                "player.supplementContent.\(id)"
            }
        }

        struct OverlayAction: Identifiable {

            struct ID: Hashable {

                let providerID: String
                let actionID: String

                var focusID: String {
                    "player.overlayAction.\(providerID.count):\(providerID)\(actionID)"
                }
            }

            let id: ID
            let button: VideoPlayerOverlayAction
        }

        var overlayActions: [OverlayAction] {
            let providers: [any VideoPlayerOverlayActionProviding] = (mediaSession?.playbackItem?
                .segments
                .map { [$0 as any VideoPlayerOverlayActionProviding] } ?? []) +
                supplements
                .compactMap { $0 as? any VideoPlayerOverlayActionProviding }

            return providers.flatMap { provider in
                provider.overlayActions.map {
                    OverlayAction(id: .init(providerID: provider.id, actionID: $0.id), button: $0)
                }
            }
        }

        var isPresentingOverlayActions: Bool {
            visibleElements.contains(.overlayActions)
        }

        var isOverlayActionFocused: Bool {
            isPresentingOverlayActions && overlayActions.contains { focusCoordinator.focusedIDs.contains($0.id.focusID) }
        }

        func performOverlayAction(_ id: OverlayAction.ID) {
            guard isPresentingOverlayActions,
                  let action = overlayActions.first(where: { $0.id == id })
            else { return }

            action.button.action()
            refreshAutoDismiss()
        }

        private func focusPlaybackControls() {
            let id = mediaSession?.item.isLiveStream == true ? Focus.controls : Focus.progress

            // 进播放器时播放器还没就绪，进度条的滑块是 disabled 的，写焦点扑空（焦点会被工具栏的默认焦点接走）。
            // 记下来，等能跳转了（canSeek 为真）再补这一次。
            guard id != Focus.progress || mediaSession?.canSeek == true else {
                isAwaitingPlaybackFocus = true
                return
            }

            isAwaitingPlaybackFocus = false
            focusCoordinator.focus(id)
        }

        func updateOverlayActionFocus(previousIDs: [OverlayAction.ID] = []) {
            guard !isPresentingCloseConfirmation,
                  containerView?.presentedViewController == nil
            else { return }

            if presentation == .hidden, isPresentingOverlayActions {
                if !isOverlayActionFocused, let first = overlayActions.first {
                    focusCoordinator.focus(first.id.focusID)
                }
            } else if isPresentingProgress,
                      previousIDs.contains(where: {
                          focusCoordinator.focusedIDs.contains($0.focusID) ||
                              focusCoordinator.lastFocusedIDs.contains($0.focusID)
                      }),
                      !isOverlayActionFocused
            {
                focusPlaybackControls()
            }
        }

        private(set) var presentation: Presentation = .hidden

        private(set) var aspectFillBehavior: AspectFillBehavior = .fit

        var zoom = VideoZoom()

        var canPanZoom: Bool {
            !isGestureLocked && !isPresentingSupplement && zoom.canPan
        }

        func resetZoom() {
            if zoom.isPanning {
                setInteraction(.pan, active: false)
            }

            zoom.reset()
            setInteraction(.pinch, active: false)
        }

        var isGestureLocked: Bool = false {
            didSet {
                if isGestureLocked {
                    discardScrub()
                    zoom.endInteraction()
                    setInteraction(.pan, active: false)
                    setInteraction(.pinch, active: false)
                    hideControls()
                }
            }
        }

        var isBeingDismissed = false
        var isCompact: Bool = false

        /// 单独存一份，只在开始、结束拖动时变：拖动和快退快进中位置每秒变好几次，只读这个的视图不必跟着重算。
        private(set) var isScrubbing = false

        var selectedSupplementID: String? {
            get {
                guard case let .supplement(id, _) = presentation else { return nil }

                return id
            }
            set {
                guard !isGestureLocked, newValue != selectedSupplementID else { return }

                transition(to: newValue.map { .supplement($0) } ?? .controls)
            }
        }

        var selectedSupplement: any VideoPlayerSupplement? {
            guard let selectedSupplementID else { return nil }

            return supplements.first { $0.id == selectedSupplementID }
        }

        private(set) var guestSupplement: any VideoPlayerSupplement?

        var supplements: [any VideoPlayerSupplement] {
            if let guestSupplement {
                return [guestSupplement]
            }

            guard let mediaSession, let item = mediaSession.playbackItem else { return [] }

            let chapters = mediaSession.chapters
            let selected = VideoPlayerDefaults.supplements.compactMap {
                $0.makeSupplement(for: item, queue: mediaSession.queue, chapters: chapters)
            }

            return selected
        }

        var singleSupplement: any VideoPlayerSupplement? {
            let supplements = supplements

            return supplements.count == 1 ? supplements.first : nil
        }

        func presentGuestSupplement(_ supplement: some VideoPlayerSupplement) {
            guard !isGestureLocked else { return }

            guestSupplement = supplement
            transition(to: .supplement(supplement.id))
        }

        private var pendingSupplementFocusID: String?

        /// 起播时进度条还不可聚焦，初始焦点请求被记下，等 `canSeek` 为真再补发。
        private var isAwaitingPlaybackFocus = false

        var isSupplementFocusPending: Bool {
            pendingSupplementFocusID != nil
        }

        // The host fade and container slide can finish in either order. Keep the request
        // pending until the preferred control receives focus after these transitions.
        func focusSupplementIfNeeded(_ id: String) {
            guard pendingSupplementFocusID == id,
                  let selectedSupplement, selectedSupplement.id == id
            else { return }

            containerView?.focusSupplementContent()
            focusCoordinator.focus(selectedSupplement.preferredFocusID)
        }

        var isPresentingSupplement: Bool {
            selectedSupplementID != nil
        }

        var isPresentingFullScreenSupplement: Bool {
            !isCompact && selectedSupplement?.presentationStyle == .expanded
        }

        var isPresentingControls: Bool {
            presentation == .controls || isPresentingSupplement
        }

        var isPresentingProgress: Bool {
            guard !isGestureLocked else {
                return false
            }

            return isScrubbing || presentation == .progress || presentation == .controls
        }

        var isProgressBarFocused: Bool {
            focusCoordinator.focusedIDs.contains(Focus.progress)
        }

        var isFocusOutsidePlayer: Bool {
            focusCoordinator.focusedIDs.isEmpty && focusCoordinator.lastFocusedIDs.isNotEmpty
        }

        var presentationControllerShouldDismiss: Bool {
            presentation == .controls && !isScrubbing && interactions.isEmpty
        }

        /// Layout and interaction affect visibility, without writing another state.
        var visibleElements: Set<Element> {
            guard !isGestureLocked else { return [] }

            if isScrubbing {
                return [.progress]
            }

            switch presentation {
            case .hidden:
                return overlayActions.isEmpty ? [] : [.overlayActions]

            case .progress:
                return overlayActions.isEmpty ? [.progress] : [.progress, .overlayActions]

            case .controls:
                // 控制条不压暗画面：和系统播放器一样只有几个玻璃控件，下面的字幕不被挡住。
                var elements: Set<Element> = [.progress, .toolbar, .playbackButtons]


                if supplements.isNotEmpty {
                    elements.insert(.supplements)
                }

                return elements

            case let .supplement(_, showsPlaybackButtons):
                // 打开面板也不压暗画面：面板、卡片自己带玻璃底，文字不靠黑色渐变衬。
                if ViewLayout.platformDefault.isLarge {
                    return [.supplements]
                }

                if isCompact {
                    return showsPlaybackButtons
                        ? [.toolbar, .playbackButtons, .supplements]
                        : [.toolbar, .supplements]
                }

                return isPresentingFullScreenSupplement
                    ? [.supplements]
                    : [.toolbar, .supplements]
            }
        }

        let focusCoordinator: FocusCoordinator = .init()

        private var scrubPosition: Duration? {
            didSet {
                if (oldValue == nil) != (scrubPosition == nil) {
                    isScrubbing = scrubPosition != nil
                    freezePlaybackTimeIfHidden()
                    refreshAutoDismiss()
                }
            }
        }

        private var hiddenPlaybackSeconds: Duration = .zero

        /// Keep hidden progress mounted without observing the live timeline.
        /// Playback actions and new scrubs must still use the session's time.
        var playbackSeconds: Duration {
            isPresentingProgress ? mediaSession?.seconds ?? .zero : hiddenPlaybackSeconds
        }

        var scrubbedSeconds: Duration {
            get {
                scrubPosition ?? playbackSeconds
            }
            set {
                guard isScrubbing else { return }

                scrubPosition = newValue
            }
        }

        let toastProxy: ToastProxy = .init()

        @ObservationIgnored
        weak var containerView: VideoPlayer.UIContainerViewController?
        private(set) weak var mediaSession: MediaSession?

        private let timer: PokeIntervalTimer
        private var interactions: Set<Interaction> = []
        @ObservationIgnored
        private var cancellables: Set<AnyCancellable> = []
        @ObservationIgnored
        private var sessionObservations: Set<AnyCancellable> = []


        var isPresentingCloseConfirmation: Bool = false {
            didSet {
                refreshAutoDismiss()
            }
        }


        private(set) var scrubOriginSeconds: Duration?

        /// 正在快退、快进（按住左右键开始）；拖动中但没有自动移动时为 nil。
        private(set) var scan: Scan?
        @ObservationIgnored
        private var scanTask: Task<Void, Never>?
        /// 快退快进期间为了让画面跟上跳转过：取消时要跳回原处。
        @ObservationIgnored
        private var scanHasSeeked = false
        /// 快退快进开始时正在播放：取消后接着播。
        @ObservationIgnored
        private var scanResumesPlayback = false

        func beginScrub() {
            guard !isScrubbing, !isGestureLocked, mediaSession?.canSeek == true else { return }

            scrubOriginSeconds = mediaSession?.seconds
            scrubPosition = scrubOriginSeconds
        }

        /// 从拖动（或快退快进）停下的位置播放。
        func commitScrub(resumePlayback: Bool = false) {
            guard isScrubbing else { return }

            let target = scrubbedSeconds
            discardScrub()
            mediaSession?.seek(to: target)

            if resumePlayback {
                mediaSession?.setPlaybackRequestStatus(status: .playing)
            }
        }

        /// 用户放弃这次拖动（返回键、焦点离开进度条）：回到原处；快退快进前在播放的，接着播。
        func cancelScrub() {
            guard isScrubbing else { return }

            let origin = scrubOriginSeconds
            let seeksBack = scanHasSeeked
            let resumesPlayback = scanResumesPlayback
            discardScrub()

            if seeksBack, let origin {
                mediaSession?.seek(to: origin)
            }
            if resumesPlayback {
                mediaSession?.setPlaybackRequestStatus(status: .playing)
            }
        }

        /// 直接清掉拖动状态，不跳转也不改播放状态：换集、退出、不能再跳转时用，免得把旧位置跳到新条目上。
        func discardScrub() {
            stopScan()
            scanHasSeeked = false
            scanResumesPlayback = false
            scrubPosition = nil
            scrubOriginSeconds = nil
        }

        /// 拖动中点一下左右键：拖动位置前后挪一格，不跳转。和快进一样停在片尾前 `Scan.endMargin`，确认后不会被当成播完。
        func moveScrub(by offset: Duration) {
            guard isScrubbing else { return }

            let upper = Scan.upperBound(runtime: mediaSession?.runtime ?? .zero)
            scrubPosition = min(max(scrubbedSeconds + offset, .zero), upper)
        }

        /// 按住左右键：开始快退、快进。画面暂停，进度条按倍速移动（见 `Scan`）。
        func beginScan(_ direction: Scan.Direction) {
            guard let mediaSession, mediaSession.canSeek, mediaSession.runtime != nil else { return }

            if !isScrubbing {
                let wasPlaying = mediaSession.playbackRequestStatus == .playing
                beginScrub()
                guard isScrubbing else { return }

                scanResumesPlayback = wasPlaying
            }

            if mediaSession.playbackRequestStatus == .playing {
                mediaSession.setPlaybackRequestStatus(status: .paused)
            }

            scan = Scan(direction: direction)
            startScanTask()
        }

        /// 快退快进中再点一下左右键：换档或掉头（见 `Scan.next`）。
        func stepScan(_ direction: Scan.Direction) {
            guard isScrubbing, scan != nil else { return }

            scan = Scan.next(after: scan, pressing: direction)
        }

        private func stopScan() {
            scanTask?.cancel()
            scanTask = nil
            scan = nil
        }

        /// 每 0.1 秒按倍速移动拖动位置；每隔 `Scan.seekInterval` 跳一次，让暂停的画面跟上。跳转沿用 `MediaSession.seek`
        /// 的合并机制，前一次还没完成时只保留最新目标。到头（片头，或片尾前 `Scan.endMargin`）就停，留在拖动状态等用户确认或取消。
        /// 拖进片尾前 `Scan.endMargin` 以内再快进，不跳转（见 `Scan.canSeek`）。
        private func startScanTask() {
            scanTask?.cancel()
            scanTask = Task { [weak self] in
                let clock = ContinuousClock()
                var lastTick = clock.now
                var lastSeek = lastTick

                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(100))

                    guard !Task.isCancelled,
                          let self,
                          let scan = self.scan,
                          let position = self.scrubPosition,
                          let mediaSession = self.mediaSession,
                          let runtime = mediaSession.runtime
                    else { return }

                    let now = clock.now
                    // 挂起（回到主屏幕、屏保）后回来，不把整段离开的时间一次补上。
                    let elapsed = min(now - lastTick, Scan.maximumTickInterval)
                    let target = scan.position(after: elapsed, from: position, runtime: runtime)
                    lastTick = now
                    self.scrubPosition = target

                    let reachedBound = scan.hasReachedBound(target, runtime: runtime)
                    if reachedBound || now - lastSeek >= Scan.seekInterval,
                       Scan.canSeek(to: target, runtime: runtime)
                    {
                        if mediaSession.seek(to: target) {
                            self.scanHasSeeked = true
                        }
                        lastSeek = now
                    }

                    if reachedBound {
                        self.scan = nil
                        self.scanTask = nil
                        return
                    }
                }
            }
        }

        init(timer: PokeIntervalTimer? = nil) {
            self.timer = timer ?? .init(defaultInterval: VideoPlayerDefaults.controlsAutoHideInterval)

            self.timer
                .sink { [weak self] in
                    guard let self, canAutoDismiss else { return }

                    // UIKit presentations do not all participate in SwiftUI focus.
                    if containerView?.presentedViewController != nil {
                        refreshAutoDismiss()
                        return
                    }

                    withAnimation(.linear(duration: 0.25)) {
                        self.hideControls()
                    }
                }
                .store(in: &cancellables)

            focusCoordinator.$focusedIDs
                .dropFirst()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] focusedIDs in
                    guard let self else { return }

                    if let supplement = self.selectedSupplement,
                       self.pendingSupplementFocusID == supplement.id,
                       focusedIDs.contains(supplement.preferredFocusID)
                    {
                        self.pendingSupplementFocusID = nil
                    }

                    self.refreshAutoDismiss()
                }
                .store(in: &cancellables)

        }

        nonisolated deinit {}

        /// 面板列表变了：选中的面板还在就保持，不在了就回到控制条。
        private func supplementsDidChange() {
            if let selectedSupplementID {
                if supplements.contains(where: { $0.id == selectedSupplementID }) {
                    transition(to: presentation)
                } else {
                    self.selectedSupplementID = nil
                }
            }

            if supplements.isEmpty {
                containerView?.cancelSupplementPan()
            }
        }

        func connect(mediaSession: MediaSession) {
            sessionObservations.removeAll()
            self.mediaSession = mediaSession
            freezePlaybackTimeIfHidden()

            var previousActivity: (MediaSession.Activity?, Bool)?

            let observations = [
                ObservationToken { [weak mediaSession] in
                    mediaSession?.playbackItem
                } onChange: { [weak self] _ in
                    guard let self else { return }

                    supplementsDidChange()

                    discardScrub()
                    freezePlaybackTimeIfHidden()

                    fitVideo()
                },
                // 章节可能在播放中途从有变成没有（播放器读出的片长更短、读完发现文件里也没有章节），「章节」面板随之消失。
                ObservationToken { [weak mediaSession] in
                    mediaSession?.chapters.isShown
                } onChange: { [weak self] _ in
                    self?.supplementsDidChange()
                },
                ObservationToken { [weak mediaSession] in
                    mediaSession?.playbackRequestStatus
                } onChange: { [weak self] status in
                    guard let self else { return }

                    if status == .paused, presentation == .hidden {
                        showControls()
                    }

                    refreshAutoDismiss()
                },
                ObservationToken { [weak mediaSession] in
                    (mediaSession?.activity, mediaSession?.canSeek == true)
                } onChange: { [weak self] activity in
                    guard let self else { return }

                    if let previousActivity, previousActivity == activity {
                        return
                    }

                    previousActivity = activity

                    if activity.1, isAwaitingPlaybackFocus, isPresentingProgress {
                        focusPlaybackControls()
                    }

                    if !activity.1 {
                        // 不能再跳转了（重新载入、换集）：只清状态。快退快进时暂停是这里加的，恢复播放。
                        let resumesPlayback = scanResumesPlayback
                        discardScrub()
                        if resumesPlayback {
                            self.mediaSession?.setPlaybackRequestStatus(status: .playing)
                        }
                    }

                    refreshAutoDismiss()
                },
            ]

            observations.forEach { $0.store(in: &sessionObservations) }
        }

        func disconnect() {
            sessionObservations.removeAll()
            discardScrub()
            timer.stop()


            mediaSession = nil
            hiddenPlaybackSeconds = .zero
        }

        func fillVideo() {
            resetZoom()
            aspectFillBehavior = .fill
        }

        func fitVideo() {
            resetZoom()
            aspectFillBehavior = .fit
        }

        var isVideoEnlarged: Bool {
            zoom.transform.map { $0.scale > 1 } ?? (aspectFillBehavior == .fill)
        }

        func toggleAspectFillBehavior() {
            if isVideoEnlarged {
                fitVideo()
            } else {
                fillVideo()
            }
        }

        func showControls() {
            guard !isGestureLocked else { return }

            if !isPresentingControls {
                transition(to: .controls)
            } else {
                refreshAutoDismiss()
            }
        }

        /// Reveal the least UI needed for a seek, retaining an already open overlay.
        func showProgress(keepingControls: Bool = true) {
            guard !isGestureLocked else { return }

            if presentation == .hidden || !keepingControls {
                transition(to: .progress)
            } else {
                refreshAutoDismiss()
            }
        }

        func hideControls() {
            transition(to: .hidden)
        }

        func toggleControls() {
            if isPresentingControls {
                hideControls()
            } else {
                showControls()
            }
        }

        func togglePlaybackButtons() {
            guard isCompact, case let .supplement(id, showsPlaybackButtons) = presentation else { return }

            transition(to: .supplement(id, showsPlaybackButtons: !showsPlaybackButtons))
        }

        func setInteraction(_ interaction: Interaction, active: Bool) {
            if active {
                interactions.insert(interaction)
            } else {
                interactions.remove(interaction)
            }

            refreshAutoDismiss()
        }

        private var canAutoDismiss: Bool {
            guard presentation != .hidden,
                  !isScrubbing,
                  !isPresentingSupplement,
                  interactions.isEmpty,
                  mediaSession?.activity == nil,
                  mediaSession?.playbackRequestStatus != .paused else { return false }

            // Menus take focus out of the player, including nested system menus.
            // Resume the countdown only after focus returns to our controls.
            guard !isPresentingCloseConfirmation,
                  !isFocusOutsidePlayer
            else { return false }


            return true
        }

        private var autoDismissInterval: TimeInterval {
            presentation == .progress
                ? VideoPlayerDefaults.progressAutoHideInterval
                : VideoPlayerDefaults.controlsAutoHideInterval
        }

        func refreshAutoDismiss() {
            if canAutoDismiss {
                timer.poke(interval: autoDismissInterval)
            } else {
                timer.stop()
            }
        }

        private func transition(to presentation: Presentation) {

            if case .supplement = presentation {
                resetZoom()
            }

            let wasPresentingSupplement = isPresentingSupplement
            let wasPresentingProgress = isPresentingProgress
            let previousSupplementID = selectedSupplementID

            self.presentation = presentation
            freezePlaybackTimeIfHidden()

            if selectedSupplementID != guestSupplement?.id {
                guestSupplement = nil
            }

            if selectedSupplementID != previousSupplementID {
                pendingSupplementFocusID = singleSupplement?.id == selectedSupplementID ? selectedSupplementID : nil
            }

            if wasPresentingSupplement || isPresentingSupplement {
                containerView?.presentSupplementContainer(isPresentingSupplement)
            }

            if isPresentingProgress, !wasPresentingProgress {
                focusPlaybackControls()
            }

            if !isPresentingProgress {
                isAwaitingPlaybackFocus = false
            }

            refreshAutoDismiss()
        }

        private func freezePlaybackTimeIfHidden() {
            guard !isPresentingProgress else {
                return
            }

            hiddenPlaybackSeconds = mediaSession?.seconds ?? .zero
        }
    }
}
