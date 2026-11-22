import SwiftUI

/// 订阅的搜索和下载规则：选项来源、摘要和设置行。订阅大面板和试看规则共用。
nonisolated enum SubscribeRuleChoices {
  static let quality = [
    (title: "全部", value: ""),
    (title: "蓝光原盘", value: "Blu-?Ray.+VC-?1|Blu-?Ray.+AVC|UHD.+blu-?ray.+HEVC|MiniBD"),
    (title: "Remux", value: "Remux"),
    (title: "蓝光", value: "Blu-?Ray"),
    (title: "UHD", value: "UHD|UltraHD"),
    (title: "WEB-DL", value: "WEB-?DL|WEB-?RIP"),
    (title: "HDTV", value: "HDTV"),
    (title: "H265", value: "[Hx].?265|HEVC"),
    (title: "H264", value: "[Hx].?264|AVC"),
  ]

  static let resolution = [
    (title: "全部", value: ""),
    (title: "4K", value: "4K|2160p|x2160"),
    (title: "1080P", value: "1080[pi]|x1080"),
    (title: "720P", value: "720[pi]|x720"),
  ]

  static let effect = [
    (title: "全部", value: ""),
    (title: "杜比视界", value: "Dolby[\\s.]+Vision|DOVI|[\\s.]+DV[\\s.]+"),
    (title: "杜比全景声", value: "Dolby[\\s.]*\\+?Atmos|Atmos"),
    (title: "HDR", value: "[\\s.]+HDR[\\s.]+|HDR10|HDR10\\+"),
    (title: "SDR", value: "[\\s.]+SDR[\\s.]+"),
  ]

  /// 与 `AddDownloadViewModel.targetDirectories` 同一套规范化：先 trim、再丢空、最后去重。
  static func savePaths(from directories: [TransferDirectoryConf]) -> [String] {
    var seen = Set<String>()
    return directories.compactMap {
      $0.download_path?.trimmingCharacters(in: .whitespacesAndNewlines)
    }.filter {
      !$0.isEmpty && seen.insert($0).inserted
    }
  }

  /// 站点摘要：不选表示使用默认站点；选了一个显示站点名，找不到名字或选了多个时显示数量。
  static func sitesSummary(
    _ ids: [Int]?, sites: [Site], empty: String = "默认", count: (Int) -> String = { "已选 \($0) 个" }
  ) -> String {
    let ids = ids ?? []
    if ids.isEmpty { return empty }
    if ids.count == 1, let site = sites.first(where: { $0.id == ids[0] }) { return site.name }
    return count(ids.count)
  }

  /// 规则组摘要：不选表示使用默认规则。
  static func filterGroupsSummary(_ groups: [String]?) -> String {
    let groups = groups ?? []
    if groups.isEmpty { return "默认" }
    return groups.count == 1 ? groups[0] : "已选 \(groups.count) 个"
  }
}

/// 设置行可选的值，来自 MoviePilot 的站点、下载器、目录和规则组配置。
struct SubscribeRuleOptions {
  var sites: [Site] = []
  var downloaders: [DownloaderConf] = []
  var savePaths: [String] = []
  var filterGroups: [FilterRuleGroup] = []
}

/// 一项搜索和下载规则的设置行；不是规则类的设置项不显示。
struct SubscribeRuleFieldRow: View {
  /// 订阅面板和试看规则都能编辑的设置项，按面板里的顺序。
  static let fields: [SubscribeSettingField] = [
    .quality, .resolution, .effect, .sites, .downloader, .savePath, .searchImdb, .keyword, .include, .exclude,
    .filterGroups, .customWords,
  ]

  let field: SubscribeSettingField
  @Binding var subscribe: Subscribe
  let options: SubscribeRuleOptions
  /// 质量、分辨率、特效不指定（存成空值）时那一项的名字。订阅面板里是「全部」；试看规则里空值表示沿用
  /// MoviePilot 默认订阅配置，和站点、下载器等行一样叫「默认」。
  var unspecifiedChoiceTitle = "全部"

  var body: some View {
    switch field {
    case .quality:
      choice(\.quality, SubscribeRuleChoices.quality)
    case .resolution:
      choice(\.resolution, SubscribeRuleChoices.resolution)
    case .effect:
      choice(\.effect, SubscribeRuleChoices.effect)
    case .sites:
      SheetMultiPicker(
        title: field.title,
        summary: SubscribeRuleChoices.sitesSummary(subscribe.sites, sites: options.sites),
        emptySelectionTitle: "默认站点", options: options.sites, id: \.id,
        selected: Binding(
          get: { Set(subscribe.sites ?? []) },
          set: { subscribe.sites = Array($0) }),
        label: { $0.name })
    case .downloader:
      SheetPicker(
        title: field.title, selection: optionalText(\.downloader),
        options: [PickerOption(title: "默认", value: "")]
          + options.downloaders.map { PickerOption(title: $0.name, value: $0.name) })
    case .savePath:
      SheetPicker(
        title: field.title, selection: optionalText(\.save_path),
        options: [PickerOption(title: "自动", value: "")]
          + options.savePaths.map { PickerOption(title: $0, value: $0) })
    case .searchImdb:
      Toggle(
        field.title,
        isOn: Binding(
          get: { (subscribe.search_imdbid ?? 0) == 1 },
          set: { subscribe.search_imdbid = $0 ? 1 : 0 }))
    case .keyword:
      SheetInlineTextField(title: field.title, text: optionalText(\.keyword))
    case .include:
      SheetInlineTextField(title: field.title, text: optionalText(\.include))
    case .exclude:
      SheetInlineTextField(title: field.title, text: optionalText(\.exclude))
    case .filterGroups:
      SheetMultiPicker(
        title: field.title, summary: SubscribeRuleChoices.filterGroupsSummary(subscribe.filter_groups),
        emptySelectionTitle: "默认规则", options: options.filterGroups, id: \.name,
        selected: Binding(
          get: { Set(subscribe.filter_groups ?? []) },
          set: { subscribe.filter_groups = Array($0) }),
        label: { $0.name })
    case .customWords:
      SheetInlineTextField(title: field.title, text: optionalText(\.custom_words))
    case .totalEpisode, .startEpisode, .subscribeMode, .episodeGroup, .season, .mediaCategory:
      EmptyView()
    }
  }

  /// 质量、分辨率、特效选不指定的那一项时保存空文本，与原订阅面板一致。
  private func choice(
    _ keyPath: WritableKeyPath<Subscribe, String?>, _ choices: [(title: String, value: String)]
  ) -> some View {
    SheetPicker(
      title: field.title,
      selection: Binding(get: { subscribe[keyPath: keyPath] ?? "" }, set: { subscribe[keyPath: keyPath] = $0 }),
      options: Self.choiceOptions(choices, unspecifiedTitle: unspecifiedChoiceTitle))
  }

  /// 选项列表，空值那一项改叫 `unspecifiedTitle`。
  static func choiceOptions(
    _ choices: [(title: String, value: String)], unspecifiedTitle: String
  ) -> [PickerOption<String>] {
    choices.map { PickerOption(title: $0.value.isEmpty ? unspecifiedTitle : $0.title, value: $0.value) }
  }

  /// 清空即恢复默认：空文本记为未指定。
  private func optionalText(_ keyPath: WritableKeyPath<Subscribe, String?>) -> Binding<String> {
    Binding(
      get: { subscribe[keyPath: keyPath] ?? "" },
      set: { subscribe[keyPath: keyPath] = $0.isEmpty ? nil : $0 })
  }
}
