#if DEBUG
import SwiftUI

/// 主 Tab 页面场景：首页、推荐、探索、搜索、状态。
///
/// 每个场景都渲染真实 `MainContentView`，只把接口数据换成 fixture；
/// 加载中 / 空 / 失败 / 无权限通过 `UIPreviewBackend` 的逐接口行为控制。
@MainActor
enum UIPreviewScenesTabs {
  static var section: UIPreviewSection {
    UIPreviewSection(
      id: "tabs",
      title: "主框架与一级页面",
      scenes: [
        // MARK: 首页
        .page(
          id: "home.dashboard",
          title: "首页 · 仪表盘（常规）",
          note: "媒体服务器最新入库 + 我的订阅，标准全权限用户。"
        ) {
          UIPreviewTabRootView(tab: .home)
        },
        .page(
          id: "home.loading",
          title: "首页 · 加载中",
          note: "媒体服务器最新入库接口挂起，页面保持骨架/加载态。",
          behaviors: [UIPreviewBehaviorKey.homeMediaServerLatest: .hang]
        ) {
          UIPreviewTabRootView(tab: .home)
        },
        .page(
          id: "home.empty",
          title: "首页 · 空数据",
          note: "没有媒体服务器、没有订阅，页面展示空状态。",
          behaviors: [
            UIPreviewBehaviorKey.homeMediaServers: .empty,
            UIPreviewBehaviorKey.homeMediaServerLatest: .empty,
            UIPreviewBehaviorKey.homeSubscriptions: .empty,
          ]
        ) {
          UIPreviewTabRootView(tab: .home)
        },
        .page(
          id: "home.failure",
          title: "首页 · 加载失败",
          note: "媒体服务器最新入库接口失败，页面展示错误与重试。",
          behaviors: [UIPreviewBehaviorKey.homeMediaServerLatest: .failure]
        ) {
          UIPreviewTabRootView(tab: .home)
        },
        .page(
          id: "home.noSubscriptionPermission",
          title: "首页 · 无订阅权限",
          note: "仅有发现权限的用户，订阅区块被隐藏或提示无权限。",
          environment: UIPreviewEnvironment.limited(permissions: Set([.discovery]))
        ) {
          UIPreviewTabRootView(tab: .home)
        },

        // MARK: 推荐
        .page(
          id: "recommend.shelves",
          title: "推荐 · 货架列表（常规）",
          note: "多组推荐货架按行渲染，可横向滚动。"
        ) {
          UIPreviewTabRootView(tab: .recommend)
        },
        .page(
          id: "recommend.loading",
          title: "推荐 · 加载中",
          note: "推荐接口挂起，首屏保持加载状态。",
          behaviors: [UIPreviewBehaviorKey.recommendMedia: .hang]
        ) {
          UIPreviewTabRootView(tab: .recommend)
        },
        .page(
          id: "recommend.empty",
          title: "推荐 · 空数据",
          note: "推荐接口返回空列表，货架展示空状态。",
          behaviors: [UIPreviewBehaviorKey.recommendMedia: .empty]
        ) {
          UIPreviewTabRootView(tab: .recommend)
        },
        .page(
          id: "recommend.failure",
          title: "推荐 · 加载失败",
          note: "推荐接口失败，货架展示错误与重试。",
          behaviors: [UIPreviewBehaviorKey.recommendMedia: .failure]
        ) {
          UIPreviewTabRootView(tab: .recommend)
        },
        .page(
          id: "recommend.loadingMore",
          title: "推荐 · 加载更多",
          note: "第一页已加载，第二页挂起，展示加载更多态。",
          behaviors: [UIPreviewBehaviorKey.recommendMore: .hang]
        ) {
          UIPreviewTabRootView(tab: .recommend)
        },

        // MARK: 探索
        .page(
          id: "explore.discover",
          title: "探索 · 发现列表（常规）",
          note: "默认数据源、来源切换与分页列表。"
        ) {
          UIPreviewTabRootView(tab: .explore)
        },
        .page(
          id: "explore.loading",
          title: "探索 · 加载中",
          note: "发现列表接口挂起。",
          behaviors: [UIPreviewBehaviorKey.recommendMedia: .hang]
        ) {
          UIPreviewTabRootView(tab: .explore)
        },
        .page(
          id: "explore.empty",
          title: "探索 · 空数据",
          note: "发现列表接口返回空列表。",
          behaviors: [UIPreviewBehaviorKey.recommendMedia: .empty]
        ) {
          UIPreviewTabRootView(tab: .explore)
        },
        .page(
          id: "explore.failure",
          title: "探索 · 加载失败",
          note: "发现列表接口失败。",
          behaviors: [UIPreviewBehaviorKey.recommendMedia: .failure]
        ) {
          UIPreviewTabRootView(tab: .explore)
        },
        .page(
          id: "explore.subscriptionShare",
          title: "探索 · 订阅分享",
          note: "订阅分享来源的列表，卡片带分享信息。"
        ) {
          UIPreviewTabRootView(tab: .explore)
        },
        .page(
          id: "explore.noDiscoveryPermission",
          title: "探索 · 无发现权限",
          note: "没有发现权限的用户，探索 Tab 不可见。",
          environment: UIPreviewEnvironment.limited(permissions: Set([.manage, .subscribe]))
        ) {
          UIPreviewTabRootView(tab: .home)
        },

        // MARK: 状态
        .page(
          id: "status.dashboard",
          title: "状态 · 仪表盘（常规）",
          note: "统计、存储、下载器概览全部有数据。"
        ) {
          UIPreviewTabRootView(tab: .status)
        },
        .page(
          id: "status.loading",
          title: "状态 · 加载中",
          note: "仪表盘三个接口全部挂起。",
          behaviors: [
            UIPreviewBehaviorKey.statusStatistic: .hang,
            UIPreviewBehaviorKey.statusStorage: .hang,
            UIPreviewBehaviorKey.statusDownloader: .hang,
          ]
        ) {
          UIPreviewTabRootView(tab: .status)
        },
        .page(
          id: "status.empty",
          title: "状态 · 空数据",
          note: "统计/存储/下载器均无数据。",
          behaviors: [
            UIPreviewBehaviorKey.statusStatistic: .empty,
            UIPreviewBehaviorKey.statusStorage: .empty,
            UIPreviewBehaviorKey.statusDownloader: .empty,
          ]
        ) {
          UIPreviewTabRootView(tab: .status)
        },
        .page(
          id: "status.failure",
          title: "状态 · 加载失败",
          note: "仪表盘接口失败，展示错误与重试。",
          behaviors: [
            UIPreviewBehaviorKey.statusStatistic: .failure,
            UIPreviewBehaviorKey.statusDownloader: .failure,
          ]
        ) {
          UIPreviewTabRootView(tab: .status)
        },
        .page(
          id: "status.noManagePermission",
          title: "状态 · 无管理权限",
          note: "没有管理权限的用户，状态 Tab 不可见。",
          environment: UIPreviewEnvironment.limited(permissions: Set([.discovery]))
        ) {
          UIPreviewTabRootView(tab: .home)
        },

        // MARK: 状态子区块（直接渲染子视图，便于单独走查）
        .page(
          id: "status.downloading",
          title: "状态 · 下载任务",
          note: "只渲染下载任务区块：客户端选择、进度、状态徽标。"
        ) {
          UIPreviewPageHost {
            ScrollView {
              DownloadTaskView(isSelected: true)
                .padding(60)
            }
          }
        },
        .page(
          id: "status.downloadingEmpty",
          title: "状态 · 下载任务为空",
          note: "没有下载任务时展示空状态。",
          behaviors: [UIPreviewBehaviorKey.downloadingItems: .empty]
        ) {
          UIPreviewPageHost {
            ScrollView {
              DownloadTaskView(isSelected: true)
                .padding(60)
            }
          }
        },
        .page(
          id: "status.downloadingFailure",
          title: "状态 · 下载任务失败",
          note: "下载任务接口失败时展示错误与重试。",
          behaviors: [UIPreviewBehaviorKey.downloadingItems: .failure]
        ) {
          UIPreviewPageHost {
            ScrollView {
              DownloadTaskView(isSelected: true)
                .padding(60)
            }
          }
        },
        .page(
          id: "status.transferHistory",
          title: "状态 · 整理历史",
          note: "整理历史列表：媒体信息、整理状态、批量操作入口。"
        ) {
          UIPreviewPageHost {
            ScrollView {
              TransferHistoryView(viewModel: TransferHistoryViewModel(), isSelected: true)
                .padding(60)
            }
          }
        },
        .page(
          id: "status.transferHistoryEmpty",
          title: "状态 · 整理历史为空",
          note: "没有整理记录时展示空状态。",
          behaviors: [UIPreviewBehaviorKey.transferHistory: .empty]
        ) {
          UIPreviewPageHost {
            ScrollView {
              TransferHistoryView(viewModel: TransferHistoryViewModel(), isSelected: true)
                .padding(60)
            }
          }
        },
        .page(
          id: "status.transferHistoryFailure",
          title: "状态 · 整理历史失败",
          note: "整理历史接口失败时展示错误与重试。",
          behaviors: [UIPreviewBehaviorKey.transferHistory: .failure]
        ) {
          UIPreviewPageHost {
            ScrollView {
              TransferHistoryView(viewModel: TransferHistoryViewModel(), isSelected: true)
                .padding(60)
            }
          }
        },
        .page(
          id: "status.manageOnly",
          title: "状态 · 仅管理权限",
          note: "非超级管理员只有 manage 权限：仪表盘概览隐藏，下载/整理仍可见。",
          environment: UIPreviewEnvironment.limited(permissions: Set([.manage]), superUser: false)
        ) {
          UIPreviewTabRootView(tab: .status)
        },

        // MARK: 设置入口
        .page(
          id: "system.root",
          title: "设置 · 根页面",
          note: "设置页入口列表（子页面在“设置”分区）。"
        ) {
          UIPreviewTabRootView(tab: .system)
        },
      ]
    )
  }
}
#endif
