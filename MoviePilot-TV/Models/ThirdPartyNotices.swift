import Foundation

/// 应用里带着的一个第三方组件和它的许可，系统页「第三方软件许可」逐个列出。
nonisolated struct ThirdPartyNotice: Identifiable, Hashable, Sendable {
  /// 一份许可原文：随应用打包的 `Licenses/<resource>.txt`，从组件发布的许可文件原样复制，不改动。
  nonisolated struct LicenseText: Hashable, Sendable {
    /// 一个组件有多份原文时的标题。
    let title: String?
    let resource: String
  }

  let name: String
  /// 许可的简称，列表行右侧显示。
  let license: String
  /// 给用户看的说明：第一条是用途（列表聚焦时显示在右侧），之后是版权和源码或项目主页。
  let details: [String]
  let texts: [LicenseText]

  var id: String { name }
}

/// 第三方组件清单。播放内核 AetherEngine 和它带进来的组件按引擎的 docs/licensing.md 要求声明：
/// 引擎指向构建用的确切版本，附 LGPL v3 和它引用的 GPL v3 原文；FFmpeg、libzvbi 附许可原文和构建源码
/// （FFmpegBuild 的构建脚本里公开了对 FFmpeg 的补丁和对 libzvbi 的删改）；libdovi、Anime4K 附原作者的版权声明。
/// AetherEngine 包里的 SMBClient 只在链接 `AetherEngineSMB` 时才编入，本应用不链接，不列出。
nonisolated enum ThirdPartyNotices {
  /// 和 Package.resolved 里锁定的版本一致（有测试核对）：LGPL 要求指向构建时用的那一版源码。
  static let aetherEngineVersion = "7.67.0"
  static let ffmpegBuildVersion = "3.15.0"

  private static let ffmpegBuildSource =
    "源码（FFmpegBuild \(ffmpegBuildVersion)）：https://github.com/superuser404notfound/FFmpegBuild/tree/\(ffmpegBuildVersion)"

  static let all: [ThirdPartyNotice] = [
    ThirdPartyNotice(
      name: "AetherEngine",
      license: "LGPL-3.0",
      details: [
        "播放内核，负责应用内播放。",
        "Copyright (C) 2026 Vincent Herbst",
        "源码（\(aetherEngineVersion)）：https://github.com/superuser404notfound/AetherEngine/tree/\(aetherEngineVersion)",
      ],
      texts: [
        .init(title: "AetherEngine 许可", resource: "AetherEngine-LICENSE"),
        .init(title: "GNU General Public License v3", resource: "GPL-3.0"),
      ]),
    ThirdPartyNotice(
      name: "FFmpeg",
      license: "LGPL-2.1+",
      details: ["解码音视频，读取各种格式的视频文件。", ffmpegBuildSource, "项目主页：https://ffmpeg.org"],
      texts: [.init(title: nil, resource: "LGPL-2.1")]),
    ThirdPartyNotice(
      name: "dav1d",
      license: "BSD-2-Clause",
      details: ["解码 AV1 视频。", "项目主页：https://code.videolan.org/videolan/dav1d"],
      texts: [.init(title: nil, resource: "dav1d-BSD-2-Clause")]),
    ThirdPartyNotice(
      name: "zimg",
      license: "WTFPL",
      details: ["缩放画面、转换色彩。", "项目主页：https://github.com/sekrit-twc/zimg"],
      texts: [.init(title: nil, resource: "zimg-WTFPL")]),
    ThirdPartyNotice(
      name: "libzvbi",
      license: "LGPL-2.0+ / MIT",
      details: ["解码图文电视（Teletext）字幕。", ffmpegBuildSource],
      texts: [
        .init(title: "GNU Lesser General Public License v2.1", resource: "LGPL-2.1"),
        .init(title: "部分文件的 MIT 许可", resource: "libzvbi-ure-MIT"),
      ]),
    ThirdPartyNotice(
      name: "libdovi",
      license: "MIT",
      details: [
        "处理杜比视界的画面信息。",
        "Copyright (c) quietvoid and contributors",
        "项目主页：https://github.com/quietvoid/dovi_tool",
      ],
      texts: [.init(title: nil, resource: "LibDovi-LICENSE")]),
    ThirdPartyNotice(
      name: "Anime4K",
      license: "MIT",
      details: ["动画画面的放大算法。", "Copyright (c) 2019-2021 bloc97", "项目主页：https://github.com/bloc97/Anime4K"],
      texts: [.init(title: nil, resource: "Anime4K-MIT")]),
    ThirdPartyNotice(
      name: "Swiftfin",
      license: "MPL-2.0",
      details: [
        "播放界面改自 Swiftfin。",
        "Copyright (c) Jellyfin & Jellyfin Contributors",
        "改动后的源码：https://github.com/CHANTXU64/MoviePilot-TV",
        "项目主页：https://github.com/jellyfin/Swiftfin",
        "许可原文：https://mozilla.org/MPL/2.0/",
      ],
      texts: []),
    ThirdPartyNotice(
      name: "Kingfisher",
      license: "MIT",
      details: ["加载和缓存海报图片。", "项目主页：https://github.com/onevcat/Kingfisher"],
      texts: [.init(title: nil, resource: "Kingfisher-LICENSE")]),
    ThirdPartyNotice(
      name: "MediaAccessibilityKit",
      license: "MIT",
      details: ["按系统的字幕样式设置显示字幕。", "项目主页：https://github.com/LePips/MediaAccessibilityKit"],
      texts: [.init(title: nil, resource: "MediaAccessibilityKit-LICENSE")]),
    ThirdPartyNotice(
      name: "SwiftDate",
      license: "MIT",
      details: ["处理日期和时间。", "项目主页：https://github.com/malcommac/SwiftDate"],
      texts: [.init(title: nil, resource: "SwiftDate-LICENSE")]),
    ThirdPartyNotice(
      name: "SwiftUI-Flow",
      license: "MIT",
      details: ["让标签等内容自动换行排列。", "项目主页：https://github.com/tevelee/SwiftUI-Flow"],
      texts: [.init(title: nil, resource: "SwiftUI-Flow-LICENSE")]),
  ]

  /// 随应用打包的许可原文；文件缺失或读不出时为 nil。
  static func text(_ resource: String, in bundle: Bundle = .main) -> String? {
    guard let url = bundle.url(forResource: resource, withExtension: "txt") else { return nil }
    return try? String(contentsOf: url, encoding: .utf8)
  }
}
