import Combine
import Foundation

/// 设置页「试看订阅规则」的编辑草稿。打开时从当前账号保存的规则生成，按「保存」才写回；按 Menu 关掉不保存。
@MainActor
final class EpisodeTrialRuleViewModel: ObservableObject {
  // 显式非隔离析构，避开 tvOS 18 的隔离析构回部署崩溃。
  nonisolated deinit {}

  static let fields = SubscribeRuleFieldRow.fields
  /// 质量、分辨率、特效不指定时沿用 MoviePilot 默认订阅配置，和站点、下载器等行一样叫「默认」。
  static let unspecifiedChoiceTitle = "默认"

  /// 借用订阅模型承载表单，设置行和订阅大面板共用；只用到规则类字段。
  @Published var draft: Subscribe
  @Published private(set) var options = SubscribeRuleOptions()
  @Published private(set) var isLoading = false
  @Published private(set) var loadErrorMessage: String?
  @Published private(set) var saveErrorMessage: String?

  private let service: EpisodeTrialService
  private let apiService: APIService

  init(service: EpisodeTrialService, apiService: APIService) {
    var draft = Subscribe(id: nil, name: "试看规则", type: "电视剧")
    service.rule.apply(to: &draft)
    self.draft = draft
    self.service = service
    self.apiService = apiService
  }

  /// 读取站点、下载器、目录和规则组作为可选值。失败时已保存的值照样保留，可以重试。
  func load() async {
    guard !isLoading else { return }
    isLoading = true
    defer { isLoading = false }
    loadErrorMessage = nil
    let session = apiService.sessionSnapshot()
    do {
      async let sites = apiService.fetchSites()
      async let downloaders = apiService.fetchDownloadClients()
      async let directories = apiService.fetchDirectories()
      async let filterGroups = apiService.fetchFilterRuleGroups()
      let loaded = try await (sites, downloaders, directories, filterGroups)
      guard apiService.isSessionUnchanged(from: session) else { return }
      options = SubscribeRuleOptions(
        sites: loaded.0.filter { $0.is_active?.value == true }, downloaders: loaded.1,
        savePaths: SubscribeRuleChoices.savePaths(from: loaded.2), filterGroups: loaded.3)
    } catch is CancellationError {
      return
    } catch {
      guard apiService.isSessionUnchanged(from: session) else { return }
      Logger.error("加载试看规则选项失败: \(error)")
      loadErrorMessage = "试看订阅规则的选项没有加载完整，请重试。"
    }
  }

  /// 返回是否已保存。服务随账号拆除后不会写入，避免存到另一个账号下。
  func save() -> Bool {
    saveErrorMessage = nil
    do {
      try service.saveRule(EpisodeTrialRule(settingsOf: draft))
      return true
    } catch {
      saveErrorMessage = "试看订阅规则没有保存，请关闭后重新打开。"
      return false
    }
  }
}
