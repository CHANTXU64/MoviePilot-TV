#if DEBUG
import Foundation
import SwiftUI

// 「播放器」预览分组。画面渲染的是真实的 VideoPlayer / PlaybackControls / 面板与菜单入口，
// 数据来自 PlayerFixtures 里的假会话；不启动 mpv 媒体流，也不访问媒体服务器。
// 场景 ID 统一以 player. 开头，注册进预览目录由 PreviewCatalogView 的维护方负责。

/// 播放器预览分组。
@MainActor
enum UIPreviewScenesPlayer {

  static var section: UIPreviewSection {
    UIPreviewSection(
      id: "player",
      title: "播放器",
      scenes: [
        scene(
          id: "player.loading",
          title: "起播加载中",
          note: "假会话处于起播前：activity = .loading、isReady = false。画面为黑场，时间旁显示「加载中」，工具栏按钮禁用；不加载真实媒体。",
          configuration: .loading,
          behaviors: [UIPreviewBehaviorKey.playerPlayback: .hang]
        ),
        scene(
          id: "player.failure",
          title: "起播失败",
          note: "模拟起播失败：状态为 .error，顶部 toast 使用线上失败文案。预览每 1.4 秒重放一次，避免默认 2 秒后消失。",
          configuration: .failed(message: "无法播放该影片，请检查与媒体服务器的网络连接"),
          behaviors: [UIPreviewBehaviorKey.playerFailure: .failure]
        ),
        scene(
          id: "player.playing.controls",
          title: "播放中 · 控件可见",
          note: "正常播放：位置 16:08 / 45:32，已选「简体中文 · ASS（内嵌）」与「国语 · DTS-HD MA 5.1」。视频画面来自 MPVUI，预览未加载流，因此为黑场；控件、章节刻度与面板入口照常渲染。",
          configuration: .playing,
          behaviors: [UIPreviewBehaviorKey.playerPlayback: .data]
        ),
        scene(
          id: "player.playing.hidden",
          title: "播放中 · 控件隐藏",
          note: "控件收起后的播放画面；预览在界面出现后主动收起控件，用于核对隐藏态。",
          configuration: {
            var value = UIPlayerPreviewConfiguration.playing
            value.hideControls = true
            return value
          }(),
          behaviors: [UIPreviewBehaviorKey.playerPlayback: .data]
        ),
        scene(
          id: "player.paused",
          title: "暂停",
          note: "暂停状态：时间旁显示暂停图标，播放按钮为继续。",
          configuration: .paused,
          behaviors: [UIPreviewBehaviorKey.playerPlayback: .data]
        ),
        scene(
          id: "player.scrubbing",
          title: "拖动进度 · 预览缩略图",
          note: "正在拖动进度条：显示章节刻度和本地生成的预览缩略图（PreviewImageProvider 的章节来源），没有网络图片请求。",
          configuration: .scrubbing,
          behaviors: [UIPreviewBehaviorKey.playerPlayback: .data]
        ),
        scene(
          id: "player.subtitles.menu",
          title: "字幕菜单 · 开启与选轨",
          note: "字幕菜单入口：字幕已开启并选中「简体中文 · ASS（内嵌）」，另有繁体中文、English PGS 与外挂 SRT。tvOS 原生菜单无法由预览代码自动展开，本场景把焦点停在「字幕」按钮。",
          configuration: {
            var value = UIPlayerPreviewConfiguration.playing
            value.focusAction = VideoPlayerActionButton.subtitles.rawValue
            return value
          }(),
          behaviors: [UIPreviewBehaviorKey.playerSubtitles: .data]
        ),
        scene(
          id: "player.subtitles.off",
          title: "字幕菜单 · 关闭",
          note: "在字幕菜单中关闭字幕后：字幕按钮变为关闭样式，字幕轨选择仍保留，重新开启时恢复。",
          configuration: {
            var value = UIPlayerPreviewConfiguration.subtitlesOff
            value.focusAction = VideoPlayerActionButton.subtitles.rawValue
            return value
          }(),
          behaviors: [UIPreviewBehaviorKey.playerSubtitles: .data]
        ),
        scene(
          id: "player.subtitles.offset",
          title: "字幕偏移",
          note: "字幕偏移调整面板（真实 PlaybackAdjustmentSupplement）：当前 -1.5 秒。面板由预览直接打开。",
          configuration: {
            var value = UIPlayerPreviewConfiguration.playing
            value.subtitleOffset = .milliseconds(-1_500)
            value.guest = .subtitleOffset
            return value
          }(),
          behaviors: [UIPreviewBehaviorKey.playerSubtitles: .data]
        ),
        scene(
          id: "player.subtitles.style",
          title: "字幕菜单 · 文本样式入口",
          note: "字幕文本样式列表和「开放字幕样式设置」都在字幕菜单内，需要手动按遥控器展开；本场景同样把焦点停在字幕按钮，记录样式入口所在位置。",
          configuration: {
            var value = UIPlayerPreviewConfiguration.playing
            value.focusAction = VideoPlayerActionButton.subtitles.rawValue
            return value
          }(),
          behaviors: [UIPreviewBehaviorKey.playerSubtitles: .data]
        ),
        scene(
          id: "player.audio.menu",
          title: "音轨菜单",
          note: "音轨菜单入口：已选「英语 · E-AC-3 5.1」，另有国语 DTS-HD 与国语 AAC 评论轨。tvOS 原生菜单需手动展开，本场景把焦点停在「音频」按钮。",
          configuration: {
            var value = UIPlayerPreviewConfiguration.playing
            value.selectedAudioIndex = 1
            value.focusAction = VideoPlayerActionButton.audio.rawValue
            return value
          }(),
          behaviors: [UIPreviewBehaviorKey.playerAudio: .data]
        ),
        scene(
          id: "player.audio.offset",
          title: "音频偏移",
          note: "音频偏移调整面板（真实 PlaybackAdjustmentSupplement）：当前 +0.25 秒，用于核对音画不同步时的调整界面。",
          configuration: {
            var value = UIPlayerPreviewConfiguration.playing
            value.audioOffset = .milliseconds(250)
            value.guest = .audioOffset
            return value
          }(),
          behaviors: [UIPreviewBehaviorKey.playerAudio: .data]
        ),
        scene(
          id: "player.chapters",
          title: "章节面板",
          note: "章节面板（真实 MediaChaptersSupplement）：五个章节，当前 16:08 落在「第二幕：轨道上的回声」。章节图未接真实地址，显示占位。",
          configuration: {
            var value = UIPlayerPreviewConfiguration.playing
            value.supplement = .chapters
            return value
          }(),
          behaviors: [UIPreviewBehaviorKey.playerChapters: .data]
        ),
        scene(
          id: "player.queue",
          title: "队列 · 下一集",
          note: "队列面板（真实 MediaQueueView）：本季五集，当前第七集；工具栏上一集/下一集按钮由队列提供。海报地址未接真实图片，显示占位。",
          configuration: {
            var value = UIPlayerPreviewConfiguration.playing
            value.supplement = .queue
            return value
          }(),
          behaviors: [UIPreviewBehaviorKey.playerQueue: .data]
        ),
        scene(
          id: "player.playbackSettings.menu",
          title: "播放设置菜单 · 版本",
          note: "播放设置菜单入口：两个可直连版本（4K HDR / 1080p），菜单内显示「版本」选择。MoviePilot-TV 只直连，不显示码率与分辨率。原生菜单需手动展开，本场景把焦点停在设置按钮。",
          configuration: {
            var value = UIPlayerPreviewConfiguration.playing
            value.focusAction = VideoPlayerActionButton.playbackSettings.rawValue
            return value
          }(),
          behaviors: [UIPreviewBehaviorKey.playerSettings: .data]
        ),
        scene(
          id: "player.speed",
          title: "播放速度",
          note: "倍速调整面板（真实 PlaybackAdjustmentSupplement.playbackSpeed）：当前 1.25×，预设 0.5×–2×，作用于假会话的播放速率。",
          configuration: {
            var value = UIPlayerPreviewConfiguration.playing
            value.rate = 1.25
            value.guest = .playbackSpeed
            return value
          }(),
          behaviors: [UIPreviewBehaviorKey.playerSpeed: .data]
        ),
        scene(
          id: "player.ended",
          title: "播放结束",
          note: "播放结束：位置到片尾 45:32、状态 .stopped、显示暂停图标。线上此时会退出播放器，预览为便于查看保留画面。",
          configuration: .ended,
          behaviors: [UIPreviewBehaviorKey.playerPlayback: .data]
        ),
        scene(
          id: "player.info",
          title: "简介 · 演职员",
          note: "简介面板（真实 MediaInfoSupplement）：简介、类型、评分、演职员来自 fixture 的 BaseItemDto；海报地址为空，显示占位。",
          configuration: {
            var value = UIPlayerPreviewConfiguration.playing
            value.supplement = .info
            return value
          }(),
          behaviors: [UIPreviewBehaviorKey.playerPlayback: .data]
        ),
      ] + bannerScenes + inPlayerErrorScenes + stateScenes
    )
  }

  // MARK: - A. 起播/解析失败提示

  /// 起播或解析失败时，`PlaybackPresentationModifier` 监听 `coordinator.failure`，用全局通知条
  /// （`NotificationType.error`）显示错误的 `errorDescription`。这些场景用真实首页做背景，
  /// 由 `UIPreviewBannerHost` 触发同一条通知，便于截图核对文案和截断。
  private static var bannerScenes: [UIPreviewScene] {
    [
      banner(
        id: "player.resolveError.notAllowed",
        title: "起播失败 · 仅管理员可用",
        note: "协调器判断当前账号不是管理员时直接抛 PlaybackError.notAllowed。背景为真实首页，顶部错误条取生产 errorDescription；检查「只有管理员账号可以在应用内播放」。",
        message: message(PlaybackError.notAllowed)),
      banner(
        id: "player.resolveError.backendTooOld",
        title: "起播失败 · 后端版本过低",
        note: "MoviePilot 版本低于应用内播放要求（或版本读不出）时抛 PlaybackError.backendTooOld；文案里带最低版本号，检查顶条是否完整显示。",
        message: message(PlaybackError.backendTooOld)),
      banner(
        id: "player.resolveError.disabledInSettings",
        title: "起播失败 · 设置中已关闭",
        note: "用户在设置里关掉应用内播放后起播，协调器抛 PlaybackError.disabledInSettings；检查提示「应用内播放已在设置中关闭」。",
        message: message(PlaybackError.disabledInSettings)),
      banner(
        id: "player.resolveError.noPlayableServer",
        title: "起播失败 · 没有可播放服务器",
        note: "MoviePilot 中没有已启用且填写了地址与密钥、支持应用内播放的媒体服务器；文案会列出目前支持的服务器类型。",
        message: message(PlaybackError.noPlayableServer)),
      banner(
        id: "player.resolveError.serverNotSupported",
        title: "起播失败 · 服务器类型不支持",
        note: "已知条目属于一台不支持应用内播放的服务器（例如尚未适配的 Jellyfin）时抛 PlaybackError.serverNotSupported；这里用「书房 Jellyfin」演示文案里的服务器名。",
        message: message(PlaybackError.serverNotSupported("书房 Jellyfin"))),
      banner(
        id: "player.resolveError.unreachableTransportSecurity",
        title: "起播失败 · 系统不允许 http 域名",
        note: "媒体服务器地址是 http 公网域名，ATS 拦截明文连接；PlaybackError.unreachable(transportSecurity: true) 提示改 https 或内网 IP。",
        message: message(PlaybackError.unreachable(server: "客厅 NAS", transportSecurity: true))),
      banner(
        id: "player.resolveError.unreachable",
        title: "起播失败 · 内外网都连不上",
        note: "连接器探测内网、外网地址都失败（离开内网、服务器关机等），且没有证书或回包类错误；PlaybackError.unreachable(transportSecurity: false) 的文案。",
        message: message(PlaybackError.unreachable(server: "客厅 NAS", transportSecurity: false))),
      banner(
        id: "player.resolveError.noServerUser",
        title: "起播失败 · 服务器没有可用用户",
        note: "地址能连上，但媒体服务器用户列表里没有匹配当前 MoviePilot 用户名或配置用户名的用户；PlaybackError.noServerUser。",
        message: message(PlaybackError.noServerUser(server: "客厅 NAS"))),
      banner(
        id: "player.resolveError.notFound",
        title: "起播失败 · 媒体库找不到条目",
        note: "详情页条目在各台可播放服务器上都没有按外部编号或 ID 兜底找到；PlaybackError.notFound，提示 MoviePilot 媒体库同步可能尚未更新。",
        message: message(PlaybackError.notFound)),
      banner(
        id: "player.resolveError.episodeMissingIdentity",
        title: "起播失败 · 缺少 TMDB 单集编号",
        note: "按集起播时 MoviePilot 集列表没有给出 TMDB 单集 ID，无法确认媒体服务器上对应哪一集；文案取自 EpisodeAvailability.UnidentifiableReason.missingEpisodeID。",
        message: message(PlaybackError.episodeUnavailable(
        EpisodeAvailability.UnidentifiableReason.missingEpisodeID.message))),
      banner(
        id: "player.resolveError.episodeGone",
        title: "起播失败 · 服务器上已无这一集",
        note: "按集起播时各台服务器都确认没有这一集（缓存重读后仍找不到）；文案取自 EpisodeAvailability.notOnServerMessage。播放中换集失败时「媒体服务器“…”上已经找不到这一集」是同类状态。",
        message: message(PlaybackError.episodeUnavailable(EpisodeAvailability.notOnServerMessage))),
      banner(
        id: "player.resolveError.unsupportedItemType",
        title: "起播失败 · 条目类型不支持",
        note: "服务器条目不是电影或剧集（如音乐、文件夹等）；PlaybackError.unsupportedItemType 提示应用内播放暂只支持电影和剧集。",
        message: message(PlaybackError.unsupportedItemType)),
      banner(
        id: "player.resolveError.noEpisodes",
        title: "起播失败 · 剧集没有可播放集",
        note: "整部剧起播时服务器上还没有任何一集带文件；PlaybackError.noEpisodes 提示这部剧在媒体服务器中还没有可播放的剧集。",
        message: message(PlaybackError.noEpisodes)),
      banner(
        id: "player.resolveError.unsupportedNoSource",
        title: "起播失败 · 没有可播放文件",
        note: "播放信息里没有可直连片源；PlaybackError.unsupported(.noSource) 的文案「媒体服务器没有返回可播放的文件」。",
        message: message(PlaybackError.unsupported(.noSource))),
      banner(
        id: "player.resolveError.unsupportedRemoteSource",
        title: "起播失败 · 远程链接片源",
        note: "片源是 strm 等远程链接，应用内播放只直连原文件；PlaybackError.unsupported(.remoteSource) 的说明。",
        message: message(PlaybackError.unsupported(.remoteSource))),
      banner(
        id: "player.resolveError.serverMessage",
        title: "起播失败 · 服务器拒绝播放",
        note: "Emby 播放信息返回 ErrorCode 且没有片源（这里用测试里的 NotAllowed）；PlaybackError.server 的文案会带出服务器名和服务器错误码。",
        message: message(PlaybackError.server("媒体服务器“客厅 Emby”拒绝播放：NotAllowed"))),
      banner(
        id: "player.mediaServerError.unreachable",
        title: "媒体服务器错误 · 连接失败",
        note: "MediaServerError(server: \"客厅 NAS\", operation: .connect, reason: .unreachable) 的错误描述；检查顶条同时给出服务器名、步骤和原因。",
        message: mediaServerMessage(.unreachable)),
      banner(
        id: "player.mediaServerError.transportSecurity",
        title: "媒体服务器错误 · http 被系统拦截",
        note: "连接阶段因系统不允许 http 域名而失败；MediaServerError 的 reason 为 .transportSecurity，提示改 https 或内网 IP。",
        message: mediaServerMessage(.transportSecurity)),
      banner(
        id: "player.mediaServerError.certificate",
        title: "媒体服务器错误 · 证书不受信任",
        note: "https 证书不受信任或加密连接建立失败；MediaServerError 的 reason 为 .certificate，提示换证书或改用内网地址。",
        message: mediaServerMessage(.certificate)),
      banner(
        id: "player.mediaServerError.unauthorized",
        title: "媒体服务器错误 · API Key 无效",
        note: "服务器返回 HTTP 401，不接受 MoviePilot 中配置的密钥；协调器会重读一次服务器配置，仍失败时把该错误交给用户。",
        message: mediaServerMessage(.unauthorized)),
      banner(
        id: "player.mediaServerError.forbidden",
        title: "媒体服务器错误 · 没有权限",
        note: "服务器返回 HTTP 403，密钥或所选用户没有权限；MediaServerError 的 reason 为 .forbidden。",
        message: mediaServerMessage(.forbidden)),
      banner(
        id: "player.mediaServerError.notFound",
        title: "媒体服务器错误 · 找不到（404）",
        note: "上报播放状态时服务器返回 HTTP 404；读取条目、集列表的 404 会被适配器当作“不在”，只有其他接口才把 .notFound 交给用户。",
        message: mediaServerMessage(.notFound, operation: .report)),
      banner(
        id: "player.mediaServerError.badRequest",
        title: "媒体服务器错误 · 请求不被接受",
        note: "服务器返回 HTTP 400（参数不支持、ID 格式不对等）；MediaServerError 的 reason 为 .badRequest，不被当作“条目不在”。",
        message: mediaServerMessage(.badRequest, operation: .readPlaybackInfo)),
      banner(
        id: "player.mediaServerError.serverError503",
        title: "媒体服务器错误 · 503 临时故障",
        note: "服务器或反向代理返回 5xx（这里 503）；不当作“条目不在”，协调器会先试已找到的其他副本，仍失败时提示稍后重试。",
        message: mediaServerMessage(.serverError(503), operation: .readPlaybackInfo)),
      banner(
        id: "player.mediaServerError.status429",
        title: "媒体服务器错误 · 429 限流",
        note: "未被专门分类的其他 HTTP 状态码（这里 429 限流）；MediaServerError 的 reason 为 .status(429)，文案带状态码。",
        message: mediaServerMessage(.status(429), operation: .search)),
      banner(
        id: "player.mediaServerError.invalidResponse",
        title: "媒体服务器错误 · 回包无法识别",
        note: "回包是反向代理登录页、地址不是媒体服务器或缺少字段；MediaServerError 的 reason 为 .invalidResponse。",
        message: mediaServerMessage(.invalidResponse, operation: .readItem)),
      banner(
        id: "player.mediaServerError.invalidURL",
        title: "媒体服务器错误 · 地址无效",
        note: "MoviePilot 中的服务器地址拼不成有效请求地址；MediaServerError 的 reason 为 .invalidURL。",
        message: mediaServerMessage(.invalidURL)),
      banner(
        id: "player.notice.nextEpisodeOnAnotherServer",
        title: "播放结束提示 · 下一集在另一台服务器",
        note: "播完一集且自动播放开启时，下一集只在另一台可播放服务器上，队列会停下并说明。PlaybackPresentationModifier 用 .info 通知条显示 coordinator.notice；检查文案与“回到详情页选择”的引导。",
        type: .info,
        message: UIPlayerPreviewMessages.nextEpisodeOnAnotherServer
      ),
    ]
  }

  private static func banner(
    id: String,
    title: String,
    note: String,
    type: NotificationType = .error,
    message: String
  ) -> UIPreviewScene {
    UIPreviewScene.page(id: id, title: title, note: note, environment: .playback) {
      UIPreviewBannerHost(type: type, message: message) {
        UIPreviewTabRootView(tab: .home)
      }
    }
  }

  private static func mediaServerMessage(
    _ reason: MediaServerError.Reason,
    operation: MediaServerError.Operation = .connect
  ) -> String {
    message(MediaServerError(server: "客厅 NAS", operation: operation, reason: reason))
  }

  private static func message(_ error: Error) -> String {
    (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
  }

  // MARK: - B. 播放界面内错误

  private static var inPlayerErrorScenes: [UIPreviewScene] {
    [
      scene(
        id: "player.error.mpvFatal",
        title: "播放错误 · mpv 致命错误",
        note: "mpv 致命失败时 PlaybackSession 把「无法播放该影片，请检查与媒体服务器的网络连接」交给协调器；线上随后结束播放并在首页弹错误条。本场景保留播放界面，把同一文案写进 MediaSession.commandError，走真实 VideoPlayer 的顶部 toast 链路。",
        configuration: {
          var value = UIPlayerPreviewConfiguration.playing
          value.commandError = UIPlayerPreviewMessages.mpvFailure
          return value
        }(),
        behaviors: [UIPreviewBehaviorKey.playerFailure: .data]
      ),
      scene(
        id: "player.error.seekFailed",
        title: "播放错误 · 跳转失败",
        note: "拖动跳转时 mpv 的 seek 失败，MediaSession.commandError 写入 L10n.unableToSeek（无法跳转。请重试。），VideoPlayer 观察 commandError 后显示顶部 toast；预览循环重放避免 2 秒后消失。",
        configuration: {
          var value = UIPlayerPreviewConfiguration.playing
          value.commandError = UIPlayerPreviewMessages.seekFailure
          return value
        }(),
        behaviors: [UIPreviewBehaviorKey.playerPlayback: .data]
      ),
      scene(
        id: "player.error.switchItemFailed",
        title: "播放错误 · 换集失败",
        note: "换集或换版本失败且当前条目还在播时，SwiftfinPlayerAdapter 把 PlaybackError 的 errorDescription 写进 commandError 显示在顶部；这里用 PlaybackError.notFound 的文案（未在媒体服务器中找到该条目…）。",
        configuration: {
          var value = UIPlayerPreviewConfiguration.playing
          value.commandError = UIPlayerPreviewMessages.switchItemFailure
          return value
        }(),
        behaviors: [UIPreviewBehaviorKey.playerPlayback: .data]
      ),
    ]
  }

  // MARK: - C. 播放状态补充

  private static var stateScenes: [UIPreviewScene] {
    [
      scene(
        id: "player.loadingItem",
        title: "换集加载中",
        note: "换集/换版本解析新条目期间 state = .loadingItem：标题仍是旧条目，activity = .loading，播放控件与进度条禁用；线上由 isSwitchingItem 分支进入。",
        configuration: .loadingItem,
        behaviors: [UIPreviewBehaviorKey.playerPlayback: .data]
      ),
      scene(
        id: "player.buffering",
        title: "缓冲中",
        note: "activity = .buffering 且 playbackState.isBuffering = true：时间旁显示缓冲指示器，控件保持可见（activity 非 nil 时不会自动收起）。",
        configuration: .buffering,
        behaviors: [UIPreviewBehaviorKey.playerPlayback: .data]
      ),
      scene(
        id: "player.seeking",
        title: "跳转中",
        note: "activity = .seeking：用于核对跳转期间控件不自动收起。当前 SplitTimestamp 只在 loading/buffering/暂停时画图标，播放中画面与普通播放接近；若需要可见的「跳转中」指示，要另加渲染。",
        configuration: .seeking,
        behaviors: [UIPreviewBehaviorKey.playerPlayback: .data]
      ),
      scene(
        id: "player.disabledControls",
        title: "控件禁用",
        note: "state 仍为 .playback 且没有 loading/error，但 canControlPlayback 与 canSeek 都是 false：进度条与 seek 手势应禁用，播放/暂停按键被 canControlPlayback 拦截；菜单仍可打开查看。用于核对不可控会话的灰态样式。",
        configuration: .disabledControls,
        behaviors: [UIPreviewBehaviorKey.playerPlayback: .data]
      ),
      scene(
        id: "player.noTracks",
        title: "无音轨 · 无字幕",
        note: "假轨道表里没有音轨和字幕：ActionButtons 过滤掉 .audio/.audioOffset/.subtitles/.subtitleOffset，工具栏菜单只剩倍速与播放设置；焦点停在工具栏「菜单」按钮。",
        configuration: {
          var value = UIPlayerPreviewConfiguration.noTracks
          value.focusAction = toolbarMenuFocusAction
          return value
        }(),
        behaviors: [
          UIPreviewBehaviorKey.playerAudio: .data,
          UIPreviewBehaviorKey.playerSubtitles: .data,
        ]
      ),
      scene(
        id: "player.singleVersion",
        title: "只有一个版本",
        note: "只有一个可直连版本（4K HDR）：PlaybackSettings.isAvailable 为 false，播放设置入口整体隐藏，菜单里因此没有「版本」选择；焦点停在工具栏「菜单」。对比 player.playbackSettings.menu（两个版本）。",
        configuration: {
          var value = UIPlayerPreviewConfiguration.singleVersion
          value.focusAction = toolbarMenuFocusAction
          return value
        }(),
        behaviors: [UIPreviewBehaviorKey.playerSettings: .data]
      ),
      scene(
        id: "player.noQueue",
        title: "无队列（剧集直接起播）",
        note: "按集条目但队列为 nil（整部剧直接起播、没有集列表上下文）：工具栏不显示自动播放、上一集、下一集，补充面板里也没有队列；焦点停在「菜单」。",
        configuration: {
          var value = UIPlayerPreviewConfiguration.noQueue
          value.focusAction = toolbarMenuFocusAction
          return value
        }(),
        behaviors: [UIPreviewBehaviorKey.playerQueue: .data]
      ),
      scene(
        id: "player.noChapters",
        title: "无章节",
        note: "BaseItemDto 没有章节：进度条不画章节刻度，viewState.supplements 里也没有章节面板。默认工具栏本来就不含上图/下图章节按钮（chapterCount < 2 时也会被过滤），检查重点是没有刻度与章节入口。",
        configuration: .noChapters,
        behaviors: [UIPreviewBehaviorKey.playerChapters: .data]
      ),
      scene(
        id: "player.longTitle",
        title: "超长标题",
        note: "超长剧名与集名：工具栏标题单行截断（TitleView 固定 lineLimit(1)），副标题为「第1季:7集」；检查不换行、不挤压右侧菜单按钮。",
        configuration: {
          var value = UIPlayerPreviewConfiguration.playing
          value.content = .longTitleEpisode
          return value
        }(),
        behaviors: [UIPreviewBehaviorKey.playerPlayback: .data]
      ),
      scene(
        id: "player.rateSlow",
        title: "倍速 · 0.5×",
        note: "播放速度 0.5×：直接打开倍速调整面板，滑块与预设停在最慢档，修改只写入假会话的 rate，不调用 mpv。",
        configuration: {
          var value = UIPlayerPreviewConfiguration.playing
          value.rate = 0.5
          value.guest = .playbackSpeed
          return value
        }(),
        behaviors: [UIPreviewBehaviorKey.playerSpeed: .data]
      ),
      scene(
        id: "player.rateFast",
        title: "倍速 · 2.0×",
        note: "播放速度 2.0×：打开倍速调整面板，检查最右侧预设与数值格式；修改只写入假会话的 rate。",
        configuration: {
          var value = UIPlayerPreviewConfiguration.playing
          value.rate = 2.0
          value.guest = .playbackSpeed
          return value
        }(),
        behaviors: [UIPreviewBehaviorKey.playerSpeed: .data]
      ),
      scene(
        id: "player.subtitleOffsetExtreme",
        title: "字幕偏移 +5 秒",
        note: "字幕偏移 +5 秒（PlaybackAdjustmentSupplement.offset 的范围上限 5000ms）：打开字幕偏移面板，检查滑块在最右端、数值格式与重置按钮；不触发 mpv 偏移。",
        configuration: {
          var value = UIPlayerPreviewConfiguration.playing
          value.subtitleOffset = .seconds(5)
          value.guest = .subtitleOffset
          return value
        }(),
        behaviors: [UIPreviewBehaviorKey.playerSubtitles: .data]
      ),
      scene(
        id: "player.movie",
        title: "电影播放",
        note: "电影条目：工具栏只显示片名，没有季集编号；队列为 nil，无上一集/下一集/自动播放与队列面板，章节、版本、音轨与字幕数据仍会构建。",
        configuration: .movie,
        behaviors: [UIPreviewBehaviorKey.playerPlayback: .data]
      ),
    ]
  }

  /// 工具栏溢出菜单按钮的焦点标识（见 `VideoPlayer+ActionButtons` 里的字面量 "menu"）。
  private static let toolbarMenuFocusAction = "menu"

  private static func scene(
    id: String,
    title: String,
    note: String,
    configuration: UIPlayerPreviewConfiguration,
    behaviors: [String: UIPreviewBackend.Behavior] = [:]
  ) -> UIPreviewScene {
    UIPreviewScene.page(
      id: id,
      title: title,
      note: note,
      environment: .playback,
      behaviors: behaviors
    ) {
      UIPreviewPageHost {
        UIPlayerPreviewHost(configuration: configuration)
      }
    }
  }
}

// MARK: - 预览宿主

private struct UIPlayerPreviewHost: View {
  let configuration: UIPlayerPreviewConfiguration

  @State private var box: UIPlayerPreviewBox?

  var body: some View {
    ZStack {
      Color.black

      if let box {
        VideoPlayer(mediaSession: box.session, previewViewState: box.viewState)
      }
    }
    .ignoresSafeArea()
    .onAppear {
      guard box == nil else { return }
      box = UIPlayerPreviewBox(configuration: configuration)
    }
    .task(id: box?.id) {
      guard let box else { return }
      try? await Task.sleep(for: .milliseconds(700))
      guard !Task.isCancelled else { return }
      box.applyAfterAppear()

      // 走真实 `VideoPlayer` 的 commandError 观察链路；每 1.4 秒重放一次，
      // 避免 toast 默认 2 秒后消失而截不到。先置 nil 再赋值，确保 onChange 每次都触发。
      if let commandError = box.configuration.commandError {
        while !Task.isCancelled {
          box.session.commandError = commandError
          try? await Task.sleep(for: .seconds(1.4))
          box.session.commandError = nil
          try? await Task.sleep(for: .milliseconds(100))
        }
      }

      guard let message = box.configuration.toast else { return }
      while !Task.isCancelled {
        box.viewState.toastProxy.present(message, systemName: AppSymbol.playbackError)
        try? await Task.sleep(for: .seconds(1.4))
      }
    }
  }
}

/// 预览会话与 ViewState 的组合。放在 `@State` 里，避免 SwiftUI 重求值时反复创建 mpv 播放器。
@MainActor
final class UIPlayerPreviewBox {
  let id = UUID()
  let configuration: UIPlayerPreviewConfiguration
  let session: MediaSession
  let viewState: VideoPlayer.ViewState

  init(configuration: UIPlayerPreviewConfiguration) {
    self.configuration = configuration

    let session = UIPlayerPreviewFixtures.makeSession(configuration: configuration)
    self.session = session

    let viewState = VideoPlayer.ViewState()
    self.viewState = viewState
    viewState.connect(mediaSession: session)
    session.start()
  }

  /// 等播放器容器出现后再补上拖动、面板、隐藏控件等状态。`VideoPlayer` 会在首次出现时
  /// 主动显示控件，因此这些状态不能提前设置。
  func applyAfterAppear() {
    if configuration.startScrubbing {
      viewState.beginScrub()
      if let target = configuration.scrubTarget {
        viewState.scrubbedSeconds = target
      }
    }

    if let supplement = configuration.supplement {
      switch supplement {
      case .info:
        viewState.selectedSupplementID = viewState.supplements
          .first(where: { $0.id.hasPrefix("MediaInfo-") })?.id
      case .chapters:
        viewState.selectedSupplementID = viewState.supplements
          .first(where: { $0.id.hasPrefix("Chapters-") })?.id
      case .queue:
        viewState.selectedSupplementID = viewState.supplements
          .first(where: { $0.id.hasPrefix("Queue-") })?.id
      }
    }

    if let guest = configuration.guest {
      switch guest {
      case .subtitleOffset:
        viewState.presentGuestSupplement(PlaybackAdjustmentSupplement.subtitleOffset)
      case .audioOffset:
        viewState.presentGuestSupplement(PlaybackAdjustmentSupplement.audioOffset)
      case .playbackSpeed:
        let range = session.player?.supportedRates ?? (0.5...2.0)
        viewState.presentGuestSupplement(PlaybackAdjustmentSupplement.playbackSpeed(range: range))
      }
    }

    if configuration.hideControls {
      viewState.hideControls()
    }

    if let action = configuration.focusAction {
      viewState.focusCoordinator.focus(VideoPlayer.ViewState.Focus.action(action))
    }
  }
}
#endif
