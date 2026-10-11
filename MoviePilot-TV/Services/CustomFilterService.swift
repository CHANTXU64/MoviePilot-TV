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
  nonisolated enum FilterError: Error, LocalizedError, Sendable {
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
    let prepared = PreparedResourceRule(ResourceRule(rule))
    let formatter = ResourceResultSemantics.dateFormatter()
    return try contexts.filter { context in
      try prepared.matches(ResourceFilterInput(context: context), formatter: formatter)
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
      Logger.debug("[\(caller)] 应用硬过滤规则「\(hardRule.name)」: \(originalCount) → \(finalContexts.count) 个资源")
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
      let prepared = PreparedResourceRule(ResourceRule(softRule))
      let formatter = ResourceResultSemantics.dateFormatter()
      var matched: [Context] = []
      var unmatched: [Context] = []
      for var ctx in finalContexts {
        if try prepared.matches(ResourceFilterInput(context: ctx), formatter: formatter) {
          matched.append(ctx)
        } else {
          ctx.isFilteredOut = true
          unmatched.append(ctx)
        }
      }
      Logger.debug("[\(caller)] 应用软过滤规则「\(softRule.name)」: 命中 \(matched.count) 个资源，排除 \(unmatched.count) 个资源（置尾）")
      finalContexts = matched + unmatched
    }

    return finalContexts
  }

  static func matchRule(context: Context, rule: CustomRule) throws -> Bool {
    try PreparedResourceRule(ResourceRule(rule)).matches(
      ResourceFilterInput(context: context), formatter: ResourceResultSemantics.dateFormatter())
  }
}

nonisolated struct ResourceRule: Equatable, Sendable {
  let missing: Bool
  let include: [String]
  let exclude: [String]
  let size: String?
  let seeders: String?
  let time: String?

  @MainActor init(_ rule: CustomRule?) {
    missing = rule == nil
    include = rule?.include ?? []
    exclude = rule?.exclude ?? []
    size = rule?.size_range
    seeders = rule?.seeders
    time = rule?.publish_time
  }
}

/// 新旧搜索共用的预编译规则；静态条件与相对时间拆开，供分页缓存分别失效。
nonisolated struct PreparedResourceRule: Sendable {
  let rule: ResourceRule
  let includes: [Result<NSRegularExpression?, CustomFilterService.FilterError>]
  let excludes: [Result<NSRegularExpression?, CustomFilterService.FilterError>]
  let size: Result<(Double, Double), CustomFilterService.FilterError>?
  let seeders: Result<Int, CustomFilterService.FilterError>?
  let time: Result<[Double], CustomFilterService.FilterError>?

  init(_ rule: ResourceRule) {
    self.rule = rule
    func regex(_ pattern: String) -> Result<NSRegularExpression?, CustomFilterService.FilterError> {
      if pattern.isEmpty { return .success(nil) }
      do { return .success(try NSRegularExpression(pattern: pattern, options: .caseInsensitive)) }
      catch { return .failure(.invalidRule("正则表达式「\(pattern)」无法编译")) }
    }
    includes = rule.include.map(regex)
    excludes = rule.exclude.map(regex)
    if let value = rule.size, !value.isEmpty {
      let trimmed = value.trimmingCharacters(in: .whitespaces)
      var range: (Double, Double)?
      if trimmed.contains("-") {
        let parts = trimmed.split(separator: "-", omittingEmptySubsequences: false)
        if parts.count == 2,
          let low = Double(parts[0].trimmingCharacters(in: .whitespaces)),
          let high = Double(parts[1].trimmingCharacters(in: .whitespaces)) { range = (low, high) }
      } else if trimmed.hasPrefix(">"), let low = Double(trimmed.dropFirst().trimmingCharacters(in: .whitespaces)) {
        range = (low, .infinity)
      } else if trimmed.hasPrefix("<"), let high = Double(trimmed.dropFirst().trimmingCharacters(in: .whitespaces)) {
        range = (-.infinity, high)
      } else if !trimmed.hasPrefix(">"), !trimmed.hasPrefix("<") {
        // 现有合同中的单值大小没有匹配分支，返回不匹配而非错误。
        range = (.infinity, -.infinity)
      }
      size = range.map { .success($0) } ?? .failure(.invalidRule("大小范围「\(value)」无法解析"))
    } else { size = nil }
    if let value = rule.seeders, !value.isEmpty {
      seeders = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)).map { .success($0) }
        ?? .failure(.invalidRule("做种人数「\(value)」无法解析"))
    } else { seeders = nil }
    if let value = rule.time, !value.isEmpty {
      let parts = value.split(separator: "-", omittingEmptySubsequences: false)
      let values = parts.compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
      time = values.count == parts.count && !values.isEmpty ? .success(values)
        : .failure(.invalidRule("发布时间「\(value)」无法解析"))
    } else { time = nil }
  }

  /// 单批调用与增量缓存共用判断；只有实际执行到该条件时才抛解析错误。
  func matches(_ input: ResourceFilterInput, formatter: DateFormatter) throws -> Bool {
    guard try matchesStatic(input) else { return false }
    let date = time == nil || input.pubdate.isEmpty ? nil : formatter.date(from: input.pubdate)
    return try matchesTime(date, hasTorrent: input.hasTorrent, now: Date())
  }

  func matchesStatic(_ input: ResourceFilterInput) throws -> Bool {
    if rule.missing { return false }
    let range = NSRange(input.content.startIndex..., in: input.content)
    func matches(_ regex: Result<NSRegularExpression?, CustomFilterService.FilterError>) throws -> Bool {
      guard let expression = try regex.get() else { return true }
      return expression.firstMatch(in: input.content, range: range) != nil
    }
    if !includes.isEmpty {
      var found = false
      for regex in includes {
        if try matches(regex) { found = true; break }
      }
      if !found { return false }
    }
    for regex in excludes {
      if try matches(regex) { return false }
    }
    if input.hasTorrent, let size {
      let (low, high) = try size.get()
      let value = Double(input.size) / Double(input.episodes)
      if !(low * 1024 * 1024 <= value && value <= high * 1024 * 1024) { return false }
    }
    if let seeders, input.seeders < (try seeders.get()) { return false }
    return true
  }

  func matchesTime(_ date: Date?, hasTorrent: Bool, now: Date) throws -> Bool {
    guard hasTorrent, let time else { return true }
    let limits = try time.get()
    let minutes = date.map { (now.timeIntervalSince($0) / 60).rounded(.down) } ?? 0
    if minutes < limits[0] { return false }
    return limits.count == 1 || !(minutes > limits[1])
  }
}
