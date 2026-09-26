import Foundation

nonisolated struct MediaIdentity: Hashable {
  let source: String
  let mediaId: String

  var mediaKey: String {
    "\(source == "themoviedb" ? "tmdb" : source):\(mediaId)"
  }
}

nonisolated enum MediaIdentifier {
  private static let builtInSources = ["themoviedb", "douban", "bangumi", "anilist"]

  static func normalizeSource(_ source: String?) -> String? {
    guard let source = normalizedString(source)?.lowercased() else { return nil }
    return source == "tmdb" ? "themoviedb" : source
  }

  static func resolve(
    mediaIdPrefix: String? = nil,
    source: String? = nil,
    mediaId: String? = nil,
    tmdbId: Int? = nil,
    doubanId: String? = nil,
    bangumiId: Int? = nil,
    anilistId: Int? = nil,
    legacyMediaId: String? = nil
  ) -> MediaIdentity? {
    var sourceIds: [String: String] = [:]
    // raw 数值 ID 的 0 按 Web 的 JavaScript truthy 语义视为缺失；负数仍是 truthy，保持原值。
    sourceIds["themoviedb"] = truthyNumericIdentifier(tmdbId).map(String.init)
    sourceIds["douban"] = truthySourceIdentifier(doubanId)
    sourceIds["bangumi"] = truthyNumericIdentifier(bangumiId).map(String.init)
    sourceIds["anilist"] = truthyNumericIdentifier(anilistId).map(String.init)

    var declaredSources: [String] = []
    for value in [mediaIdPrefix, source] {
      if let normalized = normalizeSource(value), !declaredSources.contains(normalized) {
        declaredSources.append(normalized)
      }
    }
    for declaredSource in declaredSources {
      let declaredId = mediaId == nil ? sourceIds[declaredSource] : normalizedString(mediaId)
      if let sourceId = declaredId {
        return MediaIdentity(source: declaredSource, mediaId: sourceId)
      }
    }
    for fallbackSource in builtInSources {
      if let fallbackId = sourceIds[fallbackSource] {
        return MediaIdentity(source: fallbackSource, mediaId: fallbackId)
      }
    }
    return identity(from: legacyMediaId)
  }

  static func resolveAuxiliaryContent(
    tmdbId: Int?,
    doubanId: String?,
    bangumiId: Int?,
    anilistId: Int?
  ) -> MediaIdentity? {
    if let id = truthyNumericIdentifier(tmdbId) {
      return MediaIdentity(source: "themoviedb", mediaId: String(id))
    }
    if let id = normalizedString(doubanId) {
      return MediaIdentity(source: "douban", mediaId: id)
    }
    if let id = truthyNumericIdentifier(bangumiId) {
      return MediaIdentity(source: "bangumi", mediaId: String(id))
    }
    if let id = truthyNumericIdentifier(anilistId) {
      return MediaIdentity(source: "anilist", mediaId: String(id))
    }
    return nil
  }

  static func identity(from mediaKey: String?) -> MediaIdentity? {
    guard let components = mediaIdComponents(mediaKey),
      let source = normalizeSource(components.prefix)
    else {
      return nil
    }
    return MediaIdentity(source: source, mediaId: components.id)
  }

  static func apiMediaId(
    tmdbId: Int?,
    doubanId: String?,
    bangumiId: Int?,
    anilistId: Int? = nil,
    source: String? = nil,
    mediaIdPrefix: String?,
    mediaId: String?
  ) -> String? {
    resolve(
      mediaIdPrefix: mediaIdPrefix,
      source: source,
      mediaId: mediaId,
      tmdbId: tmdbId,
      doubanId: doubanId,
      bangumiId: bangumiId,
      anilistId: anilistId
    )?.mediaKey
  }

  static func apiMediaId(
    tmdbId: Int?,
    doubanId: String?,
    bangumiId: Int?,
    anilistId: Int? = nil,
    mediaSource: String? = nil,
    mediaId: String? = nil,
    fallbackMediaId: String?
  ) -> String? {
    resolve(
      source: mediaSource,
      mediaId: mediaId,
      tmdbId: tmdbId,
      doubanId: doubanId,
      bangumiId: bangumiId,
      anilistId: anilistId,
      legacyMediaId: fallbackMediaId
    )?.mediaKey
  }

  static func validNumericIdentifier(_ id: Int?) -> Int? {
    guard let id, id > 0 else { return nil }
    return id
  }

  static func truthyNumericIdentifier(_ id: Int?) -> Int? {
    guard let id, id != 0 else { return nil }
    return id
  }

  /// 文本型来源原生 ID 的零值判据：`"0"` 在 v3 校验中非法（Web `isValidMediaSourceId` 同样拒绝），
  /// 因此按缺失处理，让身份解析继续回退到下一个来源。
  static func truthySourceIdentifier(_ value: String?) -> String? {
    guard let normalized = normalizedString(value), normalized != "0" else { return nil }
    return normalized
  }

  static func normalizedString(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  static func isValidManualMediaId(_ mediaId: String?) -> Bool {
    guard let mediaId = normalizedString(mediaId) else { return true }
    guard mediaId.unicodeScalars.allSatisfy({ (48...57).contains(Int($0.value)) }) else {
      return false
    }
    return (Int(mediaId) ?? 0) > 0
  }

  static func normalizedMediaIdentifier(_ mediaId: String?) -> String? {
    guard let mediaId = normalizedString(mediaId), !mediaId.hasSuffix(":") else { return nil }

    return mediaId
  }

  static func mediaIdComponents(_ mediaId: String?) -> (prefix: String, id: String)? {
    guard let mediaId = normalizedMediaIdentifier(mediaId) else { return nil }
    let parts = mediaId.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
    guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
    return (String(parts[0]), String(parts[1]))
  }

}
