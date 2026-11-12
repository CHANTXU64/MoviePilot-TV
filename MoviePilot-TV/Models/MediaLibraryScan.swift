import Foundation

// 试看的这一集整理好以后，叫媒体服务器马上入库：刷新哪台、刷新什么。规则照 MoviePilot 的媒体库刷新
// （Emby 等模块的 `refresh_library_by_items`，媒体库刷新插件调用的就是它），各类服务器的适配器只负责发请求。

/// 一台服务器上的一个媒体库和它的文件夹（服务器看到的路径）。
nonisolated struct MediaLibraryFolder: Equatable, Sendable {
  let id: String
  let paths: [String]
}

/// 叫服务器重新扫描的范围。
nonisolated enum MediaLibraryRefreshScope: Equatable, Sendable {
  /// 一部剧：重新扫描它的目录，新的一集会补进来。
  case series(id: String)
  /// 一个媒体库。
  case library(id: String)
  /// 整个库（所有媒体库）。
  case all
}

/// 试看服务叫媒体服务器入库的范围。
nonisolated enum LibraryScanRequest: Equatable, Sendable {
  /// 按 MoviePilot 的规则刷新这一集所在的地方（见 `PlaybackCoordinator.requestLibraryScan`）。
  case located(TransferredFileLocation)
  /// 每台都刷新整个库：按位置刷新过、过一阵还没入库时兜底（可能刷错了地方）。
  case everything
}

/// 整理好的文件在 MoviePilot 那边的位置，来自整理记录。
nonisolated struct TransferredFileLocation: Equatable, Sendable {
  /// 整理后的路径，是 MoviePilot 看到的路径；Docker 里两边挂载的路径不同时和服务器看到的对不上。
  let path: String?
  /// MoviePilot 的二级分类（如「国产剧」）：路径对不上时，按媒体库文件夹里有没有这个分类目录来找。
  let category: String?
}

nonisolated enum MediaLibraryScan {
  /// 整理后的文件所在的媒体库：路径落在哪个媒体库的文件夹里（逐级比较目录）就是哪个；都不在时，
  /// 文件夹路径里有这个二级分类目录的那个；还找不到时为 nil。都按服务器给的顺序取第一个，和 MoviePilot 一样。
  static func library(for file: TransferredFileLocation, in folders: [MediaLibraryFolder]) -> String? {
    if let path = file.path.flatMap({ trimmedNonEmpty([$0]) }) {
      let target = components(path)
      if let folder = folders.first(where: { folder in
        folder.paths.contains { root in
          let prefix = components(root)
          return !prefix.isEmpty && target.starts(with: prefix)
        }
      }) {
        return folder.id
      }
    }
    if let category = file.category.flatMap({ trimmedNonEmpty([$0]) }) {
      return folders.first { folder in
        folder.paths.contains { $0.contains("/" + category) || $0.contains("\\" + category) }
      }?.id
    }
    return nil
  }

  private static func components(_ path: String) -> [Substring] {
    path.split(whereSeparator: { $0 == "/" || $0 == "\\" })
  }
}
