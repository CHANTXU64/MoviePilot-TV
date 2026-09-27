import Foundation

/// Resolve the configured group against the executable's signing metadata. Some
/// sideloaders append the signing team to group names without rewriting Info.plist.
nonisolated enum TopShelfAppGroup {
  private static let mainIdentifier = resolve(in: .main)

  static func identifier(in bundle: Bundle) -> String? {
    bundle.bundleURL == Bundle.main.bundleURL ? mainIdentifier : resolve(in: bundle)
  }

  private static func resolve(in bundle: Bundle) -> String? {
    let entitlements = bundle.executableURL.flatMap { try? Data(contentsOf: $0, options: .mappedIfSafe) }
      .flatMap { TopShelfSigningMetadata.entitlements(in: $0) }
    return identifier(
      configured: bundle.object(forInfoDictionaryKey: "TopShelfAppGroupIdentifier") as? String,
      entitlements: entitlements)
  }

  static func identifier(configured: String?, entitlements: [String: Any]?) -> String? {
    guard let configured, isValid(configured) else { return nil }
    // Simulator entitlements can live in a Mach-O section instead of a signature.
    // Container/Keychain APIs still enforce authorization for the configured group.
    guard let entitlements else { return configured }
    guard let groups = entitlements["com.apple.security.application-groups"] as? [String] else {
      return nil
    }
    if groups.contains(configured) { return configured }
    guard let team = entitlements["com.apple.developer.team-identifier"] as? String,
      team.range(of: "^[A-Z0-9]{10}$", options: .regularExpression) != nil
    else { return nil }
    let renamed = configured + "." + team
    return groups.contains(renamed) ? renamed : nil
  }

  private static func isValid(_ identifier: String) -> Bool {
    identifier.hasPrefix("group.") && identifier.count > 6
      && !identifier.contains("$")
      && identifier.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
  }
}

/// Read the XML entitlement slot from Apple's public Mach-O/code-signature format.
/// This only selects a group; the OS remains the authority for container access.
nonisolated enum TopShelfSigningMetadata {
  static func entitlements(in data: Data) -> [String: Any]? {
    #if arch(arm64)
      let cpuType: UInt32 = 0x0100000c
    #else
      let cpuType: UInt32 = 0x01000007
    #endif
    return entitlements(in: data, cpuType: cpuType)
  }

  static func entitlements(in data: Data, cpuType: UInt32) -> [String: Any]? {
    guard let slice = executableSlice(data, cpuType: cpuType),
      slice.uint32(at: 0) == 0xfeedfacf,
      let count = slice.uint32(at: 16), let size = slice.uint32(at: 20),
      let commands = slice.bytes(at: 32, count: Int(size)), Int(count) <= commands.count / 8
    else { return nil }
    var offset = 0
    var signedEntitlements: [String: Any]?
    for _ in 0..<count {
      guard let command = commands.uint32(at: offset),
        let length = commands.uint32(at: offset + 4), length >= 8,
        let record = commands.bytes(at: offset, count: Int(length))
      else { return nil }
      #if targetEnvironment(simulator)
        if command == 0x19, let entitlements = simulatorEntitlements(in: record, executable: slice) {
          return entitlements
        }
      #endif
      if command == 0x1d { // LC_CODE_SIGNATURE
        guard let start = record.uint32(at: 8), let size = record.uint32(at: 12),
          let signature = slice.bytes(at: Int(start), count: Int(size))
        else { return nil }
        signedEntitlements = entitlements(inSignature: signature)
      }
      offset += Int(length)
    }
    return signedEntitlements
  }

  #if targetEnvironment(simulator)
    private static func simulatorEntitlements(in segment: Data, executable: Data) -> [String: Any]? {
      guard let count = segment.uint32(at: 64), segment.count >= 72,
        Int(count) <= (segment.count - 72) / 80 else { return nil }
      for index in 0..<Int(count) {
        let section = 72 + index * 80
        guard let name = segment.bytes(at: section, count: 16),
          String(bytes: name.prefix(while: { $0 != 0 }), encoding: .utf8) == "__entitlements",
          let size = segment.uint64(at: section + 40, bigEndian: false),
          let length = Int(exactly: size), let offset = segment.uint32(at: section + 48),
          let xml = executable.bytes(at: Int(offset), count: length)
        else { continue }
        return (try? PropertyListSerialization.propertyList(from: xml, format: nil)) as? [String: Any]
      }
      return nil
    }
  #endif

  private static func executableSlice(_ data: Data, cpuType: UInt32) -> Data? {
    if data.uint32(at: 0) == 0xfeedfacf { return data }
    guard let magic = data.uint32(at: 0, bigEndian: true),
      magic == 0xcafebabe || magic == 0xcafebabf,
      let count = data.uint32(at: 4, bigEndian: true)
    else { return nil }
    let recordSize = magic == 0xcafebabf ? 32 : 20
    guard data.count >= 8, Int(count) <= (data.count - 8) / recordSize else { return nil }
    for index in 0..<Int(count) {
      let record = 8 + index * recordSize
      guard data.uint32(at: record, bigEndian: true) == cpuType else { continue }
      let start: UInt64?
      let length: UInt64?
      if recordSize == 32 {
        start = data.uint64(at: record + 8)
        length = data.uint64(at: record + 16)
      } else {
        start = data.uint32(at: record + 8, bigEndian: true).map(UInt64.init)
        length = data.uint32(at: record + 12, bigEndian: true).map(UInt64.init)
      }
      guard let start, let length, let offset = Int(exactly: start),
        let size = Int(exactly: length)
      else { return nil }
      return data.bytes(at: offset, count: size)
    }
    return nil
  }

  private static func entitlements(inSignature data: Data) -> [String: Any]? {
    guard data.uint32(at: 0, bigEndian: true) == 0xfade0cc0,
      let length = data.uint32(at: 4, bigEndian: true),
      let blob = data.bytes(at: 0, count: Int(length)),
      let count = blob.uint32(at: 8, bigEndian: true),
      blob.count >= 12, Int(count) <= (blob.count - 12) / 8
    else { return nil }
    for index in 0..<Int(count) {
      let record = 12 + index * 8
      guard blob.uint32(at: record, bigEndian: true) == 5 else { continue }
      guard let offset = blob.uint32(at: record + 4, bigEndian: true),
        blob.uint32(at: Int(offset), bigEndian: true) == 0xfade7171,
        let size = blob.uint32(at: Int(offset) + 4, bigEndian: true), size >= 8,
        let xml = blob.bytes(at: Int(offset) + 8, count: Int(size) - 8)
      else { return nil }
      return (try? PropertyListSerialization.propertyList(from: xml, format: nil)) as? [String: Any]
    }
    return nil
  }
}

private extension Data {
  nonisolated func bytes(at offset: Int, count length: Int) -> Data? {
    guard offset >= 0, length >= 0, offset <= count, length <= count - offset else { return nil }
    return subdata(in: offset..<(offset + length))
  }

  nonisolated func uint32(at offset: Int, bigEndian: Bool = false) -> UInt32? {
    guard offset >= 0, offset <= count, count - offset >= 4 else { return nil }
    let bytes = self[offset..<(offset + 4)]
    return (bigEndian ? Array(bytes) : Array(bytes.reversed())).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
  }

  nonisolated func uint64(at offset: Int, bigEndian: Bool = true) -> UInt64? {
    guard let first = uint32(at: offset, bigEndian: bigEndian),
      let second = uint32(at: offset + 4, bigEndian: bigEndian) else { return nil }
    return bigEndian ? UInt64(first) << 32 | UInt64(second) : UInt64(second) << 32 | UInt64(first)
  }
}
