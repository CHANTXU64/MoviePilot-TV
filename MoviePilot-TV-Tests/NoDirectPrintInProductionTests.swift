import Foundation
import XCTest

/// F-060 回归：生产源码不得直接调用 `print`。
///
/// 项目有统一的 `Logger` 外观（`Logger.swift`），其默认处理器 `PrintLogHandler`
/// 只在 `#if DEBUG` 下输出；而散落各处的直接 `print` 会绕过这个开关，
/// 在 Release 构建里照样执行并写出用户名、种子/媒体标题、过滤规则名、服务器名、
/// 后端报错与搜索词等内容。此前生产端共 67 处直接 `print`、散在 16 个文件。
///
/// 唯一被允许的 `print` 在 `Logger.swift` 的 `PrintLogHandler` 内（且被 `#if DEBUG` 包住），
/// 本检查按文件名排除它，其余生产源码一律要求走 `Logger.*`。
///
/// 这是源码 lint 而非行为断言：经 `#filePath` 定位测试文件所在仓库，
/// 因而与工作副本路径无关；定位失败时跳过而不是误报。
final class NoDirectPrintInProductionTests: XCTestCase {

  /// 允许保留 `print` 的唯一文件（其 `print` 位于 `#if DEBUG` 内，是 Logger 的最终出口）。
  private static let allowedFileNames: Set<String> = ["Logger.swift"]

  func testProductionSourcesContainNoDirectPrint() throws {
    let root = try Self.repositoryRoot()
    let productionDir = root.appendingPathComponent("MoviePilot-TV", isDirectory: true)

    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: productionDir.path, isDirectory: &isDirectory),
      isDirectory.boolValue
    else {
      throw XCTSkip("未能在 \(root.path) 下找到生产源码目录，跳过 print 检查")
    }

    let offenders =
      Self.swiftFiles(under: productionDir)
      .filter { !Self.allowedFileNames.contains($0.lastPathComponent) }
      .flatMap { Self.directPrintSites(in: $0) }
      .sorted()

    XCTAssertTrue(
      offenders.isEmpty,
      """
      生产源码出现直接 `print`，它会绕过 Logger 的 DEBUG 开关并在 Release 保留。
      请改用 Logger.debug / info / warning / error：
      \(offenders.joined(separator: "\n"))
      """)
  }

  // MARK: - 定位与扫描

  /// 本文件位于 `<repo>/MoviePilot-TV-Tests/`，上溯两级即仓库根。
  private static func repositoryRoot() throws -> URL {
    let testFile = URL(fileURLWithPath: #filePath)
    let root = testFile.deletingLastPathComponent().deletingLastPathComponent()

    guard
      FileManager.default.fileExists(
        atPath: root.appendingPathComponent("MoviePilot-TV").path)
    else {
      throw XCTSkip("无法从 \(testFile.path) 定位仓库根，跳过 print 检查")
    }
    return root
  }

  private static func swiftFiles(under directory: URL) -> [URL] {
    guard
      let enumerator = FileManager.default.enumerator(
        at: directory, includingPropertiesForKeys: nil)
    else { return [] }

    return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
  }

  /// 返回 `文件名:行号` 形式的直接 `print` 调用点。
  private static func directPrintSites(in file: URL) -> [String] {
    guard let source = try? String(contentsOf: file, encoding: .utf8) else { return [] }

    // 先在「挖空字符串字面量与注释」的副本上匹配，
    // 避免把 `hasSameMutationFingerprint(`、注释里的 print、或字符串里的文本算进来。
    return codeOnlyLines(source).enumerated().compactMap { offset, code in
      guard code.range(of: #"(?<![\w.])print\s*\("#, options: .regularExpression) != nil else {
        return nil
      }
      return "\(file.lastPathComponent):\(offset + 1)"
    }
  }

  private enum ScanState {
    case code
    case lineComment
    case blockComment(depth: Int)
    /// 字符串字面量：原始串的 `#` 数量；是否为 `"""` 多行串。
    case string(rawHashes: Int, multiline: Bool)
  }

  /// 按行返回源码副本：字符串字面量、`//` 行注释与 `/* */` 块注释（支持嵌套）
  /// 全部被空格挖空，换行原样保留以维持行号。
  private static func codeOnlyLines(_ source: String) -> [String] {
    let chars = Array(source)
    var output: [Character] = []
    output.reserveCapacity(chars.count)
    var state = ScanState.code
    var index = 0

    /// 从 `position` 起是否为 `#"` 形式，是则返回 `#` 的数量（用于开定界符）。
    func rawHashes(at position: Int) -> Int {
      let count = countHashes(at: position)
      guard position + count < chars.count, chars[position + count] == "\"" else { return 0 }
      return count
    }

    /// 从 `position` 起连续 `#` 的数量（用于闭定界符，其后面不要求再有引号）。
    func countHashes(at position: Int) -> Int {
      var hashes = 0
      var cursor = position
      while cursor < chars.count, chars[cursor] == "#" { hashes += 1; cursor += 1 }
      return hashes
    }

    /// 判断 `position` 处（已确认是 `"`）是否为 `"""` 多行串开头。
    func isMultilineStart(at position: Int) -> Bool {
      position + 2 < chars.count && chars[position + 1] == "\"" && chars[position + 2] == "\""
    }

    func blank(_ character: Character) {
      output.append(character == "\n" ? "\n" : " ")
    }

    while index < chars.count {
      let char = chars[index]
      let next = index + 1 < chars.count ? chars[index + 1] : nil

      switch state {
      case .lineComment:
        blank(char)
        if char == "\n" { state = .code }
        index += 1

      case .blockComment(let depth):
        if char == "*", next == "/" {
          blank(char)
          blank("/")
          index += 2
          state = depth <= 1 ? .code : .blockComment(depth: depth - 1)
        } else if char == "/", next == "*" {
          blank(char)
          blank("/")
          index += 2
          state = .blockComment(depth: depth + 1)
        } else {
          blank(char)
          index += 1
        }

      case .string(let hashes, let multiline):
        // 结束定界符：`"`（多行串为 `"""`）后跟等量的 `#`。
        let isClosingQuote: Bool
        if multiline {
          isClosingQuote =
            char == "\"" && index + 2 < chars.count && chars[index + 1] == "\""
            && chars[index + 2] == "\""
        } else {
          isClosingQuote = char == "\""
        }

        if isClosingQuote,
          hashes == 0 || countHashes(at: index + (multiline ? 3 : 1)) >= hashes
        {
          let consumed = (multiline ? 3 : 1) + hashes
          for offset in 0..<consumed { blank(chars[index + offset]) }
          index += consumed
          state = .code
        } else if !multiline, hashes == 0, char == "\\", let escaped = next {
          // 非原始串中的转义：连同被转义字符一起挖空。
          blank(char)
          blank(escaped)
          index += 2
        } else {
          blank(char)
          index += 1
        }

      case .code:
        if char == "/", next == "/" {
          blank(char)
          blank("/")
          index += 2
          state = .lineComment
        } else if char == "/", next == "*" {
          blank(char)
          blank("/")
          index += 2
          state = .blockComment(depth: 1)
        } else if char == "#" {
          let hashes = rawHashes(at: index)
          if hashes > 0 {
            let quoteIndex = index + hashes
            let multiline = isMultilineStart(at: quoteIndex)
            let consumed = hashes + (multiline ? 3 : 1)
            for offset in 0..<consumed { blank(chars[index + offset]) }
            index += consumed
            state = .string(rawHashes: hashes, multiline: multiline)
          } else {
            output.append(char)
            index += 1
          }
        } else if char == "\"" {
          let multiline = isMultilineStart(at: index)
          let consumed = multiline ? 3 : 1
          for offset in 0..<consumed { blank(chars[index + offset]) }
          index += consumed
          state = .string(rawHashes: 0, multiline: multiline)
        } else {
          output.append(char)
          index += 1
        }
      }
    }

    return String(output).components(separatedBy: "\n")
  }
}
