import Foundation

nonisolated struct TopShelfSelection: Codable, Equatable, Hashable, Identifiable, Sendable {
  let shelfID: String
  let title: String

  var exploration: ExploreConfiguration? = nil

  var requestPath: String { exploration?.apiPath ?? shelfID }
  var isSubscriptionShare: Bool { exploration?.selectedSource == .subscriptionShare }

  init(shelfID: String, title: String, exploration: ExploreConfiguration? = nil) {
    self.shelfID = shelfID
    self.title = title
    self.exploration = exploration
  }

  init(exploration: ExploreConfiguration) {
    self.init(
      shelfID: exploration.apiPath, title: "探索 · \(exploration.selectedSource.title)",
      exploration: exploration)
  }

  var id: String { exploration == nil ? shelfID : "explore:\(shelfID)" }
}

nonisolated struct TopShelfRoutePayload: Codable, Equatable, Sendable {
  let sessionID: String
  let source: String?
  let mediaID: String?
  let mediaIDPrefix: String?
  let tmdbID: Int?
  let doubanID: String?
  let bangumiID: Int?
  let anilistID: Int?
  let imdbID: String?
  let tvdbID: Int?
  let title: String?
  let type: String?
  let year: String?
  let season: Int?
  let posterPath: String?
  let collectionID: Int?
  var overview: String? = nil
  var voteAverage: Double? = nil

  var cardIdentifier: String? {
    let identity = MediaIdentifier.resolve(
      mediaIdPrefix: mediaIDPrefix, source: source,
      mediaId: mediaID, tmdbId: tmdbID, doubanId: doubanID, bangumiId: bangumiID,
      anilistId: anilistID)
    let key = collectionID.map { "collection:\($0)" } ?? identity?.mediaKey
    guard let key else { return nil }
    return [key, type, season.map(String.init)].map { value in
      value.map { "s\($0.utf8.count):\($0)" } ?? "n"
    }.joined(separator: "|")
  }
}

nonisolated enum TopShelfDeepLink {
  private static let scheme = "moviepilot-tv"
  private static let host = "top-shelf"
  private static let mediaPath = "/media"
  private static let payloadName = "payload"

  static func url(for payload: TopShelfRoutePayload) throws -> URL {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let encoded = try encoder.encode(payload)
    let value = encoded.base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
    var components = URLComponents()
    components.scheme = scheme
    components.host = host
    components.path = mediaPath
    components.queryItems = [URLQueryItem(name: payloadName, value: value)]
    guard let url = components.url else { throw TopShelfDeepLinkError.invalidURL }
    return url
  }

  static func payload(from url: URL) -> TopShelfRoutePayload? {
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
      components.scheme?.lowercased() == scheme,
      components.host?.lowercased() == host,
      components.path == mediaPath
    else { return nil }

    let payloadItems = (components.queryItems ?? []).filter { $0.name == payloadName }
    guard payloadItems.count == 1, let value = payloadItems[0].value,
      !value.isEmpty
    else { return nil }

    var base64 =
      value
      .replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    let remainder = base64.count % 4
    if remainder != 0 {
      base64.append(String(repeating: "=", count: 4 - remainder))
    }
    guard let data = Data(base64Encoded: base64) else { return nil }
    return try? JSONDecoder().decode(TopShelfRoutePayload.self, from: data)
  }
}

nonisolated enum TopShelfDeepLinkError: Error, Equatable {
  case invalidURL
}

nonisolated struct TopShelfSnapshotItem: Codable, Equatable, Sendable {
  let identifier: String
  let title: String
  let imageRelativePath: String
  let displayURL: URL
  var detailRelativePath: String? = nil
  var backgroundRelativePath: String? = nil
  var backgroundIsPoster: Bool? = nil

  var resourcePaths: [String] {
    [imageRelativePath, detailRelativePath, backgroundRelativePath].compactMap { $0 }
  }
}

nonisolated struct TopShelfSnapshot: Codable, Equatable, Sendable {
  static let maximumItems = 6
  /// 系统可能在读取 state 后才异步取图，旧文件至少保留一天再回收。
  static let imageCleanupGracePeriod: TimeInterval = 24 * 60 * 60

  let sessionID: String
  let selection: TopShelfSelection
  let generatedAt: Date
  let items: [TopShelfSnapshotItem]
  var refreshConfiguration: TopShelfRefreshConfiguration? = nil

}

nonisolated struct TopShelfSharedState: Codable, Equatable, Sendable {
  static let currentSchemaVersion = 1

  var schemaVersion: Int
  let activeSessionID: String?
  let selection: TopShelfSelection?
  var snapshot: TopShelfSnapshot?
  var refreshConfiguration: TopShelfRefreshConfiguration? = nil

  static func disabled(selection: TopShelfSelection?) -> TopShelfSharedState {
    TopShelfSharedState(
      schemaVersion: currentSchemaVersion,
      activeSessionID: nil,
      selection: selection,
      snapshot: nil
    )
  }
}

nonisolated struct TopShelfImageResource: Equatable, Sendable {
  let data: Data
  let fileExtension: String
}

nonisolated struct TopShelfPresentationItem: Equatable, Sendable {
  let identifier: String
  let title: String
  let imageURL: URL
  let displayURL: URL
}

nonisolated struct TopShelfPresentation: Equatable, Sendable {
  let title: String
  let items: [TopShelfPresentationItem]
}
