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
#endif
