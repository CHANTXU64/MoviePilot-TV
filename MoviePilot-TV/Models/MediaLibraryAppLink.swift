import Foundation

/// 在 tvOS 上打开媒体服务器 App 的深链：媒体库页「跳转媒体库」和详情页已入库条目的跳转按钮共用。
enum MediaLibraryAppLink {
  enum Outcome: Equatable {
    case url(URL)
    /// 打不开时给用户看的原因。
    case failure(String)
  }

  /// 该服务器类型是否已知支持在 tvOS 打开媒体库深链（静态能力，不依赖具体链接）
  static func isSupported(serverType: MediaServerType?) -> Bool {
    guard let serverType else { return true }
    switch serverType {
    case .jellyfin, .trimemedia, .ugreen, .zspace:
      return false
    default:
      return true
    }
  }

  /// 按 MoviePilot 给的网页链接和条目编号生成 App 深链。
  /// `link` 是媒体库列表的条目链接，或 `/mediaserver/play` 的播放页面地址；`rawID` 是 Plex 的条目编号。
  static func resolve(
    serverType: MediaServerType?, link: String?, itemID: String?, serverID: String?, rawID: String?
  ) -> Outcome {
    let originalUrl = validValue(link).flatMap { URL(string: $0) }
    guard originalUrl != nil || serverType == .emby else {
      return .failure("无法打开媒体库：链接无效")
    }

    // 统一处理 Fragment 解析：有些后端返回 #!/item... 有些返回 #/item...
    let fragmentComponents: URLComponents? = {
      guard let fragment = originalUrl?.fragment else { return nil }
      let clean = fragment.starts(with: "!") ? String(fragment.dropFirst(1)) : fragment
      return URLComponents(string: "https://dummy.com" + clean)
    }()

    var finalUrl: URL?
    switch serverType {
    case .emby:
      // 保留 Emby 社区提到的深度链接格式，但 tvOS 端仍受 Emby App 自身支持限制。
      // 2026-06-29 使用 Emby for Apple TV 2.0.7 实机测试：该 URL 只能打开 Emby，尚不能跳转到具体媒体详情。
      // 后端链接格式: https://your-emby-server/web/index.html#!/item?id=xxxx&serverId=...
      // 尝试的深度链接格式: emby://items?serverId={your_server_id}&itemId={your_item_id}
      let queryItems = fragmentComponents?.queryItems ?? []
      let itemId =
        validValue(itemID)
        ?? validValue(queryItems.first { $0.name == "id" }?.value)
        ?? validValue(queryItems.first { $0.name == "parentId" }?.value)
      let serverId = validValue(serverID) ?? validValue(queryItems.first { $0.name == "serverId" }?.value)
      if let itemId {
        var deepLinkComponents = URLComponents()
        deepLinkComponents.scheme = "emby"
        deepLinkComponents.host = "items"
        deepLinkComponents.queryItems =
          (serverId.map { [URLQueryItem(name: "serverId", value: $0)] } ?? [])
          + [URLQueryItem(name: "itemId", value: itemId)]
        finalUrl = deepLinkComponents.url
      }

    case .plex:
      // 媒体库列表链接: http://ip:port/web/index.html#!/media/{server_id}/com.plexapp.plugins.library?source=...（条目编号另给 raw_id）
      // 播放页面地址: http://ip:port/web/index.html#!/server/{server_id}/details?key={条目编号或 /library/metadata/ 路径}
      // 深度链接: plex://preplay/?metadataKey={metadataKey}&server={serverId}
      if let components = fragmentComponents {
        let pathParts = components.path.split(separator: "/")
        var target: (server: String, key: String)?
        if pathParts.count >= 2, pathParts[0] == "media", let rawId = validValue(rawID) {
          target = (String(pathParts[1]), rawId)
        } else if pathParts.count >= 3, pathParts[0] == "server", pathParts[2] == "details",
          let key = validValue(components.queryItems?.first { $0.name == "key" }?.value)
        {
          target = (String(pathParts[1]), key)
        }
        if let target {
          let metadataKey = target.key.hasPrefix("/library/metadata/") ? target.key : "/library/metadata/\(target.key)"
          var deepLinkComponents = URLComponents()
          deepLinkComponents.scheme = "plex"
          deepLinkComponents.host = "preplay"
          deepLinkComponents.path = "/"
          deepLinkComponents.queryItems = [
            URLQueryItem(name: "metadataKey", value: metadataKey),
            URLQueryItem(name: "server", value: target.server),
          ]
          finalUrl = deepLinkComponents.url
        }
      }
      // 降级策略
      if finalUrl == nil { finalUrl = URL(string: "plex://") }

    case .jellyfin:
      return .failure("Jellyfin 暂不支持在 tvOS 打开媒体")
    case .trimemedia:
      return .failure("飞牛 NAS 暂不支持在 tvOS 打开媒体")
    case .ugreen:
      return .failure("绿联 NAS 暂不支持在 tvOS 打开媒体")
    case .zspace:
      return .failure("极空间 NAS 暂不支持在 tvOS 打开媒体")
    default:
      // 处理未来未知的服务器类型（serverType.rawValue）
      return .failure("未知的媒体服务器类型\(serverType.map { "（\($0.rawValue)）" } ?? "")暂不支持在 tvOS 打开媒体")
    }

    if let finalUrl { return .url(finalUrl) }
    return .failure("未能生成 \(serverType?.rawValue ?? "") 的有效媒体库链接")
  }

  /// 打开失败（没装 App）时的提示。
  static let openFailureMessage = "无法打开媒体库 App，请确认已安装后重试"

  private static func validValue(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if ["none", "null", "undefined"].contains(trimmed.lowercased()) {
      return nil
    }
    return trimmed
  }
}

/// `/mediaserver/play/{itemid}` 的结果：播放页面地址和条目所在服务器的编号。
/// 后端不给服务器类型：接口代码里的 `server_type` 填的是服务器配置名，不是类型；v3.0 的返回模型带着它，
/// v3.1 起返回模型没有这个字段、输出时被滤掉。所以不解码它，类型从媒体服务器配置里查。
struct MediaServerPlayLink: Decodable, Equatable {
  let url: String?
  let item_id: FlexibleString?
  let server_id: FlexibleString?

  /// 能在 tvOS 打开时的 App 深链；服务器类型不支持或链接无效时为 nil。
  func appURL(serverType: MediaServerType) -> URL? {
    guard MediaLibraryAppLink.isSupported(serverType: serverType),
      case .url(let url) = MediaLibraryAppLink.resolve(
        serverType: serverType, link: url, itemID: item_id?.value, serverID: server_id?.value, rawID: item_id?.value)
    else { return nil }
    return url
  }
}

extension MediaLibraryAppLink {
  /// 入库条目所在服务器的类型：按入库查询给的服务器名称在已启用的配置里找；没给名称（v3.2.6 以前的后端）时，
  /// 已启用的服务器都是同一种类型才算确定。确定不了时为 nil，不猜。
  static func serverType(named name: String?, in servers: [MediaServerConf]) -> MediaServerType? {
    let enabled = servers.filter(\.isEnabled)
    let candidates = name.map { name in enabled.filter { $0.name == name } } ?? enabled
    let types = Set(candidates.map { $0.type.lowercased() })
    guard types.count == 1, let type = types.first else { return nil }
    return MediaServerType(rawValue: type)
  }
}
