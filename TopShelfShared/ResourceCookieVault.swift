import Foundation

nonisolated final class ResourceCookieVault: @unchecked Sendable {
  private let lock = NSLock()
  private var cookies: [HTTPCookie] = []

  func update(from response: HTTPURLResponse, for url: URL) {
    let fields = response.allHeaderFields.reduce(into: [String: String]()) { result, entry in
      guard let key = entry.key as? String else { return }
      result[key] = String(describing: entry.value)
    }
    let received = HTTPCookie.cookies(withResponseHeaderFields: fields, for: url)
    guard !received.isEmpty else { return }

    lock.lock()
    defer { lock.unlock() }
    for cookie in received {
      cookies.removeAll {
        $0.name == cookie.name && $0.domain == cookie.domain && $0.path == cookie.path
      }
      if cookie.expiresDate.map({ $0 > Date() }) ?? true {
        cookies.append(cookie)
      }
    }
  }

  func cookieHeader(for url: URL) -> String? {
    lock.lock()
    cookies.removeAll { !($0.expiresDate.map { $0 > Date() } ?? true) }
    let matchingCookies = cookies.filter { cookie in
      guard let host = url.host?.lowercased() else { return false }
      let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
      guard host == domain || host.hasSuffix(".\(domain)") else { return false }
      guard !cookie.isSecure || url.scheme?.lowercased() == "https" else { return false }
      let path = cookie.path.isEmpty ? "/" : cookie.path
      guard url.path.hasPrefix(path) else { return false }
      return path.hasSuffix("/") || url.path.count == path.count
        || url.path.dropFirst(path.count).first == "/"
    }
    lock.unlock()
    guard !matchingCookies.isEmpty else { return nil }
    return HTTPCookie.requestHeaderFields(with: matchingCookies)["Cookie"]
  }

  func snapshot() -> [HTTPCookie] {
    lock.lock()
    defer { lock.unlock() }
    return cookies
  }

  func replace(with cookies: [HTTPCookie]) {
    lock.lock()
    self.cookies = cookies
    lock.unlock()
  }
}
