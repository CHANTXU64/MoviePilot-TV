#if DEBUG
import SwiftUI

/// 单集操作面板、试看规则与试看进度场景。
///
/// 直接渲染真实的 `EpisodeActionSheet` / `EpisodeTrialRuleSheet` 与 `EpisodeCardStatusOverlay`，
/// 只用手工构造的 `EpisodeEntry` 表达不同状态，不发真实起播或下载。
@MainActor
enum UIPreviewScenesEpisode {
  static var section: UIPreviewSection {
    UIPreviewSection(
      id: "episode",
      title: "单集与试看",
      scenes: [
        .page(
          id: "episode.action.playable",
          title: "单集面板 · 可以播放",
          note: "应用内播放已确认这一集在「Emby · 客厅」上：面板给出「可以播放」与播放按钮。",
          environment: .playback
        ) {
          UIPreviewEpisodeActionScene(
            entry: EpisodeEntry(availability: .playable(server: "Emby · 客厅"), trialBlock: nil))
        },
        .page(
          id: "episode.action.trial",
          title: "单集面板 · 可以试看",
          note: "服务器上没有这一集、条件都满足：面板给出试看说明与「试看」按钮。",
          environment: .playback
        ) {
          UIPreviewEpisodeActionScene(
            entry: EpisodeEntry(availability: .notOnServer, trialBlock: nil))
        },
        .page(
          id: "episode.action.trialInProgress",
          title: "单集面板 · 试看下载中",
          note: "试看正在下载（42%），管理员可以取消：面板显示进度、说明与「取消试看」。",
          environment: .playback
        ) {
          UIPreviewEpisodeActionScene(
            entry: EpisodeEntry(
              availability: .notOnServer,
              trial: EpisodeTrialSnapshot(
                progress: .downloading(progress: 42, remainingSeconds: 300),
                subscriptionID: 88),
              trialBlock: nil,
              canCancelTrial: true))
        },
        .page(
          id: "episode.action.unmatched",
          title: "单集面板 · 可能已入库",
          note: "服务器上有认不出是哪一集的文件：面板先说明风险，按钮写「仍要播放」「仍要试看」。",
          environment: .playback
        ) {
          UIPreviewEpisodeActionScene(
            entry: EpisodeEntry(availability: .unmatched(server: "Emby · 客厅"), trialBlock: nil))
        },
        .page(
          id: "episode.action.plain",
          title: "单集面板 · 只能看简介",
          note: "应用内播放不可用（无权限/未开启）：面板只有单集简介，没有播放与试看按钮。"
        ) {
          UIPreviewEpisodeActionScene(
            entry: EpisodeEntry(availability: nil, trialBlock: .unsupported))
        },
        .page(
          id: "episode.trialRule.sheet",
          title: "试看订阅规则",
          note:
            "设置页「试看订阅规则」面板：站点、下载器、目录等选项从接口读取；这是系统 Sheet 的内容，预览按整页渲染。",
          environment: .playback
        ) {
          UIPreviewEpisodeTrialRuleScene()
        },
        .page(
          id: "episode.trialRule.loading",
          title: "试看订阅规则 · 读取选项",
          note: "站点接口挂起：保存按钮转圈、禁用，左栏说明仍在；已保存的规则值照常显示。",
          environment: .playback.with(behaviors: [
            UIPreviewBehaviorKey.searchSites: .hang
          ])
        ) {
          UIPreviewEpisodeTrialRuleScene()
        },
        .page(
          id: "episode.trialRule.failure",
          title: "试看订阅规则 · 选项读取失败",
          note: "站点接口失败：选项没加载完整，面板显示失败说明与「重试」，已保存的值不受影响。",
          environment: .playback.with(behaviors: [
            UIPreviewBehaviorKey.searchSites: .failure
          ])
        ) {
          UIPreviewEpisodeTrialRuleScene()
        },
        .page(
          id: "episode.trialNotice.manage",
          title: "试看提示 · 正在占用这一季",
          note: "管理本机试看订阅时按到季订阅/试看入口弹出的系统提示框：说明取消试看的后果，可取消或返回。",
          environment: .playback
        ) {
          UIPreviewEpisodeTrialNoticeScene()
        },
      ]
    )
  }
}

// MARK: - 单集面板

@MainActor
private struct UIPreviewEpisodeActionScene: View {
  let entry: EpisodeEntry

  private static let episode = MoviePilotEpisode(
    TmdbEpisode(
      id: 6_241_107,
      episodeNumber: 7,
      seasonNumber: 1,
      name: "第一束光",
      overview:
        "补给船在木星轨道附近失联七十二小时后，顾维在一次例行扫描里重新听到了它的信标。信号里没有求救，只有一段重复的、像是从更远处传来的呼吸声。",
      runtime: 46,
      voteAverage: 8.7
    ),
    season: 1,
    index: 6
  )

  var body: some View {
    UIPreviewSheetHost {
      EpisodeActionSheet(
        episode: Self.episode,
        seriesTitle: "边境信号",
        entry: entry,
        isCancellingTrial: false,
        isRechecking: false,
        onAction: { _ in }
      )
    }
  }
}

// MARK: - 试看规则

@MainActor
private struct UIPreviewEpisodeTrialRuleScene: View {
  private let api = APIService.shared

  var body: some View {
    UIPreviewSheetHost {
      EpisodeTrialRuleSheet(service: api.sessionScope.episodeTrial, apiService: api)
    }
  }
}

// MARK: - 剧照状态叠层

@MainActor
struct UIPreviewEpisodeCardOverlayGrid: View {
  private struct State {
    let label: String
    let status: EpisodeEntry.CardStatus?
    let runtimeText: String?
    let progress: Double?
  }

  private let states: [State] = [
    State(label: "可播放", status: .playable, runtimeText: "46 分钟", progress: 0.42),
    State(label: "可播放 · 未看", status: .playable, runtimeText: "46 分钟", progress: nil),
    State(label: "需要确认", status: .attention, runtimeText: nil, progress: nil),
    State(
      label: "搜索资源中",
      status: .trialInProgress(.init(label: "搜索资源中", fraction: nil, stage: .search)),
      runtimeText: nil, progress: nil),
    State(
      label: "下载 42%",
      status: .trialInProgress(.init(label: "下载中 42%", fraction: 0.42, stage: .download)),
      runtimeText: nil, progress: nil),
    State(
      label: "等待整理",
      status: .trialInProgress(.init(label: "等待整理", fraction: nil, stage: .organize)),
      runtimeText: nil, progress: nil),
    State(
      label: "等待入库",
      status: .trialInProgress(.init(label: "等待入库", fraction: nil, stage: .library)),
      runtimeText: nil, progress: nil),
    State(
      label: "正在取消试看",
      status: .trialInProgress(.init(label: "正在取消试看", fraction: nil, stage: nil)),
      runtimeText: nil, progress: nil),
    State(label: "不做状态叠层", status: nil, runtimeText: nil, progress: nil),
  ]

  private let columns = Array(repeating: GridItem(.fixed(360), spacing: 36), count: 4)

  var body: some View {
    ScrollView {
      LazyVGrid(columns: columns, spacing: 40) {
        ForEach(Array(states.enumerated()), id: \.offset) { _, state in
          VStack(spacing: 10) {
            still(status: state)
            Text(state.label)
              .font(.callout)
              .foregroundStyle(.secondary)
          }
        }
      }
      .padding(60)
    }
  }

  private func still(status: State) -> some View {
    RoundedRectangle(cornerRadius: EpisodeCardLayout.stillCornerRadius)
      .fill(
        LinearGradient(
          colors: [Color(white: 0.32), Color(white: 0.16)],
          startPoint: .topLeading, endPoint: .bottomTrailing)
      )
      .frame(width: 360, height: 203)
      .overlay {
        Image(systemName: AppSymbol.play)
          .font(.system(size: 40))
          .foregroundStyle(.white.opacity(0.18))
      }
      .overlay {
        if let overlayStatus = status.status {
          EpisodeCardStatusOverlay(
            status: overlayStatus,
            stillSize: CGSize(width: 360, height: 203),
            runtimeText: status.runtimeText,
            watchProgress: status.progress,
            isFocused: false)
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: EpisodeCardLayout.stillCornerRadius))
  }
}

// MARK: - 试看提示框

@MainActor
private struct UIPreviewEpisodeTrialNoticeScene: View {
  @State private var isPresented = true

  var body: some View {
    UIPreviewPageHost {
      VStack(spacing: 16) {
        Text("这一季正在试看")
          .font(.title2.bold())
        Text("管理试看订阅时按到订阅入口会弹出系统提示框；本场景在页面出现时自动弹出。")
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(AppBackground())
      .episodeTrialNotice(
        isPresented: $isPresented,
        context: .manage,
        isCancelling: false,
        canCancel: true,
        cancel: {}
      )
    }
  }
}
#endif
