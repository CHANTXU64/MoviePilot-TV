import Foundation

func containsTokensInOrder(
  _ source: some StringProtocol,
  _ tokens: [String]
) -> Bool {
  let source = String(source)
  var searchStart = source.startIndex
  for token in tokens {
    guard let range = source.range(of: token, range: searchStart..<source.endIndex) else {
      return false
    }
    searchStart = range.upperBound
  }
  return true
}

func containsTrimmedLineSequence(
  _ source: some StringProtocol,
  _ expectedLines: [String]
) -> Bool {
  let sourceLines = String(source)
    .split(separator: "\n")
    .map { $0.trimmingCharacters(in: .whitespaces) }
  let expectedLines = expectedLines.map { $0.trimmingCharacters(in: .whitespaces) }
  guard !expectedLines.isEmpty, expectedLines.count <= sourceLines.count else { return false }

  for start in 0...(sourceLines.count - expectedLines.count) {
    if Array(sourceLines[start..<(start + expectedLines.count)]) == expectedLines {
      return true
    }
  }
  return false
}
