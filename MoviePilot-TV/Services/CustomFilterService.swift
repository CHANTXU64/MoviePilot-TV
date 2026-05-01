import Foundation
import SwiftDate

/// 自定义过滤服务
/// 移植自后端 filter.py 的核心筛选逻辑，在前端对搜索资源结果进行过滤。
enum CustomFilterService {

  /// 根据自定义规则过滤搜索结果
  /// - Parameters:
  ///   - contexts: 原始搜索结果
  ///   - rule: 用户选择的自定义过滤规则
  /// - Returns: 过滤后的搜索结果
  static func filter(contexts: [Context], with rule: CustomRule) -> [Context] {
    return contexts.filter { context in
      matchRule(context: context, rule: rule)
    }
  }

  /// 应用硬过滤+软过滤组合规则
  /// - Parameters:
  ///   - contexts: 原始搜索结果
  ///   - apiService: API 服务实例，用于获取规则详情
  ///   - caller: 调用方标识，用于日志区分
  /// - Returns: 过滤后的搜索结果（软过滤的不匹配项标记为 isFilteredOut 并置尾）
  static func applyHardAndSoftFilter(
    to contexts: [Context],
    using apiService: APIService,
    caller: String = ""
  ) async throws -> [Context] {
    let hardRuleId = SystemViewModel.currentSelectedHardFilterRuleId()
    let softRuleId = SystemViewModel.currentSelectedSoftFilterRuleId()

    guard hardRuleId != nil || softRuleId != nil else {
      return contexts
    }

    let rules = try await apiService.fetchCustomFilterRules()
    var finalContexts = contexts

    // 1. 应用硬过滤 (完全排除)
    if let hardId = hardRuleId, let hardRule = rules.first(where: { $0.id == hardId }) {
      let originalCount = finalContexts.count
      finalContexts = filter(contexts: finalContexts, with: hardRule)
      print("🔍 [\(caller)] 应用硬过滤规则「\(hardRule.name)」: \(originalCount) → \(finalContexts.count) 个资源")
    }

    // 2. 应用软过滤 (置尾变灰)
    if let softId = softRuleId, let softRule = rules.first(where: { $0.id == softId }) {
      var matched: [Context] = []
      var unmatched: [Context] = []
      for var ctx in finalContexts {
        if matchRule(context: ctx, rule: softRule) {
          matched.append(ctx)
        } else {
          ctx.isFilteredOut = true
          unmatched.append(ctx)
        }
      }
      print("🔍 [\(caller)] 应用软过滤规则「\(softRule.name)」: 命中 \(matched.count) 个资源，排除 \(unmatched.count) 个资源（置尾）")
      finalContexts = matched + unmatched
    }

    return finalContexts
  }

  /// 判断单个搜索结果是否匹配规则
  /// - 对应后端: filter.py __match_rule 方法
  static func matchRule(context: Context, rule: CustomRule) -> Bool {
    let torrent = context.torrent_info

    // 匹配项：标题 + 副标题 + 标签（与后端 content 逻辑一致）
    let title = torrent?.title ?? ""
    let desc = torrent?.description ?? ""
    let labels = (torrent?.labels ?? []).joined(separator: " ")
    let content = "\(title) \(desc) \(labels)"

    // 1. 包含规则：整个 include 字符串作为一个正则表达式匹配
    //    与后端一致: re.search(include, content, re.IGNORECASE)
    if let include = rule.include, !include.isEmpty {
      if let regex = try? NSRegularExpression(pattern: include, options: .caseInsensitive) {
        if regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)) == nil {
          print("🔍 [CustomFilter] 排除: \(title) — 不匹配包含规则 [\(include)]")
          return false
        }
      }
    }

    // 2. 排除规则：整个 exclude 字符串作为一个正则表达式匹配
    //    与后端一致: re.search(exclude, content, re.IGNORECASE)
    if let exclude = rule.exclude, !exclude.isEmpty {
      if let regex = try? NSRegularExpression(pattern: exclude, options: .caseInsensitive),
        regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)) != nil
      {
        print("🔍 [CustomFilter] 排除: \(title) — 匹配排除规则 [\(exclude)]")
        return false
      }
    }

    // 3. 大小范围规则 (单位: MB，按每集大小匹配)
    if let sizeRange = rule.size_range, !sizeRange.isEmpty {
      if !matchSize(context: context, sizeRange: sizeRange) {
        return false
      }
    }

    // 4. 做种人数规则
    if let seedersStr = rule.seeders, !seedersStr.isEmpty, let minSeeders = Int(seedersStr) {
      let currentSeeders = torrent?.seeders ?? 0
      if currentSeeders < minSeeders {
        print("🔍 [CustomFilter] 排除: \(title) — 做种人数 \(currentSeeders) < \(minSeeders)")
        return false
      }
    }

    // 5. 发布时间规则 (单位: 分钟)
    if let publishTime = rule.publish_time, !publishTime.isEmpty {
      if !matchPublishTime(torrent: torrent, publishTime: publishTime) {
        return false
      }
    }

    return true
  }

  // MARK: - 大小匹配

  /// 判断种子每集大小是否在指定范围内
  /// - 对应后端: filter.py __match_size（剧集拆分为每集大小）
  /// - size_range 单位: MB，torrent.size 单位: 字节
  /// - 与后端一致: 匹配成功返回 true，所有格式都不匹配则返回 false
  private static func matchSize(context: Context, sizeRange: String) -> Bool {
    guard let torrent = context.torrent_info else { return true }
    let title = torrent.title ?? ""
    let trimmed = sizeRange.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return true }

    // 集数：与后端一致，用 meta_info.total_episode，默认 1
    let episodeCount = max(context.meta_info?.total_episode ?? 1, 1)
    // 每集大小（字节）
    let perEpisodeSize = Double(torrent.size) / Double(episodeCount)

    if trimmed.contains("-") {
      // 区间格式: "min-max" (MB)
      let parts = trimmed.split(separator: "-")
        .map { String($0).trimmingCharacters(in: .whitespaces) }
      guard parts.count == 2,
        let minMB = Double(parts[0]),
        let maxMB = Double(parts[1])
      else { return false }
      let minBytes = minMB * 1024 * 1024
      let maxBytes = maxMB * 1024 * 1024
      if minBytes <= perEpisodeSize && perEpisodeSize <= maxBytes {
        return true
      }
    } else if trimmed.hasPrefix(">") {
      let valueStr = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
      guard let minMB = Double(valueStr) else { return false }
      if perEpisodeSize >= minMB * 1024 * 1024 {
        return true
      }
    } else if trimmed.hasPrefix("<") {
      let valueStr = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
      guard let maxMB = Double(valueStr) else { return false }
      if perEpisodeSize <= maxMB * 1024 * 1024 {
        return true
      }
    }

    print(
      "🔍 [CustomFilter] 排除: \(title) — 每集大小 \(Int64(perEpisodeSize).formattedBytes()) (\(episodeCount)集) 不匹配 \(sizeRange) MB"
    )
    return false
  }

  // MARK: - 发布时间匹配

  /// 判断种子发布时间是否在指定范围内
  /// - 对应后端: filter.py __match_rule 中 pubdate 逻辑
  /// - publish_time 单位: 分钟，torrent.pubdate 是日期字符串
  private static func matchPublishTime(torrent: TorrentInfo?, publishTime: String) -> Bool {
    guard let torrent = torrent else { return true }
    let title = torrent.title ?? ""

    // 解析 pubdate 字符串为 Date
    guard let pubdate = torrent.pubdate, !pubdate.isEmpty else {
      return true
    }

    // 尝试多种日期格式解析
    guard let pubMinutes = parsePubdateToMinutes(pubdate) else {
      print("🔍 [CustomFilter] 警告: 无法解析 pubdate: \(pubdate)")
      return true
    }

    // publish_time 单位是"分钟"，直接比较
    let parts = publishTime.split(separator: "-")
      .map { String($0).trimmingCharacters(in: .whitespaces) }
    if parts.count == 1 {
      // 单值: 发布时间必须 >= 该分钟数
      guard let minMinutes = Double(parts[0]) else { return true }
      if pubMinutes < minMinutes {
        print(
          "🔍 [CustomFilter] 排除: \(title) — 发布时间 \(String(format: "%.0f", pubMinutes)) 分钟 < \(minMinutes) 分钟"
        )
        return false
      }
    } else if parts.count == 2 {
      // 区间: 发布时间必须在 [min, max] 分钟范围内
      guard let minMinutes = Double(parts[0]), let maxMinutes = Double(parts[1]) else {
        return true
      }
      if pubMinutes < minMinutes || pubMinutes > maxMinutes {
        print(
          "🔍 [CustomFilter] 排除: \(title) — 发布时间 \(String(format: "%.0f", pubMinutes)) 分钟不在 \(minMinutes)-\(maxMinutes) 分钟范围"
        )
        return false
      }
    }

    return true
  }

  /// 将 pubdate 字符串解析为距今的分钟数
  /// 使用 SwiftDate 解析，与 Formatters.swift 中 toRelativeDateString() 保持一致
  private static func parsePubdateToMinutes(_ pubdate: String) -> Double? {
    let region = Region(zone: Zones.asiaShanghai)
    guard let date = Date(pubdate, region: region) else { return nil }
    return Date().timeIntervalSince(date) / 60.0
  }
}
