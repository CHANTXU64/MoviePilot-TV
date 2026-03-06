import Foundation

struct ParsedSeason {
  let original: String
  let seasonNum: Int
  let episodeNum: Int
  let maxEpisodeNum: Int
  let isWholeSeason: Bool
  let index: Int

  // 正则表达式解释:
  // ^S(\d+)       -> 匹配以 S 开头的季号，后面跟数字
  // (?:-S(\d+))?  -> 可选的季号范围（如 S01-S02）
  // \s*           -> 可选的空格
  // (?:E(\d+)(?:-E(\d+))?)? -> 可选的集号或集号范围（如 E01 或 E01-E02）
  // 静态缓存正则表达式，避免在 map 循环中重复编译，提升性能
  private static let seasonRegex: NSRegularExpression? = {
    let pattern = #"^S(\d+)(?:-S(\d+))?\s*(?:E(\d+)(?:-E(\d+))?)?$"#
    return try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
  }()

  /// 初始化方法：解析输入的剧集字符串（如 S01, S01E01-E02）
  init(original: String, index: Int) {
    self.original = original
    self.index = index

    // 默认值
    var seasonNum = 0
    var episodeNum = 0
    var maxEpisodeNum = 0
    var isWholeSeason = false

    if let regex = Self.seasonRegex,
       let match = regex.firstMatch(in: original, options: [], range: NSRange(location: 0, length: original.utf16.count)) {

      // 提取季号数字
      if let sRange = Range(match.range(at: 1), in: original),
         let s = Int(original[sRange]) {
        seasonNum = s
      }

      // 提取起始集号（如果存在 E 标记）
      if match.range(at: 3).location != NSNotFound,
         let eRange = Range(match.range(at: 3), in: original),
         let e = Int(original[eRange]) {
        episodeNum = e

        // 提取结束集号（处理范围，如 E01-E02 中的 02）
        if match.range(at: 4).location != NSNotFound,
           let maxERange = Range(match.range(at: 4), in: original),
           let maxE = Int(original[maxERange]) {
          maxEpisodeNum = maxE
        } else {
          maxEpisodeNum = episodeNum
        }
        isWholeSeason = false // 既然有集号，说明不是整季
      } else {
        isWholeSeason = true  // 只有季号，标记为整季
      }
    }

    self.seasonNum = seasonNum
    self.episodeNum = episodeNum
    self.maxEpisodeNum = maxEpisodeNum
    self.isWholeSeason = isWholeSeason
  }

  // 保留成员初始化方法，用于内部逻辑或特殊需求
  internal init(original: String, seasonNum: Int, episodeNum: Int, maxEpisodeNum: Int, isWholeSeason: Bool, index: Int) {
    self.original = original
    self.seasonNum = seasonNum
    self.episodeNum = episodeNum
    self.maxEpisodeNum = maxEpisodeNum
    self.isWholeSeason = isWholeSeason
    self.index = index
  }

  /// 核心逻辑：对后端返回的季/集选项进行自定义排序
  /// 排序目标：通常是倒序显示，即最新的季或集排在前面
  static func sortSeasonOptions(_ options: [String]) -> [String] {
    if options.count <= 1 { return options }

    // 先将所有字符串解析为结构体并记录原始索引，保证稳定排序
    let parsedOptions: [ParsedSeason] = options.enumerated().map { (index, option) in
      return ParsedSeason(original: option, index: index)
    }

    // 分离整季和具体集号，分别排序后再合并
    let wholeSeasons = parsedOptions.filter { $0.isWholeSeason }
    let episodes = parsedOptions.filter { !$0.isWholeSeason }

    // 1. 整季排序逻辑：按季号降序排列（大季号在前）
    let sortedWhole = wholeSeasons.sorted { a, b in
      if a.seasonNum != b.seasonNum {
        return b.seasonNum < a.seasonNum  // 降序
      }
      return a.index < b.index // 季号相同时按原序
    }

    // 2. 具体集号排序逻辑
    let sortedEpisodes = episodes.sorted { a, b in
      // 优先按季号降序
      if a.seasonNum != b.seasonNum {
        return b.seasonNum < a.seasonNum  // 降序
      }

      // 季号相同时，取结束集号进行降序比较
      let aMaxEp = a.maxEpisodeNum > 0 ? a.maxEpisodeNum : a.episodeNum
      let bMaxEp = b.maxEpisodeNum > 0 ? b.maxEpisodeNum : b.episodeNum

      if aMaxEp != bMaxEp {
        return bMaxEp < aMaxEp  // 结束集号较大的排在前面
      }

      // 结束集号也相同时，按起始集号降序
      if a.episodeNum != b.episodeNum {
        return b.episodeNum < a.episodeNum  // 降序
      }
      return a.index < b.index // 全部相同时按原序
    }

    // 最后合并结果，整季通常排在具体集的前面或后面（取决于业务喜好，这里是整季在前）
    return (sortedWhole + sortedEpisodes).map { $0.original }
  }
}
