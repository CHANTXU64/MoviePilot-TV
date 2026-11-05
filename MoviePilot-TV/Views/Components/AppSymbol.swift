/// 整个 App 使用的 SF Symbols 图标，全部从这里取。
///
/// 规则：同一个意思在所有地方（卡片、菜单、详情页、Sheet、状态页）只用一个图标；同一个图标只表示一个意思。
/// 卡片上看到的图标，点开的 Sheet 里也是同一个。新增图标先在这里加一项，不要在视图里直接写图标名。
nonisolated enum AppSymbol {
  // MARK: 底部标签页

  static let tabHome = "play.tv"
  static let tabRecommend = "sparkles.tv"
  static let tabExplore = "safari"
  static let tabSearch = search
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
  static let details = "info.circle"
  /// 订阅：订阅后会自动下载、可以观看，用加号表示「加进来」，不用爱心（容易误解成收藏）。
  static let subscribe = "plus.circle"
  static let unsubscribe = "minus.circle"
  /// 电视剧按季选择订阅。
  static let chooseSeasons = "list.bullet.circle"
  static let subscribed = "checkmark.circle.fill"
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
  static let allItems = "doc.on.doc"

  // MARK: 状态

  static let subscriptionActive = "dot.radiowaves.left.and.right"
  static let subscriptionPaused = pause
  static let subscriptionPending = "hourglass"
  static let success = "checkmark.circle.fill"
  static let failure = "xmark.circle.fill"
  static let warning = "exclamationmark.triangle.fill"
  static let info = "info.circle"
  static let empty = "tray"
  static let noComments = "text.bubble"
  static let noResults = "doc.text.magnifyingglass"

  // MARK: 控件

  static let selected = "checkmark.circle.fill"
  static let unselected = "circle"
  static let disclosure = "chevron.right"
  static let menuDisclosure = "chevron.up.chevron.down"
  static let arrowRight = "arrow.right"
}
