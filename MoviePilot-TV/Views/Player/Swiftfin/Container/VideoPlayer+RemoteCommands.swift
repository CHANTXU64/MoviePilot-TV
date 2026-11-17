//
// 遥控器播放键、触控板中央和左右键的判断，按 Apple TV 系统播放器的行为：
// - 播放/暂停键、按触控板中央：暂停或继续播放；暂停时呼出控制条。拖动或快退快进中按下，从新位置播放。
// - 左右键点一下跳 10 秒；按住开始快退、快进，再点一下在 2×、3×、4× 之间切换，按播放键或触控板中央从新位置播放，
//   按返回键回到原处。
// 播放内核不支持倒放和 2 倍以上的速度，快退快进是一次自动移动的拖动（`Scan`），只用 `MediaSession` 现有的跳转和暂停。
//

import SwiftUI

extension VideoPlayer.ViewState {

    /// 快退、快进的方向与档位。
    struct Scan: Equatable {

        enum Direction: Equatable {
            case backward
            case forward
        }

        /// 与系统播放器相同的三档。
        static let rates: [Double] = [2, 3, 4]
        /// 每隔多久跳一次，让暂停的画面跟上进度条。
        static let seekInterval: Duration = .milliseconds(500)
        /// 快进停在片尾前这么远：跳到最末尾会被当成播完。
        static let endMargin: Duration = .seconds(2)
        /// 每次移动最多按这么长的时间算：App 挂起后回来，不把离开的时间一次补上。
        static let maximumTickInterval: Duration = .milliseconds(300)

        var direction: Direction
        var level = 0

        var rate: Double {
            Self.rates[min(max(level, 0), Self.rates.count - 1)]
        }

        /// 快退快进中再点一下左右键：同方向换下一档（4× 之后回到 2×），反方向从 2× 开始往回。
        static func next(after current: Scan?, pressing direction: Direction) -> Scan {
            guard let current, current.direction == direction else {
                return Scan(direction: direction)
            }

            return Scan(direction: direction, level: (current.level + 1) % rates.count)
        }

        /// 经过 `elapsed` 之后的位置，不越过片头和片尾前的 `endMargin`。
        func position(after elapsed: Duration, from position: Duration, runtime: Duration) -> Duration {
            let step = elapsed * rate
            let upper = Self.upperBound(runtime: runtime)

            switch direction {
            case .forward:
                return min(max(position, .zero) + step, max(upper, position))
            case .backward:
                return max(min(position, upper) - step, .zero)
            }
        }

        /// 已经到头：快退到片头，或快进到片尾前 `endMargin`。
        func hasReachedBound(_ position: Duration, runtime: Duration) -> Bool {
            switch direction {
            case .forward: position >= Self.upperBound(runtime: runtime)
            case .backward: position <= .zero
            }
        }

        /// 快进和拖动中挪位置的终点：片尾前 `endMargin`。
        static func upperBound(runtime: Duration) -> Duration {
            max(runtime - endMargin, .zero)
        }

        /// 快退快进中能不能跳到这里让画面跟上：片尾前 `endMargin` 以内不跳，跳过去会被当成播完。
        /// 触控板能把拖动位置拖进这一段，这时再按住右键，进度条停着不动，也不跳转，等用户确认或取消。
        static func canSeek(to position: Duration, runtime: Duration) -> Bool {
            position <= upperBound(runtime: runtime)
        }
    }

    /// 播放/暂停键和触控板中央。
    enum PlaybackButton {
        case playPause
        case select
    }

    enum PlaybackButtonAction: Equatable {
        /// 交给当前聚焦的控件（按钮、卡片）处理。
        case forwardToFocusedControl
        /// 从拖动或快退快进停下的位置播放。
        case commitScrub
        case play
        /// 暂停；控制条原本收起或只显示进度条时，呼出完整控制条。
        case pause(showsControls: Bool)
        case showControls
        case ignore
    }

    /// 播放/暂停键、触控板中央按下后怎么做。
    ///
    /// | 情况 | 播放/暂停键 | 触控板中央 |
    /// | --- | --- | --- |
    /// | 聚焦在画面上的操作按钮（如「跳过片头」） | 暂停/播放 | 按下这个按钮 |
    /// | 拖动或快退快进中 | 从新位置播放 | 从新位置播放 |
    /// | 控制条收起 | 暂停/播放 | 暂停/播放（不能控制播放时呼出控制条） |
    /// | 只显示进度条（跳转、轻触后），焦点可能还没落到进度条上 | 暂停/播放 | 暂停/播放 |
    /// | 聚焦在进度条 | 暂停/播放 | 暂停/播放 |
    /// | 聚焦在其他控件或面板 | 暂停/播放 | 交给聚焦的控件 |
    static func action(
        for button: PlaybackButton,
        presentation: Presentation,
        isScrubbing: Bool,
        isProgressBarFocused: Bool,
        isOverlayActionFocused: Bool,
        canControlPlayback: Bool,
        isPaused: Bool
    ) -> PlaybackButtonAction {
        if button == .select, isOverlayActionFocused {
            return .forwardToFocusedControl
        }

        if isScrubbing {
            return canControlPlayback ? .commitScrub : .ignore
        }

        let isHidden = presentation == .hidden
        // 只显示进度条时屏幕上没有别的可聚焦控件（「跳过片头」已在上面处理）。
        let hasOtherControls = !isHidden && presentation != .progress

        if button == .select, hasOtherControls, !isProgressBarFocused {
            return .forwardToFocusedControl
        }

        guard canControlPlayback else {
            return button == .select && isHidden ? .showControls : .ignore
        }

        if isPaused {
            return .play
        }

        return .pause(showsControls: isHidden || presentation == .progress)
    }
}
