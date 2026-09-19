import Foundation

struct TVAPIParameter: Equatable {
  enum Location: String {
    case query
    case path
    case header
  }

  let name: String
  let location: Location
  let alwaysSent: Bool
  let jsonType: TVJSONType
}

enum TVJSONType: String, Equatable {
  case string
  case integer
  case number
  case boolean
  case array
  case object
  case json
  case flexibleBool
  case flexibleString
}

struct TVAPIField: Equatable {
  let name: String
  let jsonType: TVJSONType
  /// TV 解码时该键必须出现（`decode` 而非 `decodeIfPresent`）。
  let required: Bool
  /// TV 请求体每次都会写出该键，包括显式 null。
  let alwaysSent: Bool
}

enum TVAPIResponseKind: Equatable {
  case moviePilotEnvelope
  case raw
  case sse
  case image
  case opaqueJSON
}

struct TVAPITestCoverage: OptionSet, Equatable {
  let rawValue: Int

  static let liveReadOnly = TVAPITestCoverage(rawValue: 1 << 0)
  static let liveSideEffect = TVAPITestCoverage(rawValue: 1 << 1)
  static let urlProtocol = TVAPITestCoverage(rawValue: 1 << 2)
  static let unitDecoding = TVAPITestCoverage(rawValue: 1 << 3)

  var labels: [String] {
    var result: [String] = []
    if contains(.liveReadOnly) { result.append("live-readonly") }
    if contains(.liveSideEffect) { result.append("live-side-effect") }
    if contains(.urlProtocol) { result.append("url-protocol") }
    if contains(.unitDecoding) { result.append("unit-decoding") }
    return result
  }
}

struct TVAPIOperation: Equatable {
  let method: String
  let pathTemplate: String
  let parameters: [TVAPIParameter]
  let bodyFields: [TVAPIField]
  let responseKind: TVAPIResponseKind
  let requiredResponseFields: [TVAPIField]
  let dependedResponseFields: [TVAPIField]
  let roundTrip: Bool
  let dynamic: Bool
  let coverage: TVAPITestCoverage
  let notes: String?

  var operationID: String {
    OpenAPIPathIndex.operationID(method: method, path: pathTemplate)
  }

  var familyPrefix: String {
    OpenAPIPathIndex.familyPrefix(for: pathTemplate)
  }

  var sentParameterNames: [(location: String, name: String)] {
    parameters.map { ($0.location.rawValue, $0.name) }
  }
}

struct TVAPIDynamicFamily: Equatable {
  let id: String
  let method: String
  let pathPrefix: String
  let source: String
}

enum TVAPIOperationBuilder {
  static func get(
    _ path: String,
    query: [TVAPIParameter] = [],
    pathParams: [TVAPIParameter] = [],
    response: TVAPIResponseKind = .moviePilotEnvelope,
    requiredResponse: [TVAPIField] = [],
    dependedResponse: [TVAPIField] = [],
    coverage: TVAPITestCoverage,
    dynamic: Bool = false,
    notes: String? = nil
  ) -> TVAPIOperation {
    operation(
      method: "GET",
      path: path,
      parameters: pathParams + query,
      bodyFields: [],
      response: response,
      requiredResponse: requiredResponse,
      dependedResponse: dependedResponse,
      roundTrip: false,
      coverage: coverage,
      dynamic: dynamic,
      notes: notes
    )
  }

  static func mutation(
    _ method: String,
    _ path: String,
    query: [TVAPIParameter] = [],
    pathParams: [TVAPIParameter] = [],
    body: [TVAPIField] = [],
    response: TVAPIResponseKind = .moviePilotEnvelope,
    requiredResponse: [TVAPIField] = [],
    dependedResponse: [TVAPIField] = [],
    roundTrip: Bool = false,
    coverage: TVAPITestCoverage,
    notes: String? = nil
  ) -> TVAPIOperation {
    operation(
      method: method,
      path: path,
      parameters: pathParams + query,
      bodyFields: body,
      response: response,
      requiredResponse: requiredResponse,
      dependedResponse: dependedResponse,
      roundTrip: roundTrip,
      coverage: coverage,
      dynamic: false,
      notes: notes
    )
  }

  private static func operation(
    method: String,
    path: String,
    parameters: [TVAPIParameter],
    bodyFields: [TVAPIField],
    response: TVAPIResponseKind,
    requiredResponse: [TVAPIField],
    dependedResponse: [TVAPIField],
    roundTrip: Bool,
    coverage: TVAPITestCoverage,
    dynamic: Bool,
    notes: String?
  ) -> TVAPIOperation {
    TVAPIOperation(
      method: method.uppercased(),
      pathTemplate: OpenAPIPathIndex.normalizeAPIPath(path),
      parameters: parameters,
      bodyFields: bodyFields,
      responseKind: response,
      requiredResponseFields: requiredResponse,
      dependedResponseFields: dependedResponse,
      roundTrip: roundTrip,
      dynamic: dynamic,
      coverage: coverage,
      notes: notes
    )
  }
}

enum TVAPIParam {
  static func query(
    _ name: String,
    alwaysSent: Bool = false,
    type: TVJSONType = .string
  ) -> TVAPIParameter {
    TVAPIParameter(name: name, location: .query, alwaysSent: alwaysSent, jsonType: type)
  }

  static func path(_ name: String, type: TVJSONType = .string) -> TVAPIParameter {
    TVAPIParameter(name: name, location: .path, alwaysSent: true, jsonType: type)
  }
}

enum TVAPIFields {
  static func field(
    _ name: String,
    _ type: TVJSONType,
    required: Bool = false,
    alwaysSent: Bool? = nil
  ) -> TVAPIField {
    TVAPIField(
      name: name,
      jsonType: type,
      required: required,
      alwaysSent: alwaysSent ?? required
    )
  }

  static let subscribeRequired: [TVAPIField] = [
    field("name", .string, required: true),
    field("type", .string, required: true),
  ]

  static let subscribeDepended: [TVAPIField] = [
    field("id", .integer),
    field("year", .string),
    field("season", .integer),
    field("state", .string),
    field("username", .string),
    field("tmdbid", .integer),
    field("doubanid", .string),
    field("bangumiid", .integer),
    field("anilistid", .integer),
    field("media_source", .string),
    field("media_id", .string),
    field("mediaid", .string),
    field("keyword", .string),
    field("poster", .string),
    field("best_version", .integer),
    field("best_version_full", .integer),
    field("sites", .array),
    field("downloader", .string),
    field("save_path", .string),
    field("filter_groups", .array),
    field("episode_group", .string),
    field("note", .json),
    field("current_priority", .integer),
    field("episode_priority", .object),
    field("total_episode", .integer),
    field("lack_episode", .integer),
  ]

  static let subscribeWritable: [TVAPIField] = [
    field("id", .integer),
    field("name", .string, required: true),
    field("type", .string, required: true),
    field("year", .string),
    field("keyword", .string),
    field("season", .integer),
    field("poster", .string),
    field("backdrop", .string),
    field("vote", .number),
    field("state", .string),
    field("last_update", .string),
    field("username", .string),
    field("date", .string),
    field("total_episode", .integer),
    field("start_episode", .integer),
    field("lack_episode", .integer),
    field("note", .json),
    field("tmdbid", .integer),
    field("doubanid", .string),
    field("bangumiid", .integer),
    field("anilistid", .integer),
    field("media_source", .string),
    field("media_id", .string),
    field("quality", .string),
    field("resolution", .string),
    field("effect", .string),
    field("include", .string),
    field("exclude", .string),
    field("sites", .array),
    field("downloader", .string),
    field("save_path", .string),
    field("best_version", .integer),
    field("best_version_full", .integer),
    field("current_priority", .integer),
    field("filter_groups", .array),
    field("custom_words", .string),
    field("description", .string),
    field("filter", .string),
    field("episode_group", .string),
    field("search_imdbid", .integer),
    field("media_category", .string),
    field("mediaid", .string),
    field("episode_priority", .object),
  ]

  static let subscribeCreate: [TVAPIField] = [
    field("name", .string, required: true),
    field("type", .string, required: true),
    field("year", .string),
    field("tmdbid", .integer),
    field("doubanid", .string),
    field("bangumiid", .integer),
    field("anilistid", .integer),
    field("media_source", .string),
    field("media_id", .string),
    field("mediaid", .string),
    field("season", .integer),
    field("best_version", .integer),
    field("best_version_full", .integer),
    field("episode_group", .string),
  ]

  static let mediaIdentity: [TVAPIField] = [
    field("title", .string),
    field("type", .string),
    field("year", .string),
    field("season", .integer),
    field("media_source", .string),
    field("media_id", .string),
    field("tmdb_id", .integer),
    field("douban_id", .string),
    field("bangumi_id", .integer),
    field("anilist_id", .integer),
    field("poster_path", .string),
    field("backdrop_path", .string),
  ]

  static let tokenRequired: [TVAPIField] = [
    field("access_token", .string, required: true),
    field("token_type", .string, required: true),
    field("user_name", .string, required: true),
  ]

  static let tokenDepended: [TVAPIField] = [
    field("super_user", .flexibleBool),
    field("permissions", .object),
    field("user_id", .integer),
    field("avatar", .string),
  ]

  static let discoverSourceRequired: [TVAPIField] = [
    field("name", .string, required: true),
    field("mediaid_prefix", .string, required: true),
    field("api_path", .string, required: true),
  ]

  static let recommendSourceRequired: [TVAPIField] = [
    field("name", .string, required: true),
    field("api_path", .string, required: true),
    field("type", .string, required: true),
  ]
}

enum TVAPIContractCatalog {
  static let operations: [TVAPIOperation] = {
    var items: [TVAPIOperation] = []
    items.append(contentsOf: sessionOperations)
    items.append(contentsOf: systemOperations)
    items.append(contentsOf: dashboardOperations)
    items.append(contentsOf: mediaOperations)
    items.append(contentsOf: discoverOperations)
    items.append(contentsOf: personOperations)
    items.append(contentsOf: searchOperations)
    items.append(contentsOf: downloadOperations)
    items.append(contentsOf: transferOperations)
    items.append(contentsOf: siteOperations)
    items.append(contentsOf: subscribeOperations)
    items.append(contentsOf: imageOperations)
    return items
  }()

  static let dynamicFamilies: [TVAPIDynamicFamily] = [
    TVAPIDynamicFamily(
      id: "discover-source-api-path",
      method: "GET",
      pathPrefix: "/",
      source: "GET /discover/source 返回的 api_path，含插件发现入口"
    ),
    TVAPIDynamicFamily(
      id: "recommend-source-api-path",
      method: "GET",
      pathPrefix: "/",
      source: "GET /recommend/source 返回的 api_path"
    ),
  ]

  static let sourceLiteralIgnore: [String] = [
    "/",
    "//",
    "/api/v1",
    "/t/p/original/",
    "/t/p/w500/",
    "/browse/media/search",
  ]

  static var operationIDs: Set<String> {
    Set(operations.map(\.operationID))
  }

  static var usedFamilyPrefixes: Set<String> {
    Set(operations.map(\.familyPrefix))
  }

  private static let read = TVAPITestCoverage.liveReadOnly
  private static let readDecode: TVAPITestCoverage = [.liveReadOnly, .unitDecoding]
  private static let protocolOnly = TVAPITestCoverage.urlProtocol
  private static let sideEffect = TVAPITestCoverage.liveSideEffect
  private static let mutationUnit: TVAPITestCoverage = [.urlProtocol, .unitDecoding]

  private static var sessionOperations: [TVAPIOperation] {
    [
      TVAPIOperationBuilder.mutation(
        "POST",
        "/login/access-token",
        body: [
          TVAPIFields.field("username", .string, required: true),
          TVAPIFields.field("password", .string, required: true),
        ],
        response: .raw,
        requiredResponse: TVAPIFields.tokenRequired,
        dependedResponse: TVAPIFields.tokenDepended,
        coverage: [.liveReadOnly, .urlProtocol, .unitDecoding]
      ),
      TVAPIOperationBuilder.get(
        "/user/current",
        response: .moviePilotEnvelope,
        requiredResponse: [
          TVAPIFields.field("name", .string, required: true),
        ],
        dependedResponse: [
          TVAPIFields.field("id", .integer),
          TVAPIFields.field("is_superuser", .flexibleBool),
          TVAPIFields.field("permissions", .object),
          TVAPIFields.field("avatar", .string),
        ],
        coverage: [.liveReadOnly, .urlProtocol]
      ),
    ]
  }

  private static var systemOperations: [TVAPIOperation] {
    [
      TVAPIOperationBuilder.get(
        "/system/global",
        query: [TVAPIParam.query("token", alwaysSent: true)],
        response: .opaqueJSON,
        dependedResponse: [
          TVAPIFields.field("BACKEND_VERSION", .string),
          TVAPIFields.field("FRONTEND_VERSION", .string),
          TVAPIFields.field("GLOBAL_IMAGE_CACHE", .flexibleBool),
          TVAPIFields.field("RECOGNIZE_SOURCE", .string),
        ],
        coverage: [.liveReadOnly, .urlProtocol, .unitDecoding],
        notes: "响应被声明为 JsonObject，字段检查只能对照 TV 依赖名是否仍存在于基线快照"
      ),
      TVAPIOperationBuilder.get(
        "/system/global/user",
        response: .opaqueJSON,
        coverage: [.liveReadOnly, .urlProtocol]
      ),
      TVAPIOperationBuilder.get(
        "/system/env",
        response: .moviePilotEnvelope,
        dependedResponse: [TVAPIFields.field("VERSION", .string)],
        coverage: read
      ),
      TVAPIOperationBuilder.get(
        "/system/setting/public/{key}",
        pathParams: [TVAPIParam.path("key")],
        response: .moviePilotEnvelope,
        dependedResponse: [TVAPIFields.field("value", .json)],
        coverage: read
      ),
      TVAPIOperationBuilder.get(
        "/system/setting/{key}",
        pathParams: [TVAPIParam.path("key")],
        response: .moviePilotEnvelope,
        dependedResponse: [TVAPIFields.field("value", .json)],
        coverage: read
      ),
      TVAPIOperationBuilder.get(
        "/system/progress/{process_type}",
        pathParams: [TVAPIParam.path("process_type")],
        response: .sse,
        coverage: sideEffect,
        notes: "SSE 进度流；OpenAPI 通常只声明 text/event-stream"
      ),
    ]
  }

  private static var dashboardOperations: [TVAPIOperation] {
    [
      TVAPIOperationBuilder.get("/dashboard/statistic", coverage: read),
      TVAPIOperationBuilder.get(
        "/dashboard/storage",
        dependedResponse: [
          TVAPIFields.field("total_storage", .number),
          TVAPIFields.field("used_storage", .number),
        ],
        coverage: readDecode
      ),
      TVAPIOperationBuilder.get("/dashboard/downloader", coverage: read),
    ]
  }

  private static var mediaOperations: [TVAPIOperation] {
    [
      TVAPIOperationBuilder.get(
        "/media/search",
        query: [
          TVAPIParam.query("title", alwaysSent: true),
          TVAPIParam.query("type"),
          TVAPIParam.query("page", type: .integer),
          TVAPIParam.query("count", type: .integer),
          TVAPIParam.query("media_source"),
        ],
        dependedResponse: TVAPIFields.mediaIdentity,
        coverage: readDecode
      ),
      TVAPIOperationBuilder.get(
        "/media/recognize",
        query: [
          TVAPIParam.query("title", alwaysSent: true),
          TVAPIParam.query("media_source"),
        ],
        coverage: readDecode
      ),
      TVAPIOperationBuilder.get(
        "/media/{media_id}",
        query: [
          TVAPIParam.query("media_source", alwaysSent: true),
          TVAPIParam.query("type_name", alwaysSent: true),
        ],
        pathParams: [TVAPIParam.path("media_id")],
        dependedResponse: TVAPIFields.mediaIdentity,
        coverage: readDecode
      ),
      TVAPIOperationBuilder.get(
        "/media/seasons",
        query: [
          TVAPIParam.query("media_source"),
          TVAPIParam.query("media_id"),
          TVAPIParam.query("title"),
          TVAPIParam.query("year"),
          TVAPIParam.query("season", type: .integer),
        ],
        coverage: read
      ),
      TVAPIOperationBuilder.get(
        "/media/groups/{tmdbid}",
        pathParams: [TVAPIParam.path("tmdbid", type: .integer)],
        coverage: read
      ),
      TVAPIOperationBuilder.get(
        "/media/group/seasons/{episode_group}",
        pathParams: [TVAPIParam.path("episode_group")],
        coverage: read
      ),
      TVAPIOperationBuilder.get(
        "/tmdb/collection/{collection_id}",
        query: [
          TVAPIParam.query("page", alwaysSent: true, type: .integer),
          TVAPIParam.query("title", alwaysSent: true),
        ],
        pathParams: [TVAPIParam.path("collection_id", type: .integer)],
        coverage: read
      ),
      TVAPIOperationBuilder.get(
        "/mediaserver/latest",
        query: [TVAPIParam.query("server", alwaysSent: true)],
        coverage: read
      ),
      TVAPIOperationBuilder.get(
        "/mediaserver/exists",
        query: [
          TVAPIParam.query("media_source"),
          TVAPIParam.query("media_id"),
          TVAPIParam.query("title"),
          TVAPIParam.query("year"),
          TVAPIParam.query("season", type: .integer),
          TVAPIParam.query("mtype"),
        ],
        dependedResponse: [TVAPIFields.field("item", .object)],
        coverage: read
      ),
      TVAPIOperationBuilder.mutation(
        "POST",
        "/mediaserver/notexists",
        body: TVAPIFields.mediaIdentity,
        coverage: read
      ),
    ]
  }

  private static var discoverOperations: [TVAPIOperation] {
    let page = [TVAPIParam.query("page", type: .integer)]
    let discoverPaths = [
      "/discover/tmdb_movies",
      "/discover/tmdb_tvs",
      "/discover/douban_movies",
      "/discover/douban_tvs",
      "/discover/bangumi",
      "/anilist/discover",
    ]
    let recommendPaths = [
      "/recommend/tmdb_trending",
      "/recommend/douban_showing",
      "/recommend/tmdb_movies",
      "/recommend/douban_movie_hot",
      "/recommend/douban_movies",
      "/recommend/tmdb_tvs",
      "/recommend/douban_tv_hot",
      "/recommend/douban_tvs",
      "/recommend/bangumi_calendar",
      "/recommend/douban_tv_animation",
      "/recommend/douban_movie_top250",
      "/recommend/douban_tv_weekly_chinese",
      "/recommend/douban_tv_weekly_global",
      "/anilist/trending",
      "/anilist/popular-this-season",
    ]
    var items = [
      TVAPIOperationBuilder.get(
        "/discover/source",
        requiredResponse: TVAPIFields.discoverSourceRequired,
        dependedResponse: [
          TVAPIFields.field("filter_params", .object),
          TVAPIFields.field("filter_ui", .array),
          TVAPIFields.field("depends", .object),
        ],
        coverage: readDecode
      ),
      TVAPIOperationBuilder.get(
        "/recommend/source",
        requiredResponse: TVAPIFields.recommendSourceRequired,
        coverage: readDecode
      ),
    ]
    items += discoverPaths.map {
      TVAPIOperationBuilder.get($0, query: page, dependedResponse: TVAPIFields.mediaIdentity, coverage: read)
    }
    items += recommendPaths.map {
      TVAPIOperationBuilder.get($0, query: page, dependedResponse: TVAPIFields.mediaIdentity, coverage: read)
    }
    items += [
      TVAPIOperationBuilder.get(
        "/tmdb/recommend/{tmdbid}/{type_name}",
        query: page,
        pathParams: [
          TVAPIParam.path("tmdbid", type: .integer),
          TVAPIParam.path("type_name"),
        ],
        coverage: read
      ),
      TVAPIOperationBuilder.get(
        "/douban/recommend/{doubanid}/{type_name}",
        query: page,
        pathParams: [
          TVAPIParam.path("doubanid"),
          TVAPIParam.path("type_name"),
        ],
        coverage: read
      ),
      TVAPIOperationBuilder.get(
        "/bangumi/recommend/{bangumiid}",
        query: page,
        pathParams: [TVAPIParam.path("bangumiid", type: .integer)],
        coverage: read
      ),
      TVAPIOperationBuilder.get(
        "/anilist/recommend/{anilist_id}",
        query: page,
        pathParams: [TVAPIParam.path("anilist_id", type: .integer)],
        coverage: read
      ),
      TVAPIOperationBuilder.get(
        "/tmdb/similar/{tmdbid}/{type_name}",
        query: page,
        pathParams: [
          TVAPIParam.path("tmdbid", type: .integer),
          TVAPIParam.path("type_name"),
        ],
        coverage: read
      ),
      TVAPIOperationBuilder.get(
        "/tmdb/credits/{tmdbid}/{type_name}",
        query: page,
        pathParams: [
          TVAPIParam.path("tmdbid", type: .integer),
          TVAPIParam.path("type_name"),
        ],
        coverage: read
      ),
      TVAPIOperationBuilder.get(
        "/douban/credits/{doubanid}/{type_name}",
        query: page,
        pathParams: [
          TVAPIParam.path("doubanid"),
          TVAPIParam.path("type_name"),
        ],
        coverage: read
      ),
      TVAPIOperationBuilder.get(
        "/bangumi/credits/{bangumiid}",
        query: page,
        pathParams: [TVAPIParam.path("bangumiid", type: .integer)],
        coverage: read
      ),
      TVAPIOperationBuilder.get(
        "/anilist/credits/{anilist_id}",
        query: page,
        pathParams: [TVAPIParam.path("anilist_id", type: .integer)],
        coverage: read
      ),
    ]
    return items
  }

  private static var personOperations: [TVAPIOperation] {
    let sources = ["tmdb", "douban", "bangumi", "anilist"]
    return sources.flatMap { source in
      [
        TVAPIOperationBuilder.get(
          "/\(source)/person/{person_id}",
          pathParams: [TVAPIParam.path("person_id", type: .integer)],
          coverage: readDecode
        ),
        TVAPIOperationBuilder.get(
          "/\(source)/person/credits/{person_id}",
          query: [TVAPIParam.query("page", type: .integer)],
          pathParams: [TVAPIParam.path("person_id", type: .integer)],
          coverage: read
        ),
      ]
    }
  }

  private static var searchOperations: [TVAPIOperation] {
    [
      TVAPIOperationBuilder.get(
        "/search/title",
        query: [
          TVAPIParam.query("keyword", alwaysSent: true),
          TVAPIParam.query("sites"),
        ],
        coverage: read
      ),
      TVAPIOperationBuilder.get(
        "/search/media/{media_id}",
        query: [
          TVAPIParam.query("media_source", alwaysSent: true),
          TVAPIParam.query("mtype"),
          TVAPIParam.query("area"),
          TVAPIParam.query("title"),
          TVAPIParam.query("year"),
          TVAPIParam.query("season", type: .integer),
          TVAPIParam.query("sites"),
        ],
        pathParams: [TVAPIParam.path("media_id")],
        coverage: read
      ),
      TVAPIOperationBuilder.get(
        "/search/title/stream",
        query: [
          TVAPIParam.query("keyword"),
          TVAPIParam.query("sites"),
        ],
        response: .sse,
        coverage: read
      ),
      TVAPIOperationBuilder.get(
        "/search/media/{media_id}/stream",
        query: [
          TVAPIParam.query("media_source", alwaysSent: true),
          TVAPIParam.query("mtype"),
          TVAPIParam.query("area"),
          TVAPIParam.query("title"),
          TVAPIParam.query("year"),
          TVAPIParam.query("season", type: .integer),
          TVAPIParam.query("sites"),
        ],
        pathParams: [TVAPIParam.path("media_id")],
        response: .sse,
        coverage: read
      ),
    ]
  }

  private static var downloadOperations: [TVAPIOperation] {
    [
      TVAPIOperationBuilder.get("/download/clients", coverage: read),
      TVAPIOperationBuilder.get(
        "/download/",
        query: [TVAPIParam.query("name", alwaysSent: true)],
        coverage: read
      ),
      TVAPIOperationBuilder.get(
        "/download/stop/{hashString}",
        query: [TVAPIParam.query("name", alwaysSent: true)],
        pathParams: [TVAPIParam.path("hashString")],
        coverage: [.urlProtocol]
      ),
      TVAPIOperationBuilder.get(
        "/download/start/{hashString}",
        query: [TVAPIParam.query("name", alwaysSent: true)],
        pathParams: [TVAPIParam.path("hashString")],
        coverage: [.urlProtocol]
      ),
      TVAPIOperationBuilder.mutation(
        "DELETE",
        "/download/{hashString}",
        query: [TVAPIParam.query("name", alwaysSent: true)],
        pathParams: [TVAPIParam.path("hashString")],
        coverage: [.urlProtocol]
      ),
      TVAPIOperationBuilder.mutation(
        "POST",
        "/download/add",
        body: [
          TVAPIFields.field("torrent_in", .object, required: true),
          TVAPIFields.field("downloader", .string),
          TVAPIFields.field("save_path", .string),
        ],
        coverage: mutationUnit
      ),
      TVAPIOperationBuilder.mutation(
        "POST",
        "/download/",
        body: [
          TVAPIFields.field("torrent_in", .object, required: true),
          TVAPIFields.field("downloader", .string),
          TVAPIFields.field("save_path", .string),
          TVAPIFields.field("media_in", .object, required: true),
        ],
        coverage: mutationUnit
      ),
    ]
  }

  private static var transferOperations: [TVAPIOperation] {
    [
      TVAPIOperationBuilder.get(
        "/history/transfer",
        query: [
          TVAPIParam.query("page", alwaysSent: true, type: .integer),
          TVAPIParam.query("count", alwaysSent: true, type: .integer),
          TVAPIParam.query("title"),
        ],
        dependedResponse: [
          TVAPIFields.field("list", .array),
          TVAPIFields.field("total", .integer),
        ],
        coverage: readDecode
      ),
      TVAPIOperationBuilder.mutation(
        "DELETE",
        "/history/transfer",
        query: [
          TVAPIParam.query("deletesrc", alwaysSent: true, type: .boolean),
          TVAPIParam.query("deletedest", alwaysSent: true, type: .boolean),
        ],
        body: [TVAPIFields.field("id", .integer, required: true, alwaysSent: true)],
        coverage: [.urlProtocol]
      ),
      TVAPIOperationBuilder.mutation(
        "POST",
        "/history/transfer/{history_id}/ai-redo",
        pathParams: [TVAPIParam.path("history_id", type: .integer)],
        dependedResponse: [TVAPIFields.field("progress_key", .string, required: true)],
        coverage: sideEffect
      ),
      TVAPIOperationBuilder.mutation(
        "POST",
        "/history/transfer/ai-redo",
        body: [TVAPIFields.field("history_ids", .array, required: true)],
        dependedResponse: [TVAPIFields.field("progress_key", .string, required: true)],
        coverage: sideEffect
      ),
      TVAPIOperationBuilder.mutation(
        "POST",
        "/transfer/manual",
        query: [TVAPIParam.query("background", alwaysSent: true, type: .boolean)],
        body: [
          TVAPIFields.field("fileitem", .object),
          TVAPIFields.field("fileitems", .array),
          TVAPIFields.field("logid", .integer),
          TVAPIFields.field("target_storage", .string),
          TVAPIFields.field("target_path", .string),
          TVAPIFields.field("min_filesize", .integer),
          TVAPIFields.field("scrape", .boolean),
          TVAPIFields.field("from_history", .boolean),
          TVAPIFields.field("transfer_type", .string, alwaysSent: true),
          TVAPIFields.field("type_name", .string),
          TVAPIFields.field("tmdbid", .integer),
          TVAPIFields.field("doubanid", .string),
          TVAPIFields.field("bangumiid", .integer),
          TVAPIFields.field("anilistid", .integer),
          TVAPIFields.field("media_source", .string),
          TVAPIFields.field("media_id", .string),
          TVAPIFields.field("episode_group", .string),
          TVAPIFields.field("season", .integer),
          TVAPIFields.field("episode_detail", .string),
          TVAPIFields.field("episode_format", .string),
          TVAPIFields.field("episode_offset", .string),
          TVAPIFields.field("episode_part", .string),
          TVAPIFields.field("library_type_folder", .boolean),
          TVAPIFields.field("library_category_folder", .boolean),
          TVAPIFields.field("preview", .boolean),
        ],
        coverage: [.liveReadOnly, .urlProtocol, .unitDecoding]
      ),
    ]
  }

  private static var siteOperations: [TVAPIOperation] {
    [
      TVAPIOperationBuilder.get("/site/rss", coverage: read),
      TVAPIOperationBuilder.get("/site/", coverage: read),
    ]
  }

  private static var subscribeOperations: [TVAPIOperation] {
    [
      TVAPIOperationBuilder.get(
        "/subscribe/",
        requiredResponse: TVAPIFields.subscribeRequired,
        dependedResponse: TVAPIFields.subscribeDepended,
        coverage: readDecode
      ),
      TVAPIOperationBuilder.mutation(
        "POST",
        "/subscribe/",
        body: TVAPIFields.subscribeCreate,
        dependedResponse: [TVAPIFields.field("id", .integer)],
        coverage: mutationUnit
      ),
      TVAPIOperationBuilder.mutation(
        "PUT",
        "/subscribe/",
        body: TVAPIFields.subscribeWritable,
        roundTrip: true,
        coverage: [.liveSideEffect, .unitDecoding]
      ),
      TVAPIOperationBuilder.get(
        "/subscribe/{subscribe_id}",
        pathParams: [TVAPIParam.path("subscribe_id", type: .integer)],
        requiredResponse: TVAPIFields.subscribeRequired,
        dependedResponse: TVAPIFields.subscribeDepended,
        coverage: readDecode
      ),
      TVAPIOperationBuilder.mutation(
        "DELETE",
        "/subscribe/{subscribe_id}",
        pathParams: [TVAPIParam.path("subscribe_id", type: .integer)],
        coverage: mutationUnit
      ),
      TVAPIOperationBuilder.get(
        "/subscribe/media/{media_id}",
        query: [
          TVAPIParam.query("media_source", alwaysSent: true),
          TVAPIParam.query("season", type: .integer),
          TVAPIParam.query("title"),
          TVAPIParam.query("year"),
          TVAPIParam.query("mtype"),
        ],
        pathParams: [TVAPIParam.path("media_id")],
        dependedResponse: [
          TVAPIFields.field("id", .integer),
          TVAPIFields.field("media_source", .string),
          TVAPIFields.field("media_id", .string),
        ],
        coverage: readDecode
      ),
      TVAPIOperationBuilder.mutation(
        "DELETE",
        "/subscribe/media/{media_id}",
        query: [
          TVAPIParam.query("media_source", alwaysSent: true),
          TVAPIParam.query("season", type: .integer),
        ],
        pathParams: [TVAPIParam.path("media_id")],
        coverage: mutationUnit
      ),
      TVAPIOperationBuilder.mutation(
        "POST",
        "/subscribe/fork",
        body: [
          TVAPIFields.field("id", .integer),
          TVAPIFields.field("share_title", .string),
          TVAPIFields.field("name", .string),
          TVAPIFields.field("type", .string),
        ],
        dependedResponse: [TVAPIFields.field("id", .integer)],
        coverage: mutationUnit
      ),
      TVAPIOperationBuilder.mutation(
        "PUT",
        "/subscribe/status/{subid}",
        query: [TVAPIParam.query("state", alwaysSent: true)],
        pathParams: [TVAPIParam.path("subid", type: .integer)],
        coverage: sideEffect
      ),
      TVAPIOperationBuilder.mutation(
        "POST",
        "/subscribe/search/{subscribe_id}",
        pathParams: [TVAPIParam.path("subscribe_id", type: .integer)],
        coverage: sideEffect
      ),
      TVAPIOperationBuilder.mutation(
        "POST",
        "/subscribe/reset/{subid}",
        pathParams: [TVAPIParam.path("subid", type: .integer)],
        coverage: sideEffect
      ),
      TVAPIOperationBuilder.get(
        "/subscribe/shares",
        query: [
          TVAPIParam.query("name"),
          TVAPIParam.query("page", type: .integer),
          TVAPIParam.query("count", type: .integer),
          TVAPIParam.query("genre_id", type: .integer),
          TVAPIParam.query("min_rating", type: .number),
          TVAPIParam.query("sort_type"),
        ],
        coverage: read
      ),
      TVAPIOperationBuilder.get(
        "/subscribe/popular",
        query: [
          TVAPIParam.query("stype", alwaysSent: true),
          TVAPIParam.query("page", type: .integer),
          TVAPIParam.query("count", type: .integer),
          TVAPIParam.query("genre_id", type: .integer),
          TVAPIParam.query("min_rating", type: .number),
          TVAPIParam.query("sort_type"),
        ],
        coverage: read
      ),
    ]
  }

  private static var imageOperations: [TVAPIOperation] {
    [
      TVAPIOperationBuilder.get(
        "/system/img/{proxy}",
        query: [
          TVAPIParam.query("imgurl", alwaysSent: true),
          TVAPIParam.query("cache", type: .boolean),
          TVAPIParam.query("use_cookies", type: .boolean),
        ],
        pathParams: [TVAPIParam.path("proxy", type: .boolean)],
        response: .image,
        coverage: read
      ),
      TVAPIOperationBuilder.get(
        "/system/cache/image",
        query: [TVAPIParam.query("url", alwaysSent: true)],
        response: .image,
        coverage: read
      ),
    ]
  }
}
