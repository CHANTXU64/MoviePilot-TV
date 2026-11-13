/// 整个 App 使用的 SF Symbols 图标，全部从这里取。
///
/// 规则：同一个意思在所有地方（卡片、菜单、详情页、Sheet、状态页）只用一个图标；不同常量不写同一个图标名，
/// 也不写系统里互为别名的两个名字（如 `doc.on.doc` 与 `document.on.document`）。
/// 确实是同一个意思、只是出现在不同位置时，写成指向另一个常量的别名并注明理由（如 `season = tv`）。
/// 卡片上看到的图标，点开的 Sheet 里也是同一个。新增图标先在这里加一项，不要在视图里直接写图标名。
nonisolated enum AppSymbol {
  // MARK: 底部标签页

  static let tabHome = "play.tv"
  static let tabRecommend = "sparkles.tv"
  static let tabExplore = "safari"
  static let tabStatus = "slider.horizontal.3"
  static let tabSettings = "gear"

  // MARK: 媒体类型与分类

  static let movie = "film"
  /// 电视剧；季（含「1季 3集」这类季集合写）也用它。
  static let tv = "tv"
  static let collection = "rectangle.stack"
  static let person = "person.fill"
  /// 类型未知时的缺图占位。
  static let imagePlaceholder = "photo"
  static let allCategories = "square.grid.2x2"
  static let anime = "sparkles"
  static let chart = "chart.bar"
  static let otherCategory = "square.stack"

  // MARK: 操作

  static let search = "magnifyingglass"
  /// 打开详情（菜单项、按钮）。状态类的「提示信息」用实心的 `info`。
  static let details = "info.circle"
  /// 订阅：订阅后会自动下载、可以观看，用加号表示「加进来」，不用爱心（容易误解成收藏）。
  static let subscribe = "plus.circle"
  static let unsubscribe = "minus.circle"
  /// 电视剧按季选择订阅。
  static let chooseSeasons = "list.bullet.circle"
  /// 已订阅就是「已加进来」：和操作成功同一个对勾。
  static let subscribed = success
  static let forkSubscription = "document.on.document"
  static let editSubscription = "pencil"
  static let resetSubscription = "arrow.counterclockwise"
  static let pause = "pause.circle"
  static let resume = "play.circle"
  static let download = "arrow.down.circle"
  static let delete = "trash"
  static let retry = "arrow.clockwise"
  static let save = "checkmark"
  static let searchSubtitles = "captions.bubble"
  static let reorganize = "folder.badge.gearshape"
  static let aiReorganize = "wand.and.stars"
  /// 应用内播放影片；订阅的“恢复”用 `resume`，两者不混用。
  static let play = "play.fill"
  static let openInLibrary = "arrow.up.right.square"
  static let link = "link"
  static let filter = "line.3.horizontal.decrease.circle"
  static let filterActive = "line.3.horizontal.decrease.circle.fill"
  static let sortAscending = "chevron.up"
  static let sortDescending = "chevron.down"

  // MARK: 信息

  /// 季属于电视剧，和电视剧同一个图标。
  static let season = tv
  /// 集数、集数范围、剧集数。
  static let episodes = "list.number"
  /// 时间、日期（发布时间、首播日期、分享时间）。
  static let time = "clock"
  /// 时长（单集时长）。
  static let duration = "timer"
  static let size = "internaldrive"
  static let site = "globe"
  /// 搜索来源、媒体数据源。
  static let mediaSource = "server.rack"
  static let language = "character.bubble"
  static let rating = "star.fill"
  static let ratingHalf = "star.leadinghalf.filled"
  /// 下载数、下载速度；做种、上传用 `uploads`。
  static let downloads = "arrow.down"
  static let uploads = "arrow.up"
  static let transferTotal = "arrow.up.arrow.down"
  /// 复用次数这类热度。
  static let popularity = "flame"
  static let downloader = "square.and.arrow.down"
  static let resolution = "4k.tv"
  /// 订阅方式（洗版）。
  static let subscribeMode = "arrow.triangle.2.circlepath"
  static let progress = "checklist"
  static let transferMode = "arrow.right.doc.on.clipboard"
  static let account = "person.crop.circle"
  /// 整理预览里的「全部」合计。
  static let allItems = "sum"

  // MARK: 状态

  static let subscriptionActive = "dot.radiowaves.left.and.right"
  static let subscriptionPaused = pause
  static let subscriptionPending = "hourglass"
  /// 单集试看用的临时订阅。
  static let subscriptionTrial = "ticket"
  /// 正在加载（如详情页按季订阅按钮在等季信息）。
  static let loading = "ellipsis.circle"
  /// 对勾表示「是 / 已完成」。
  static let success = "checkmark.circle.fill"
  static let failure = "xmark.circle.fill"
  /// 警告，也用于「没加载出来」这类可以重试的失败。
  static let warning = "exclamationmark.triangle.fill"
  /// 提示信息；和成功、失败、警告一样用实心。
  static let info = "info.circle.fill"
  static let empty = "tray"
  static let noComments = "text.bubble"
  static let noResults = "doc.text.magnifyingglass"

  // MARK: 播放器（沿用 Swiftfin 播放界面的图标）

  static let playbackError = "exclamationmark.triangle"
  static let playbackPaused = pause
  /// 自动播放开、关：工具栏按钮和切换后的提示条用同一组。
  static let autoPlayOn = "play.circle.fill"
  static let autoPlayOff = "stop.circle"
  /// 跳过片头、片尾等片段；上一集、下一集用 `previousItem` / `nextItem`。
  static let skipSegment = "forward.end.alt.fill"
  static let nextItem = "forward.end.fill"
  static let previousItem = "backward.end.fill"
  static let nextChapter = "forward.frame.fill"
  static let previousChapter = "backward.frame.fill"
  /// 长按加速的倍率提示。
  static let speedBoost = "forward.fill"
  static let jumpForward = "goforward"
  static let jumpBackward = "gobackward"
  /// 音频、字幕偏移的增减。
  static let decrease = "minus"
  static let increase = "plus"
  /// 画面放大填满；放大后按钮换成 `aspectFit`，表示恢复原比例。
  static let aspectFill = "arrow.up.left.and.arrow.down.right"
  static let aspectFit = "arrow.down.right.and.arrow.up.left"
  static let audioTrack = "speaker.wave.2"
  static let audioOffset = "waveform.path"
  /// 已选字幕；没选字幕时用 `subtitlesOff`。
  static let subtitlesOn = "captions.bubble.fill"
  /// 没选字幕：和「搜索字幕」同一个图标，都表示字幕。
  static let subtitlesOff = searchSubtitles
  static let subtitleOffset = "textformat.abc"
  static let pictureInPicture = "pip.enter"
  static let exitPictureInPicture = "pip.exit"
  static let playbackSpeed = "speedometer"
  /// 播放设置：和设置页同一个齿轮。
  static let playbackSettings = tabSettings
  /// 更多播放操作；带圈的省略号已是 `loading`，这里用不带圈的。
  static let playerMenu = "ellipsis"
  static let closePlayer = "xmark"
  /// 收起播放器底部面板；`chevron.down` 已是 `sortDescending`。
  static let collapsePanel = "chevron.compact.down"
  /// 跳到系统设置等其他 App：和「跳转媒体库」同一个图标。
  static let openExternal = openInLibrary

  // MARK: 控件

  /// 开关打开、多选已勾选：和操作成功同一个对勾。
  static let selected = success
  static let unselected = "circle"
  static let disclosure = "chevron.right"
  static let menuDisclosure = "chevron.up.chevron.down"
  static let arrowRight = "arrow.right"
}
