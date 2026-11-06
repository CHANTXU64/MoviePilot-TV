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
  static let openInLibrary = "arrow.up.right.square"
  static let link = "link"
  static let filter = "line.3.horizontal.decrease.circle"
  static let filterActive = "line.3.horizontal.decrease.circle.fill"
  static let sortAscending = "chevron.up"
  static let sortDescending = "chevron.down"

  // MARK: 信息

  static let season = tv
  /// 集数、集数范围、剧集数。
  static let episodes = "list.number"
  /// 时间、日期（发布时间、首播日期、分享时间）。
  static let time = "clock"
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
  /// 正在加载（如详情页按季订阅按钮在等季信息）。
  static let loading = "ellipsis.circle"
  /// 对勾表示「是 / 已完成」：操作成功、已订阅、已勾选都用它（见 `subscribed`、`selected`）。
  static let success = "checkmark.circle.fill"
  static let failure = "xmark.circle.fill"
  /// 警告，也用于「没加载出来」这类可以重试的失败。
  static let warning = "exclamationmark.triangle.fill"
  /// 提示信息；和成功、失败、警告一样用实心。
  static let info = "info.circle.fill"
  static let empty = "tray"
  static let noComments = "text.bubble"
  static let noResults = "doc.text.magnifyingglass"

  // MARK: 控件

  /// 开关打开、多选已勾选：和操作成功同一个对勾。
  static let selected = success
  static let unselected = "circle"
  static let disclosure = "chevron.right"
  static let menuDisclosure = "chevron.up.chevron.down"
  static let arrowRight = "arrow.right"
}
