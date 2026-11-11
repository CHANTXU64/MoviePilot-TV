import Foundation

/// 定义职位的数据结构，包含key和多语言翻译
struct JobDefinition {
  let key: String  // 英文key，作为唯一标识
  let translations: [AppLanguage: String]
}

/// 全局唯一的职位定义列表。
/// 数组的顺序代表了职位的显示优先级（越靠前，优先级越高）。
/// 这是项目中关于“职位”的单一数据源。
let prioritizedJobs: [JobDefinition] = [
  JobDefinition(
    key: "Director",
    translations: [.en: "Director", .zhHans: "导演", .zhHant: "導演"]),
  JobDefinition(
    key: "Writer",
    translations: [.en: "Writer", .zhHans: "编剧", .zhHant: "編劇"]),
  JobDefinition(
    key: "Screenplay",
    translations: [.en: "Screenplay", .zhHans: "剧本", .zhHant: "劇本"]),
  JobDefinition(
    key: "Story",
    translations: [.en: "Story", .zhHans: "故事", .zhHant: "故事"]),
  JobDefinition(
    key: "Novel",
    translations: [.en: "Novel", .zhHans: "小说", .zhHant: "小說"]),
  JobDefinition(
    key: "Producer",
    translations: [.en: "Producer", .zhHans: "制片人", .zhHant: "製片人"]),
  JobDefinition(
    key: "Executive Producer",
    translations: [.en: "Executive Producer", .zhHans: "执行制片人", .zhHant: "執行製片人"]),
  JobDefinition(
    key: "Director of Photography",
    translations: [.en: "Director of Photography", .zhHans: "摄影指导", .zhHant: "攝影指導"]),
  JobDefinition(
    key: "Cinematography",
    translations: [.en: "Cinematography", .zhHans: "摄影", .zhHant: "攝影"]),
  JobDefinition(
    key: "Camera",
    translations: [.en: "Camera", .zhHans: "摄影", .zhHant: "攝影"]),
  JobDefinition(
    key: "Editor",
    translations: [.en: "Editor", .zhHans: "剪辑", .zhHant: "剪輯"]),
  JobDefinition(
    key: "Production Design",
    translations: [.en: "Production Design", .zhHans: "艺术指导", .zhHant: "藝術指導"]),
  JobDefinition(
    key: "Art Direction",
    translations: [.en: "Art Direction", .zhHans: "美术指导", .zhHant: "美術指導"]),
  JobDefinition(
    key: "Art",
    translations: [.en: "Art", .zhHans: "艺术", .zhHant: "藝術"]),
  JobDefinition(
    key: "Set Decoration",
    translations: [.en: "Set Decoration", .zhHans: "布景师", .zhHant: "佈景師"]),
  JobDefinition(
    key: "Costume Design",
    translations: [.en: "Costume Design", .zhHans: "服装设计", .zhHant: "服裝設計"]),
  JobDefinition(
    key: "Makeup Artist",
    translations: [.en: "Makeup Artist", .zhHans: "化妆师", .zhHant: "化妝師"]),
  JobDefinition(
    key: "Original Music Composer",
    translations: [.en: "Original Music Composer", .zhHans: "原创音乐", .zhHant: "原創音樂"]),
  JobDefinition(
    key: "Music",
    translations: [.en: "Music", .zhHans: "音乐", .zhHant: "音樂"]),
  JobDefinition(
    key: "Sound",
    translations: [.en: "Sound", .zhHans: "音效", .zhHant: "音效"]),
  JobDefinition(
    key: "Visual Effects",
    translations: [.en: "Visual Effects", .zhHans: "视觉特效", .zhHant: "視覺特效"]),
  JobDefinition(
    key: "Visual Effects Supervisor",
    translations: [.en: "Visual Effects Supervisor", .zhHans: "视觉特效总监", .zhHant: "視覺特效總監"]),
  JobDefinition(
    key: "Animation",
    translations: [.en: "Animation", .zhHans: "动画", .zhHant: "動畫"]),
  JobDefinition(
    key: "Casting",
    translations: [.en: "Casting", .zhHans: "选角", .zhHant: "選角"]),
  JobDefinition(
    key: "Stunt Coordinator",
    translations: [.en: "Stunt Coordinator", .zhHans: "动作指导", .zhHant: "動作指導"]),
  JobDefinition(
    key: "Script Consultant",
    translations: [.en: "Script Consultant", .zhHans: "剧本顾问", .zhHant: "劇本顧問"]),
  JobDefinition(
    key: "Key Hair Stylist",
    translations: [.en: "Key Hair Stylist", .zhHans: "首席发型师", .zhHant: "首席髮型師"]),
  JobDefinition(
    key: "Sound Re-Recording Mixer",
    translations: [.en: "Sound Re-Recording Mixer", .zhHans: "混音", .zhHant: "混音"]),
  JobDefinition(
    key: "Supervising Sound Editor",
    translations: [.en: "Supervising Sound Editor", .zhHans: "声音剪辑指导", .zhHant: "聲音剪輯指導"]),
]

// 以下为根据 prioritizedJobs 派生的便利字典，用于快速查找

/// 英文职位key到多语言翻译的映射
let jobTranslationMap: [String: [AppLanguage: String]] = Dictionary(
  uniqueKeysWithValues: prioritizedJobs.map { ($0.key, $0.translations) })

/// 英文职位key到其优先级的映射
let jobPriorityMap: [String: Int] = Dictionary(
  uniqueKeysWithValues: prioritizedJobs.enumerated().map { index, job in (job.key, index) })

// MARK: - 职位 key 规范化

/// 小写形式到 canonical key 的索引，用于大小写不敏感的职位解析。
private let jobCanonicalKeyIndex: [String: String] = Dictionary(
  uniqueKeysWithValues: prioritizedJobs.map { ($0.key.lowercased(), $0.key) })

/// 将单个职位 token 解析为 `prioritizedJobs` 中的 canonical key。
///
/// 依次尝试：清理空白与换行 → 精确匹配 → 大小写不敏感匹配。
/// 无法识别时**原样保真**返回（调用方按未知职位处理，不在解析层丢弃上游信息）。
/// - Returns: 规范化后的 canonical key；输入全为空白时返回空串。
func canonicalJobKey(for token: String) -> String {
  let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
  if trimmed.isEmpty {
    return ""
  }
  if jobPriorityMap[trimmed] != nil {
    return trimmed
  }
  return jobCanonicalKeyIndex[trimmed.lowercased()] ?? trimmed
}

/// 将 `"/"` 分隔的多职位文本解析为 canonical key 列表。
///
/// 逐项清理空白/换行、丢弃空段，并在**规范化之后**去重（保留首次出现顺序），
/// 供翻译与优先级排序共用同一套 key，避免两者对同一字符串得出不同结论。
func canonicalJobKeys(from raw: String) -> [String] {
  var seen = Set<String>()
  var keys: [String] = []
  for token in raw.components(separatedBy: "/") {
    let key = canonicalJobKey(for: token)
    if key.isEmpty || !seen.insert(key).inserted {
      continue
    }
    keys.append(key)
  }
  return keys
}
