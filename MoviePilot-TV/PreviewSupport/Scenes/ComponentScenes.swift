#if DEBUG
import SwiftUI

/// 核心组件与通用状态场景：空状态、加载、卡片、选择器、通知、Sheet 表单行。
@MainActor
enum UIPreviewScenesComponents {
  static var section: UIPreviewSection {
    UIPreviewSection(
      id: "components",
      title: "核心组件",
      scenes: [
        .page(
          id: "component.emptyData",
          title: "空状态 · 带操作",
          note: "EmptyDataView：图标、标题、说明与操作按钮。"
        ) {
          EmptyDataView(
            title: "暂无订阅",
            systemImage: AppSymbol.empty,
            description: "去探索页看看有什么新内容吧。",
            actionTitle: "去探索"
          ) {}
        },
        .page(
          id: "component.emptyDataCompact",
          title: "空状态 · 无操作",
          note: "EmptyDataView：没有操作按钮时的布局与焦点兜底。"
        ) {
          EmptyDataView(
            title: "暂无下载任务",
            systemImage: AppSymbol.empty,
            description: "下载器里还没有任务。"
          )
        },
        .page(
          id: "component.emptyDataTitleOnly",
          title: "空状态 · 仅标题",
          note:
            "EmptyDataView 只给标题、不给描述和操作：内部仍放一个透明可聚焦占位，避免焦点直接跳走。"
        ) {
          EmptyDataView(title: "暂无内容")
        },
        .page(
          id: "component.emptyDataRetry",
          title: "空状态 · 带重试",
          note:
            "EmptyDataView 的“说明 + 重试”组合；首页/整理历史等页面目前各自手写错误块，没有复用这个带重试的空状态。"
        ) {
          EmptyDataView(
            title: "加载失败",
            systemImage: AppSymbol.warning,
            description: "网络连接失败，请检查网络后重试。",
            actionTitle: "重试"
          ) {}
        },
        .page(
          id: "component.loadingState",
          title: "首屏加载态",
          note:
            "项目没有骨架屏组件，首屏加载统一用 ProgressView + 文案；首页/推荐/探索/状态页的具体加载态见各自场景。"
        ) {
          VStack(spacing: 24) {
            ProgressView()
            Text("正在加载…")
              .font(.body)
              .foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        },
        .page(
          id: "component.errorStatusCard",
          title: "错误卡片",
          note:
            "详情页豆瓣讨论区与剧集货架共用的 ShelfStatusCard：加载失败、加载中、空内容三种同尺寸状态卡；失败卡下方的“重试”由所在行提供。"
        ) {
          VStack(spacing: 36) {
            HStack(spacing: 24) {
              ShelfStatusCard(
                status: .failed("短评加载失败"),
                size: CGSize(
                  width: DoubanDiscussionCard.cardWidth, height: DoubanDiscussionCard.cardHeight),
                emptyIcon: AppSymbol.noComments, failedEmphasis: true, focusStyle: .button)
              ShelfStatusCard(
                status: .loading("正在加载短评…"),
                size: CGSize(
                  width: DoubanDiscussionCard.cardWidth, height: DoubanDiscussionCard.cardHeight),
                emptyIcon: AppSymbol.noComments, failedEmphasis: true, focusStyle: .button)
              ShelfStatusCard(
                status: .empty("暂无短评"),
                size: CGSize(
                  width: DoubanDiscussionCard.cardWidth, height: DoubanDiscussionCard.cardHeight),
                emptyIcon: AppSymbol.noComments, failedEmphasis: true, focusStyle: .button)
            }
            Button("重试") {}
              .buttonStyle(.borderedProminent)
          }
          .padding(60)
        },
        .page(
          id: "component.continueWatchingCard",
          title: "继续观看卡片",
          note:
            "媒体库「继续观看」剧照卡：16:9 剧照、左下角播放图标与已播放进度条、季集角标，标题只有一行；对比有进度 / 无进度 / 长标题 / 无剧照。"
        ) {
          HStack(alignment: .top, spacing: 40) {
            ContinueWatchingCard(
              title: "边境信号", stillURL: nil, icon: AppSymbol.play, episodeText: "第 1 季第 7 集",
              progress: 0.62, loadsImage: false, action: {})
            ContinueWatchingCard(
              title: "荒原长路", stillURL: nil, icon: AppSymbol.play, progress: nil, loadsImage: false,
              action: {})
            ContinueWatchingCard(
              title: "这是一部标题很长很长、需要缩字号才能放下的剧集名称",
              stillURL: nil, icon: AppSymbol.play, episodeText: "第 12 季第 24 集", progress: 0.05,
              loadsImage: false, action: {})
            ContinueWatchingCard(
              title: "轨道边界", stillURL: nil, icon: nil, episodeText: "第 3 季第 2 集", loadsImage: false,
              action: {})
          }
          .padding(60)
        },
        .page(
          id: "component.loadingIndicators",
          title: "加载指示",
          note:
            "LoadingIndicators 的三种用法：LoadingIcon（图标位转圈，不改变按钮尺寸）、RowLoadingTail（货架行尾加载更多，占一张海报高度）、FirstLoadIndicator（页面/区块首次加载的居中裸转圈）。"
        ) {
          VStack(spacing: 48) {
            HStack(spacing: 40) {
              Button {} label: {
                Label("保存", systemImage: AppSymbol.save)
                  .labelStyle(.iconOnly)
              }
              Button {} label: {
                LoadingIcon(systemImage: AppSymbol.save, isLoading: true)
              }
              .accessibilityLabel("保存中")
              HStack(spacing: 12) {
                LoadingIcon(systemImage: AppSymbol.save, isLoading: true)
                Text("保存中")
              }
              .foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 60) {
              RowLoadingTail(height: 200)
              FirstLoadIndicator(minHeight: 200, maxHeight: nil)
            }
          }
          .padding(60)
        },
        .page(
          id: "component.playbackProgressBar",
          title: "已播放进度条",
          note: "试看与继续观看共用的细进度条：0%、35%、100% 三种取值，长度由所在文字槽决定。"
        ) {
          VStack(alignment: .leading, spacing: 40) {
            ForEach([0.0, 0.35, 1.0], id: \.self) { fraction in
              VStack(alignment: .leading, spacing: 10) {
                PlaybackProgressBar(fraction: fraction)
                  .frame(width: 320)
                Text("\(Int(fraction * 100))%")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
          }
          .padding(60)
        },
        .page(
          id: "component.buttonStates",
          title: "按钮 · 焦点与禁用",
          note:
            "tvOS 原生按钮的焦点高亮与禁用态并排展示：禁用按钮不接收焦点；长文案按钮需要在焦点放大后仍保持可读。进入场景后焦点会落在第一个可用按钮。"
        ) {
          UIPreviewButtonStatesDemo()
        },
        .page(
          id: "component.notificationWarning",
          title: "通知 · 警告",
          note: "Notification 警告提示（权限或连接状态异常时使用）。"
        ) {
          UIPreviewNotificationDemo(
            type: .warning,
            message: "当前账号权限不足，部分入口已隐藏。"
          )
        },
        .page(
          id: "component.notificationInfo",
          title: "通知 · 普通信息",
          note: "Notification 普通信息提示（无强调色的默认类型）。"
        ) {
          UIPreviewNotificationDemo(
            type: .info,
            message: "已切换到推荐货架：近期热门。"
          )
        },
        .page(
          id: "component.notificationLongText",
          title: "通知 · 超长文案",
          note:
            "超长通知没有行数上限，胶囊会随文本变宽；在窄屏/长中文下可能超出安全区。用于确认截断或换行策略是否需要产品侧补充。"
        ) {
          UIPreviewNotificationDemo(
            type: .error,
            message:
              "整理失败：目标磁盘空间不足，且源文件已被其他任务占用。请先清理目标存储、停止正在执行的下载任务，再回到整理历史重试。若问题仍然存在，请检查下载器与 MoviePilot 后端连接状态，并查看系统日志中的完整错误堆栈。"
          )
        },
        .page(
          id: "component.paginatorFailure",
          title: "分页器 · 连续失败",
          note:
            "真实 Paginator 第一页与后续两页都失败：网格保持空态，分页器记录 hasError / lastError，并在第 3 次失败后让全局显示“加载数据失败，请重试。”。预览默认通知在 5 秒后消失，底部状态区会保留分页器状态。",
          environment: UIPreviewEnvironment.standard,
          behaviors: [UIPreviewBehaviorKey.componentPaginator: .error(.networkTimeout)]
        ) {
          UIPreviewPaginatorFailureDemo()
        },
        .page(
          id: "component.mediaCards",
          title: "媒体卡片各种状态",
          note: "MediaCard：类型/评分角标、已订阅与更新进度、来源图标、查看更多卡片。"
        ) {
          ScrollView {
            HStack(alignment: .top, spacing: 24) {
              MediaCard(
                title: "流浪地球 2",
                typeText: "电影",
                ratingText: "8.3",
                bottomLeftText: "已入库",
                source: .tmdb,
                loadsImage: false
              )
              MediaCard(
                title: "漫长的季节",
                typeText: "电视剧",
                ratingText: "9.4",
                bottomLeftText: "已订阅",
                bottomLeftSecondaryText: "更新至 12 集",
                source: .douban,
                loadsImage: false
              )
              MediaCard(
                title: "沙丘 2",
                typeText: "电影",
                ratingText: "8.0",
                bottomLeftText: "未订阅",
                loadsImage: false
              )
              MoreCard(titleText: "查看全部", posterUrl: nil, loadsImage: false) {}
            }
            .padding(60)
          }
        },
        .page(
          id: "component.personCard",
          title: "演职员卡片",
          note: "PersonCard：人物头像、姓名与角色。"
        ) {
          ScrollView {
            HStack(spacing: 24) {
              PersonCard(
                person: UIPreviewFixtures.person(id: 1, name: "张颂文", character: "高启强"),
                width: PersonCard.imageSize.width,
                height: PersonCard.imageSize.height
              ) {}
              PersonCard(
                person: UIPreviewFixtures.person(id: 2, name: "辛爽", character: "导演"),
                width: PersonCard.imageSize.width,
                height: PersonCard.imageSize.height
              ) {}
            }
            .padding(60)
          }
        },
        .page(
          id: "component.shelfPicker",
          title: "货架选择器",
          note: "ShelfPicker：推荐/详情页顶部的胶囊分组选择。"
        ) {
          UIPreviewShelfPickerDemo()
        },
        .page(
          id: "component.sheetPickerRow",
          title: "Sheet 选择行",
          note: "SheetPicker：设置面板里的菜单选择行（点开是系统菜单）。"
        ) {
          UIPreviewSheetPickerDemo()
        },
        .page(
          id: "component.sheetTextField",
          title: "Sheet 输入行",
          note: "SheetTextField：设置面板里的文本输入行。"
        ) {
          UIPreviewSheetTextFieldDemo()
        },
        .page(
          id: "component.notificationSuccess",
          title: "通知 · 成功",
          note: "Notification 成功提示（订阅成功）。"
        ) {
          UIPreviewNotificationDemo(type: .success, message: "订阅成功")
        },
        .page(
          id: "component.notificationError",
          title: "通知 · 错误",
          note: "Notification 错误提示（加载失败）。"
        ) {
          UIPreviewNotificationDemo(type: .error, message: "加载数据失败，请重试。")
        },
      ]
    )
  }
}

private struct UIPreviewShelfPickerDemo: View {
  private struct Shelf: Identifiable {
    let id: String
    let title: String
  }

  private let shelves = [
    Shelf(id: "trending", title: "近期热门"),
    Shelf(id: "movie", title: "电影推荐"),
    Shelf(id: "tv", title: "剧集推荐"),
  ]
  @State private var selection: Shelf?

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      ShelfPicker(items: shelves, selection: $selection) { $0.title }
      Spacer()
    }
    .padding(60)
    .onAppear { selection = shelves.first }
  }
}

private struct UIPreviewSheetPickerDemo: View {
  private enum Field: String, CaseIterable {
    case downloader
    case site
    case quality
  }

  @State private var downloader = "qbittorrent"
  @State private var site = 0
  @State private var quality = "1080p"

  private let downloaders = [
    PickerOption(title: "qBittorrent", value: "qbittorrent"),
    PickerOption(title: "Transmission", value: "transmission"),
    PickerOption(title: "Aria2", value: "aria2"),
  ]
  private let sites = [
    PickerOption(title: "所有站点", value: 0),
    PickerOption(title: "馒头", value: 1, detail: "PT"),
    PickerOption(title: "红叶", value: 2, detail: "PT"),
  ]

  var body: some View {
    VStack(spacing: 20) {
      SheetPicker(title: "下载器", selection: $downloader, options: downloaders)
      SheetPicker(title: "站点", selection: $site, options: sites)
      SheetPicker(
        title: "清晰度",
        selection: $quality,
        options: [
          PickerOption(title: "1080p", value: "1080p"),
          PickerOption(title: "2160p", value: "2160p"),
        ]
      )
    }
    .padding(60)
  }
}

private struct UIPreviewSheetTextFieldDemo: View {
  @State private var tmdbID = ""
  @State private var keyword = ""

  var body: some View {
    VStack(spacing: 20) {
      SheetTextField(title: "TheMovieDb ID", placeholder: "输入 TMDB ID", text: $tmdbID)
      SheetTextField(title: "搜索关键词", placeholder: "输入关键词", text: $keyword)
    }
    .padding(60)
  }
}

private struct UIPreviewNotificationDemo: View {
  @EnvironmentObject private var notificationManager: NotificationManager
  private let type: NotificationType
  private let message: String

  init(type: NotificationType, message: String) {
    self.type = type
    self.message = message
  }

  var body: some View {
    Color.clear
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .onAppear {
        notificationManager.show(message: message, type: type, duration: 600)
      }
  }
}

/// 原生按钮焦点/禁用对照。禁用按钮不参与焦点链，焦点会直接落到可用按钮。
private struct UIPreviewButtonStatesDemo: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 48) {
      VStack(alignment: .leading, spacing: 12) {
        Text("焦点态 / 禁用态")
          .font(.headline)
        Text("禁用按钮不能聚焦；焦点放大后长标题仍应完整可读。")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      HStack(spacing: 48) {
        Button("可操作按钮") {}
          .buttonStyle(.borderedProminent)
        Button("禁用按钮") {}
          .buttonStyle(.bordered)
          .disabled(true)
      }

      Button("长文案按钮 · 确认删除这条整理记录并停止自动重试") {}
        .buttonStyle(.bordered)
    }
    .padding(80)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

/// 直接驱动真实 `Paginator`，连续制造 3 次失败以触达错误上限和全局通知。
@MainActor
private struct UIPreviewPaginatorFailureDemo: View {
  @StateObject private var paginator: Paginator<MediaInfo>
  @StateObject private var navigationCoordinator = ImageNavigationCoordinator()
  @State private var didStart = false

  init() {
    _paginator = StateObject(
      wrappedValue: Paginator<MediaInfo>(
        threshold: 8,
        fetcher: { _ in
          try await UIPreviewFixtures.componentPaginatorMedia()
        },
        processor: { items, newItems in
          let existing = Set(items.map(\.id))
          let additions = newItems.filter { !existing.contains($0.id) }
          guard !additions.isEmpty else { return false }
          items.append(contentsOf: additions)
          return true
        }
      )
    )
  }

  var body: some View {
    MediaGridView(
      imageLifecycle: navigationCoordinator.rootLifecycle,
      listIdentity: paginator.listIdentity,
      items: paginator.items,
      isLoading: paginator.isFirstLoading,
      isLoadingMore: paginator.isLoadingMore,
      onLoadMore: { id in
        Task { await paginator.loadMore(id) }
      },
      header: { statusHeader }
    )
    .environment(\.pageImageLifecycle, navigationCoordinator.rootLifecycle)
    .environmentObject(navigationCoordinator)
    .task {
      guard !didStart else { return }
      didStart = true
      await paginator.refresh()
      await paginator.loadMore(nil)
      await paginator.loadMore(nil)
    }
  }

  private var statusHeader: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Paginator · 连续失败")
        .font(.headline)
      HStack(spacing: 24) {
        statusLine("hasError", paginator.hasError ? "true" : "false")
        statusLine("hasMore", paginator.hasMore ? "true" : "false")
        statusLine("consecutiveErrorCount", "3")
      }
      if let error = paginator.lastError {
        Text("lastError：\(error.localizedDescription)")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Text("第 3 次失败后停止加载，并触发全局通知“加载数据失败，请重试。”。")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 8)
  }

  private func statusLine(_ name: String, _ value: String) -> some View {
    HStack(spacing: 6) {
      Text(name)
        .font(.system(.caption, design: .monospaced))
        .foregroundStyle(.secondary)
      Text(value)
        .font(.system(.caption, design: .monospaced))
        .foregroundStyle(.primary)
    }
  }
}
#endif
