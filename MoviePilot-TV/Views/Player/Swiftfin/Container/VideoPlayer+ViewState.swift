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
            case dimming
        }

        enum AspectFillBehavior {

            case fit
            case fill
        }

        enum Interaction: Hashable {

            case pan
            case pinch
            case speedBoost
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
            focusCoordinator.focus(mediaSession?.item.isLiveStream == true ? Focus.controls : Focus.progress)
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
                    cancelScrub()
                    zoom.endInteraction()
                    setInteraction(.pan, active: false)
                    setInteraction(.pinch, active: false)
                    hideControls()
                }
            }
        }

        var isBeingDismissed = false
        var isCompact: Bool = false

        var isScrubbing: Bool {
            scrubPosition != nil
        }

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
                var elements: Set<Element> = [.progress, .toolbar, .playbackButtons, .dimming]


                if supplements.isNotEmpty {
                    elements.insert(.supplements)
                }

                return elements

            case let .supplement(_, showsPlaybackButtons):
                if ViewLayout.platformDefault.isLarge {
                    return [.supplements, .dimming]
                }

                if isCompact {
                    return showsPlaybackButtons
                        ? [.toolbar, .playbackButtons, .supplements, .dimming]
                        : [.toolbar, .supplements]
                }

                return isPresentingFullScreenSupplement
                    ? [.supplements, .dimming]
                    : [.toolbar, .supplements, .dimming]
            }
        }

        var originalPlaybackRate: Double?

        let focusCoordinator: FocusCoordinator = .init()
        let jumpProgressObserver: JumpProgressObserver = .init()

        private var scrubPosition: Duration? {
            didSet {
                if (oldValue == nil) != (scrubPosition == nil) {
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

        func beginScrub() {
            guard !isScrubbing, !isGestureLocked, mediaSession?.canSeek == true else { return }

            scrubOriginSeconds = mediaSession?.seconds
            scrubPosition = scrubOriginSeconds
        }

        func commitScrub(resumePlayback: Bool = false) {
            guard isScrubbing else { return }

            mediaSession?.seek(to: scrubbedSeconds)

            if resumePlayback {
                mediaSession?.setPlaybackRequestStatus(status: .playing)
            }

            scrubPosition = nil
            scrubOriginSeconds = nil
        }

        func cancelScrub() {
            guard isScrubbing else { return }

            scrubPosition = nil
            scrubOriginSeconds = nil
        }

        init(timer: PokeIntervalTimer? = nil) {
            self.timer = timer ?? .init(defaultInterval: ViewLayout.platformDefault.isLarge ? 10 : 5)

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

                    cancelScrub()
                    freezePlaybackTimeIfHidden()

                    if let rate = originalPlaybackRate {
                        self.mediaSession?.rate = rate
                        originalPlaybackRate = nil
                    }

                    setInteraction(.speedBoost, active: false)


                    fitVideo()
                },
                // 章节可能在播放中途从有变成没有（mpv 读出的片长更短、读完发现文件里也没有章节），「章节」面板随之消失。
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

                    if !activity.1 {
                        cancelScrub()
                    }

                    refreshAutoDismiss()
                },
            ]

            observations.forEach { $0.store(in: &sessionObservations) }
        }

        func disconnect() {
            sessionObservations.removeAll()
            cancelScrub()
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
            // Short interval for progress only
            presentation == .progress ? 2 : 10
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
