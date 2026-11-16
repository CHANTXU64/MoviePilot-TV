import XCTest

@testable import MoviePilot_TV

/// 系统页「第三方软件许可」：许可原文真的打包进了应用，源码指向的版本和实际构建用的一致，新加依赖不会漏列。
final class ThirdPartyNoticesTests: XCTestCase {
  /// 每份原文里必须有的版权行或标题，证明打包进应用的是对应组件的原文。
  private static let markers: [String: [String]] = [
    "AetherEngine-LICENSE": [
      "Copyright (C) 2026 Vincent Herbst", "APP STORE / DRM EXCEPTION", "GNU LESSER GENERAL PUBLIC LICENSE",
    ],
    "GPL-3.0": ["GNU GENERAL PUBLIC LICENSE", "Version 3, 29 June 2007", "END OF TERMS AND CONDITIONS"],
    "LGPL-2.1": ["GNU LESSER GENERAL PUBLIC LICENSE", "Version 2.1, February 1999", "END OF TERMS AND CONDITIONS"],
    "dav1d-BSD-2-Clause": ["VideoLAN and dav1d authors"],
    "zimg-WTFPL": ["DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE"],
    "libzvbi-ure-MIT": ["Computing Research Labs"],
    "LibDovi-LICENSE": ["Copyright (c) quietvoid and contributors"],
    "Anime4K-MIT": ["Copyright (c) 2019-2021 bloc97"],
    "Kingfisher-LICENSE": ["Copyright (c) 2019 Wei Wang"],
    "MediaAccessibilityKit-LICENSE": ["Copyright (c) 2026 Ethan Pippin"],
    "SwiftDate-LICENSE": ["Copyright (c) 2018 Daniele Margutti"],
    "SwiftUI-Flow-LICENSE": ["Copyright (c) 2026 Laszlo Teveli"],
  ]

  /// Package.resolved 里的包 → 清单里的组件名。
  private static let packageNotices: [String: String] = [
    "aetherengine": "AetherEngine",
    "ffmpegbuild": "FFmpeg",
    "libdovi": "libdovi",
    "kingfisher": "Kingfisher",
    "mediaaccessibilitykit": "MediaAccessibilityKit",
    "swiftdate": "SwiftDate",
    "swiftui-flow": "SwiftUI-Flow",
  ]
  /// 解析进来但不编入应用的包：SMBClient 只在链接 AetherEngineSMB 时才编入，本应用只链接 AetherEngine。
  private static let unlinkedPackages: Set<String> = ["smbclient"]

  func testEveryLicenseTextIsBundledWithTheApp() throws {
    let resources = Set(ThirdPartyNotices.all.flatMap { $0.texts.map(\.resource) })
    XCTAssertEqual(resources, Set(Self.markers.keys))
    for resource in resources {
      let text = try XCTUnwrap(ThirdPartyNotices.text(resource), "应用里没有 \(resource).txt")
      for marker in Self.markers[resource] ?? [] {
        XCTAssertTrue(text.contains(marker), "\(resource).txt 里没有「\(marker)」")
      }
    }
  }

  func testSourceLinksPointAtTheResolvedPackageVersions() throws {
    let pins = try Self.resolvedPins()
    XCTAssertEqual(pins["aetherengine"], ThirdPartyNotices.aetherEngineVersion)
    XCTAssertEqual(pins["ffmpegbuild"], ThirdPartyNotices.ffmpegBuildVersion)
    let aether = try XCTUnwrap(ThirdPartyNotices.all.first { $0.name == "AetherEngine" })
    XCTAssertTrue(
      aether.details.contains { $0.contains("AetherEngine/tree/\(ThirdPartyNotices.aetherEngineVersion)") })
  }

  func testEveryResolvedPackageIsListed() throws {
    let names = Set(ThirdPartyNotices.all.map(\.name))
    XCTAssertEqual(names.count, ThirdPartyNotices.all.count, "组件名重复")
    for identity in try Self.resolvedPins().keys where !Self.unlinkedPackages.contains(identity) {
      let name = try XCTUnwrap(Self.packageNotices[identity], "新依赖 \(identity) 还没加进第三方软件许可")
      XCTAssertTrue(names.contains(name), "\(identity) 对应的「\(name)」不在清单里")
    }
  }

  func testDetailShowsDescriptionThenEveryFullText() throws {
    let aether = try XCTUnwrap(ThirdPartyNotices.all.first { $0.name == "AetherEngine" })
    let blocks = SystemView.licenseBlocks(aether)
    let texts = blocks.map { String($0.text.characters) }
    XCTAssertEqual(texts.first, "许可：\(aether.license)")
    XCTAssertEqual(Array(texts.dropFirst().prefix(aether.details.count)), aether.details)
    let headings = blocks.filter { $0.style == .heading }.map { String($0.text.characters) }
    XCTAssertEqual(headings, aether.texts.compactMap(\.title))
    // 两份原文都完整接上：LGPL v3 和 GPL v3 各自的结尾段落都在。
    XCTAssertTrue(texts.contains { $0.contains("permanent authorization for you to choose that version for the") })
    XCTAssertTrue(texts.contains { $0.contains("<https://www.gnu.org/licenses/why-not-lgpl.html>") })
  }

  func testMissingTextIsReportedInsteadOfShowingNothing() {
    let notice = ThirdPartyNotice(
      name: "Missing", license: "MIT", details: ["用途"], texts: [.init(title: nil, resource: "NoSuchLicense")])
    let texts = SystemView.licenseBlocks(notice).map { String($0.text.characters) }
    XCTAssertEqual(texts.last, "许可原文读取失败")
  }

  private static func resolvedPins() throws -> [String: String] {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    let url = root.appendingPathComponent(
      "MoviePilot-TV.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved")
    struct Resolved: Decodable {
      struct Pin: Decodable {
        struct State: Decodable { let version: String? }
        let identity: String
        let state: State
      }
      let pins: [Pin]
    }
    let resolved = try JSONDecoder().decode(Resolved.self, from: Data(contentsOf: url))
    return Dictionary(uniqueKeysWithValues: resolved.pins.map { ($0.identity, $0.state.version ?? "") })
  }
}
