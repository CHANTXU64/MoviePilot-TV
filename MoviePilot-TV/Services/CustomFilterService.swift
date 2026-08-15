import Foundation

/// 自定义过滤服务
/// 移植自后端 filter.py 的核心筛选逻辑，在前端对搜索资源结果进行过滤。
/// 语义与后端 `app/modules/filter/__init__.py` 的 `__match_rule` 对齐：
/// - include/exclude 支持单个字符串或列表，任一正则匹配；
/// - seeders/publish_time 解析前忽略首尾空白（对齐 Python int()/float()）；
/// - pubdate 缺失或不可解析按 0 分钟处理（对齐后端 pub_minutes()）；
/// - 非法正则或数值显式失败，不静默放行（对齐后端抛异常）；
/// - 所选规则 ID 不存在时全部排除（对齐后端 rule_set.get 为空返回 False）。
enum CustomFilterService {

  /// 规则解析失败时抛出的错误；与后端非法规则抛异常的行为对齐。
  enum FilterError: Error, LocalizedError {
    case invalidRule(String)

    var errorDescription: String? {
      switch self {
      case .invalidRule(let detail):
        return "自定义过滤规则无效：\(detail)"
      }
    }
  }

  /// 根据自定义规则过滤搜索结果
  /// - Parameters:
  ///   - contexts: 原始搜索结果
  ///   - rule: 用户选择的自定义过滤规则
  /// - Returns: 过滤后的搜索结果
  static func filter(contexts: [Context], with rule: CustomRule) throws -> [Context] {
    return try contexts.filter { context in
      try matchRule(context: context, rule: rule)
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
    let hardRuleId = SystemViewModel.currentSelectedHardFilterRuleId(apiService: apiService)
    let softRuleId = SystemViewModel.currentSelectedSoftFilterRuleId(apiService: apiService)

    guard hardRuleId != nil || softRuleId != nil else {
      return contexts
    }

    guard apiService.canRequestSuperUserEndpoints else {
      return contexts
    }

    let rules = try await apiService.fetchCustomFilterRules()
    var finalContexts = contexts

    // 1. 应用硬过滤 (完全排除)
    if let hardId = hardRuleId {
      guard let hardRule = rules.first(where: { $0.id == hardId }) else {
        // 与后端 __match_rule 一致：规则不存在时所有资源都不匹配。
        return []
      }
      let originalCount = finalContexts.count
      finalContexts = try filter(contexts: finalContexts, with: hardRule)
      print("🔍 [\(caller)] 应用硬过滤规则「\(hardRule.name)」: \(originalCount) → \(finalContexts.count) 个资源")
    }

    // 2. 应用软过滤 (置尾变灰)
    if let softId = softRuleId {
      guard let softRule = rules.first(where: { $0.id == softId }) else {
        // 与后端 __match_rule 一致：规则不存在时所有资源都不匹配，全部置灰。
        return finalContexts.map { context in
          var context = context
          context.isFilteredOut = true
          return context
        }
      }
      var matched: [Context] = []
      var unmatched: [Context] = []
      for var ctx in finalContexts {
        if try matchRule(context: ctx, rule: softRule) {
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
  static func matchRule(context: Context, rule: CustomRule) throws -> Bool {
    let torrent = context.torrent_info

    // 匹配项：标题 + 副标题 + 标签（与后端 content 逻辑一致）
    let title = torrent?.title ?? ""
    let desc = torrent?.description ?? ""
    let labels = (torrent?.labels ?? []).joined(separator: " ")
    let content = "\(title) \(desc) \(labels)"

    // 1. 包含规则：任一 include 正则匹配 content 即通过（与后端 any(_regex_search) 一致）
    if let includes = rule.include, !includes.isEmpty {
      var matched = false
      for include in includes {
        if try regexMatches(pattern: include, content: content) {
          matched = true
          break
        }
      }
      if !matched {
        print("🔍 [CustomFilter] 排除: \(title) — 不匹配包含规则 \(includes)")
        return false
      }
    }

    // 2. 排除规则：任一 exclude 正则匹配 content 即排除
    if let excludes = rule.exclude {
      for exclude in excludes {
        if try regexMatches(pattern: exclude, content: content) {
          print("🔍 [CustomFilter] 排除: \(title) — 匹配排除规则 [\(exclude)]")
          return false
        }
      }
    }

    // 3. 大小范围规则 (单位: MB，按每集大小匹配)
    if let sizeRange = rule.size_range, !sizeRange.isEmpty {
      if try !matchSize(context: context, sizeRange: sizeRange) {
        return false
      }
    }

    // 4. 做种人数规则（对齐后端 int()：忽略首尾空白；非法值显式失败）
    if let seedersStr = rule.seeders, !seedersStr.isEmpty {
      let trimmedSeeders = seedersStr.trimmingCharacters(in: .whitespacesAndNewlines)
      guard let minSeeders = Int(trimmedSeeders) else {
        throw FilterError.invalidRule("做种人数「\(seedersStr)」无法解析")
      }
      let currentSeeders = torrent?.seeders ?? 0
      if currentSeeders < minSeeders {
        print("🔍 [CustomFilter] 排除: \(title) — 做种人数 \(currentSeeders) < \(minSeeders)")
        return false
      }
    }

    // 5. 发布时间规则 (单位: 分钟；pubdate 缺失或不可解析按 0 分钟处理)
    if let publishTime = rule.publish_time, !publishTime.isEmpty {
      if try !matchPublishTime(torrent: torrent, publishTime: publishTime) {
        return false
      }
    }

    return true
  }

  private static func regexMatches(pattern: String, content: String) throws -> Bool {
    // 与后端一致：空正则匹配一切（re.compile("").search 恒命中）。
    if pattern.isEmpty { return true }
    guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
      throw FilterError.invalidRule("正则表达式「\(pattern)」无法编译")
    }
    return regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)) != nil
  }

  // MARK: - 大小匹配

  /// 判断种子每集大小是否在指定范围内
  /// - 对应后端: filter.py __match_size（剧集拆分为每集大小）
  /// - size_range 单位: MB，torrent.size 单位: 字节
  /// - 与后端一致: 匹配成功返回 true，所有格式都不匹配则返回 false
  private static func matchSize(context: Context, sizeRange: String) throws -> Bool {
    guard let torrent = context.torrent_info else { return true }
    let title = torrent.title ?? ""
    let trimmed = sizeRange.trimmingCharacters(in: .whitespaces)

    // 集数：与后端一致，用 meta_info.total_episode，默认 1
    let episodeCount = max(context.meta_info?.total_episode ?? 1, 1)
    // 每集大小（字节）
    let perEpisodeSize = Double(torrent.size) / Double(episodeCount)

    if trimmed.contains("-") {
      // 区间格式: "min-max" (MB)
      // omittingEmptySubsequences: false 与后端 split("-") 一致（"-5"、"5-" 保留空段并失败）。
      let parts = trimmed.split(separator: "-", omittingEmptySubsequences: false)
        .map { String($0).trimmingCharacters(in: .whitespaces) }
      guard parts.count == 2,
        let minMB = Double(parts[0]),
        let maxMB = Double(parts[1])
      else {
        throw FilterError.invalidRule("大小范围「\(sizeRange)」无法解析")
      }
      let minBytes = minMB * 1024 * 1024
      let maxBytes = maxMB * 1024 * 1024
      if minBytes <= perEpisodeSize && perEpisodeSize <= maxBytes {
        return true
      }
    } else if trimmed.hasPrefix(">") {
      let valueStr = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
      guard let minMB = Double(valueStr) else {
        throw FilterError.invalidRule("大小范围「\(sizeRange)」无法解析")
      }
      if perEpisodeSize >= minMB * 1024 * 1024 {
        return true
      }
    } else if trimmed.hasPrefix("<") {
      let valueStr = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
      guard let maxMB = Double(valueStr) else {
        throw FilterError.invalidRule("大小范围「\(sizeRange)」无法解析")
      }
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
  private static func matchPublishTime(torrent: TorrentInfo?, publishTime: String) throws -> Bool {
    guard let torrent = torrent else { return true }
    let title = torrent.title ?? ""

    // 与后端 pub_minutes() 一致：pubdate 缺失或不可解析按 0 分钟处理。
    let pubMinutes: Double
    if let pubdate = torrent.pubdate, !pubdate.isEmpty,
      let parsed = parsePubdateToMinutes(pubdate)
    {
      pubMinutes = parsed
    } else {
      pubMinutes = 0
    }

    // 与后端 _parse_publish_time 一致：按 "-" 拆分逐段转浮点（忽略首尾空白），单值或区间。
    // omittingEmptySubsequences: false 与后端 split("-") 一致："-"、"-5"、"5-" 均保留空段并显式失败。
    let parts = publishTime.split(separator: "-", omittingEmptySubsequences: false)
      .map { String($0).trimmingCharacters(in: .whitespaces) }
    let minutes = try parts.map { part -> Double in
      guard let value = Double(part) else {
        throw FilterError.invalidRule("发布时间「\(publishTime)」无法解析")
      }
      return value
    }

    if minutes.count == 1 {
      // 单值: 发布时间必须 >= 该分钟数
      if pubMinutes < minutes[0] {
        print(
          "🔍 [CustomFilter] 排除: \(title) — 发布时间 \(String(format: "%.0f", pubMinutes)) 分钟 < \(minutes[0]) 分钟"
        )
        return false
      }
    } else {
      // 区间: 发布时间必须在 [min, max] 分钟范围内（与后端一致，取前两段）
      if pubMinutes < minutes[0] || pubMinutes > minutes[1] {
        print(
          "🔍 [CustomFilter] 排除: \(title) — 发布时间 \(String(format: "%.0f", pubMinutes)) 分钟不在 \(minutes[0])-\(minutes[1]) 分钟范围"
        )
        return false
      }
    }

    return true
  }

  /// 与后端 pub_minutes() 对齐：严格 "%Y-%m-%d %H:%M:%S" 格式，本地时区解析，向下取整分钟。
  private static func parsePubdateToMinutes(_ pubdate: String) -> Double? {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    guard let date = formatter.date(from: pubdate) else { return nil }
    return (Date().timeIntervalSince(date) / 60.0).rounded(.down)
  }
}
