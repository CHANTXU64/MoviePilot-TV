import Foundation

enum OpenAPIContractSupport {
  static func repositoryRoot(from filePath: String = #filePath) -> URL? {
    var url = URL(fileURLWithPath: filePath).deletingLastPathComponent()
    while url.path != "/" {
      if FileManager.default.fileExists(
        atPath: url.appendingPathComponent("MoviePilot-TV.xcodeproj").path
      ) {
        return url
      }
      url.deleteLastPathComponent()
    }
    return nil
  }

  static func fixtureURL(_ name: String, from filePath: String = #filePath) -> URL? {
    repositoryRoot(from: filePath)?
      .appendingPathComponent("MoviePilot-TV-Tests/OpenAPI/Fixtures/\(name)")
  }

  static func loadData(_ name: String, from filePath: String = #filePath) throws -> Data {
    guard let url = fixtureURL(name, from: filePath) else {
      throw OpenAPIDocumentError.unsupported("无法定位仓库根目录")
    }
    return try Data(contentsOf: url)
  }

  static func loadDocument(_ name: String, from filePath: String = #filePath) throws -> OpenAPIDocument {
    try OpenAPIDocument.parse(data: loadData(name, from: filePath))
  }

  static func loadExceptions(from filePath: String = #filePath) throws -> [OpenAPIException] {
    let data = try loadData("openapi-exceptions.json", from: filePath)
    return try OpenAPIExceptionStore.load(from: data)
  }

  static func isProbablyHTML(data: Data, contentType: String?) -> Bool {
    if let contentType, contentType.lowercased().contains("text/html") {
      return true
    }
    let prefix = data.prefix(64)
    guard let text = String(data: prefix, encoding: .utf8)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    else {
      return false
    }
    return text.hasPrefix("<!doctype html") || text.hasPrefix("<html")
  }

  static func openAPIURL(baseURL: String) throws -> URL {
    let trimmed = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
    guard let url = URL(string: "\(trimmed)/api/v1/openapi.json") else {
      throw OpenAPIDocumentError.unsupported("无法构造 OpenAPI URL")
    }
    return url
  }

  static func fetchOpenAPI(
    baseURL: String,
    token: String? = nil,
    session: URLSession = .shared
  ) async throws -> (document: OpenAPIDocument, raw: Data, version: String?) {
    let url = try openAPIURL(baseURL: baseURL)
    var request = URLRequest(url: url)
    request.timeoutInterval = 30
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if let token, !token.isEmpty {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw OpenAPIFetchError.invalidResponse
    }
    let contentType = http.value(forHTTPHeaderField: "Content-Type")
    if isProbablyHTML(data: data, contentType: contentType) {
      throw OpenAPIFetchError.htmlLoginPage(statusCode: http.statusCode)
    }
    guard (200..<300).contains(http.statusCode) else {
      throw OpenAPIFetchError.httpStatus(http.statusCode)
    }
    let document = try OpenAPIDocument.parse(data: data)
    return (document, data, document.version)
  }
}

enum OpenAPIFetchError: Error, Equatable, CustomStringConvertible {
  case invalidResponse
  case htmlLoginPage(statusCode: Int)
  case httpStatus(Int)

  var description: String {
    switch self {
    case .invalidResponse:
      return "OpenAPI 请求没有返回 HTTP 响应"
    case .htmlLoginPage(let statusCode):
      return "读取 OpenAPI 时得到登录页或 HTML（HTTP \(statusCode)），不能当作契约通过，也不改走公共文档站"
    case .httpStatus(let code):
      return "读取 OpenAPI 失败：HTTP \(code)"
    }
  }
}

enum TVAPIContractSourceScanner {
  static func coverageGaps(from filePath: String = #filePath) -> [OpenAPICoverageGap] {
    guard let root = OpenAPIContractSupport.repositoryRoot(from: filePath) else { return [] }
    let files = [
      root.appendingPathComponent("MoviePilot-TV/Services/APIService.swift"),
      root.appendingPathComponent("MoviePilot-TV/ViewModels/ExploreViewModel.swift"),
      root.appendingPathComponent("MoviePilot-TV/ViewModels/RecommendViewModel.swift"),
    ]
    var literals: Set<String> = []
    for file in files {
      guard let source = try? String(contentsOf: file, encoding: .utf8) else { continue }
      literals.formUnion(extractPathLiterals(from: source))
    }

    var gaps: [OpenAPICoverageGap] = []
    for literal in literals.sorted() {
      if shouldIgnore(literal) { continue }
      if isCatalogued(literal) { continue }
      gaps.append(
        OpenAPICoverageGap(
          kind: .sourceUnregistered,
          operationID: literal,
          message: "生产入口出现该路径，但 OpenAPI 目录未登记"
        )
      )
    }
    return gaps
  }

  static func extractPathLiterals(from source: String) -> Set<String> {
    var result: Set<String> = []
    let pattern = #""(/[^"\n]*)""#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    let range = NSRange(source.startIndex..., in: source)
    for match in regex.matches(in: source, range: range) {
      guard let swiftRange = Range(match.range(at: 1), in: source) else { continue }
      result.insert(String(source[swiftRange]))
    }
    return result
  }

  static func normalizeSourcePath(_ raw: String) -> String {
    var value = raw
    value = value.replacingOccurrences(
      of: #"\\\([^)]*\)"#,
      with: "{param}",
      options: .regularExpression
    )
    if let query = value.firstIndex(of: "?") {
      value = String(value[..<query])
    }
    return OpenAPIPathIndex.normalizeAPIPath(value)
  }

  private static func shouldIgnore(_ raw: String) -> Bool {
    let normalized = normalizeSourcePath(raw)
    if TVAPIContractCatalog.sourceLiteralIgnore.contains(raw)
      || TVAPIContractCatalog.sourceLiteralIgnore.contains(normalized)
    {
      return true
    }
    if normalized == "/" || normalized == "/api/v1" { return true }
    if normalized.hasPrefix("/t/p/") { return true }
    if normalized == "/{param}" || normalized == "/{param}/"
      || normalized == "/{param}/api/v1"
    {
      return true
    }
    if raw.contains("browse/media") { return true }
    if !normalized.hasPrefix("/") { return true }
    if normalized.split(separator: "/").count <= 1 && !normalized.hasSuffix("/") {
      return true
    }
    return false
  }

  private static func isCatalogued(_ raw: String) -> Bool {
    let normalized = normalizeSourcePath(raw)
    if TVAPIContractCatalog.operations.contains(where: {
      OpenAPIPathIndex.pathsMatch($0.pathTemplate, normalized)
        || concreteSettingPathMatches(catalog: $0.pathTemplate, source: normalized)
    }) {
      return true
    }
    let mapped = mappedTemplates(from: raw)
    return mapped.contains { template in
      TVAPIContractCatalog.operations.contains {
        OpenAPIPathIndex.pathsMatch($0.pathTemplate, template)
      }
    }
  }

  private static func concreteSettingPathMatches(catalog: String, source: String) -> Bool {
    let knownKeys = [
      "Storages", "Directories", "IndexerSites", "MediaServers",
      "UserFilterRuleGroups", "CustomFilterRules",
    ]
    for key in knownKeys {
      if source == catalog.replacingOccurrences(of: "{key}", with: key) {
        return true
      }
    }
    return false
  }

  private static func mappedTemplates(from raw: String) -> [String] {
    let normalized = normalizeSourcePath(raw)
    switch normalized {
    case "/media":
      return ["/media/{media_id}"]
    case "/search/media":
      return ["/search/media/{media_id}"]
    case "/subscribe/media":
      return ["/subscribe/media/{media_id}"]
    case "/{param}/person/{param}":
      return ["tmdb", "douban", "bangumi", "anilist"].map { "/\($0)/person/{person_id}" }
    case "/{param}/person/credits/{param}":
      return ["tmdb", "douban", "bangumi", "anilist"].map { "/\($0)/person/credits/{person_id}" }
    default:
      if normalized.hasPrefix("/discover/")
        || normalized.hasPrefix("/recommend/")
        || normalized.hasPrefix("/anilist/")
        || normalized.hasPrefix("/subscribe/")
      {
        return [normalized]
      }
      return [normalized]
    }
  }
}
