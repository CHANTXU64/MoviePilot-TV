import CoreGraphics
import Foundation
import ImageIO
import Kingfisher
import TVServices
import UIKit
import UniformTypeIdentifiers

nonisolated enum TopShelfImageError: Error, Equatable {
  case invalidResponse
  case httpStatus(Int)
  case insecureRedirect
  case tooLarge
  case invalidImage
}

nonisolated final class TopShelfImageRedirectDelegate: NSObject,
  URLSessionTaskDelegate, @unchecked Sendable
{
  private let startedProtected: Bool
  private let baseURL: String
  private let token: String?
  private let cookieHeader: @Sendable (URL) -> String?
  private let lock = NSLock()
  private var hasLeftProtectedBoundary = false
  private var blockedInsecureRedirect = false

  init(
    startedProtected: Bool,
    baseURL: String,
    token: String?,
    cookieHeader: @escaping @Sendable (URL) -> String?
  ) {
    self.startedProtected = startedProtected
    self.baseURL = baseURL
    self.token = token
    self.cookieHeader = cookieHeader
  }

  var didBlockInsecureRedirect: Bool {
    lock.lock()
    defer { lock.unlock() }
    return blockedInsecureRedirect
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest,
    completionHandler: @escaping @Sendable (URLRequest?) -> Void
  ) {
    guard let destination = request.url else {
      completionHandler(nil)
      return
    }

    if response.url?.scheme?.lowercased() == "https",
      destination.scheme?.lowercased() == "http"
    {
      lock.lock()
      blockedInsecureRedirect = true
      lock.unlock()
      completionHandler(nil)
      return
    }

    lock.lock()
    let mayRetainProtection = startedProtected && !hasLeftProtectedBoundary
    let destinationIsProtected = isProtectedMoviePilotImageURL(destination, baseURL: baseURL)
    if mayRetainProtection, !destinationIsProtected {
      hasLeftProtectedBoundary = true
    }
    let shouldAuthenticate = mayRetainProtection && destinationIsProtected
    lock.unlock()

    var redirected = request
    redirected.setValue(nil, forHTTPHeaderField: "Authorization")
    redirected.setValue(nil, forHTTPHeaderField: "Cookie")
    if shouldAuthenticate {
      if let token {
        redirected.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
      }
      if let cookie = cookieHeader(destination) {
        redirected.setValue(cookie, forHTTPHeaderField: "Cookie")
      }
    }
    completionHandler(redirected)
  }
}

nonisolated func isBangumiImageHost(_ value: String) -> Bool {
  let host = value.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
  return ["bgm.tv", "bangumi.tv", "bangumi.lol"].contains { domain in
    host == domain || host.hasSuffix(".\(domain)")
  }
}

nonisolated func isBangumiImageURL(_ value: String) -> Bool {
  guard let host = URLComponents(string: value)?.host else { return false }
  return isBangumiImageHost(host)
}

nonisolated func bangumiImageProxyURL(_ imageURL: String, baseURL: String) -> String {
  guard isBangumiImageURL(imageURL) else { return imageURL }
  let rawBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
  guard !rawBaseURL.isEmpty else { return imageURL }

  let candidate = rawBaseURL.contains("://") ? rawBaseURL : "https://\(rawBaseURL)"
  guard let proxyComponents = URLComponents(string: candidate),
    let proxyScheme = proxyComponents.scheme?.lowercased(),
    ["http", "https"].contains(proxyScheme),
    let proxyHost = proxyComponents.host,
    !proxyHost.isEmpty,
    proxyComponents.fragment == nil,
    let sourceComponents = URLComponents(string: imageURL),
    let sourceHost = sourceComponents.host
  else {
    return imageURL
  }

  if let query = proxyComponents.percentEncodedQuery, !query.isEmpty {
    guard let encodedImageURL = encodeURIComponent(imageURL) else { return imageURL }
    return candidate + encodedImageURL
  }

  var normalizedBaseURL = candidate
  while normalizedBaseURL.hasSuffix("/") {
    normalizedBaseURL.removeLast()
  }
  if rawBaseURL.hasSuffix("/") {
    if sourceHost.caseInsensitiveCompare(proxyHost) == .orderedSame {
      return imageURL
    }
    let query = sourceComponents.percentEncodedQuery.map { "?\($0)" } ?? ""
    return normalizedBaseURL + sourceComponents.percentEncodedPath + query
  }

  return "\(normalizedBaseURL)/\(imageURL)"
}

nonisolated func isDefaultPlaceholderImageURL(_ value: String) -> Bool {
  guard let components = URLComponents(string: value),
    let host = components.host?.lowercased()
  else {
    return false
  }

  let path = components.path.lowercased()
  let isDoubanHost = host == "doubanio.com" || host.hasSuffix(".doubanio.com")
  if isDoubanHost {
    return path.contains("movie_default") || path.contains("tv_default")
      || path.contains("personage-default") || path.contains("celebrity-default")
  }

  let isBangumiHost = isBangumiImageHost(host)
  if isBangumiHost {
    return path.contains("no_icon")
  }

  let isAniListHost = host == "anilist.co" || host.hasSuffix(".anilist.co")
  return isAniListHost && path.contains("anilistcdn") && path.hasSuffix("/default.jpg")
}

nonisolated func displayImageURL(
  _ value: String?,
  baseURL: String,
  useImageCache: Bool,
  bangumiProxyEnabled: Bool,
  bangumiImageDomain: String?
) -> URL? {
  guard let value, !value.isEmpty else {
    return nil
  }

  let lowercasedValue = value.lowercased()
  guard lowercasedValue.hasPrefix("http://") || lowercasedValue.hasPrefix("https://") else {
    return URL(string: value)
  }

  if isBangumiImageURL(value), bangumiProxyEnabled {
    let proxiedValue = bangumiImageProxyURL(value, baseURL: bangumiImageDomain ?? "")
    guard let encodedUrl = encodeURIComponent(proxiedValue) else { return nil }
    var urlString = "\(baseURL)/api/v1/system/img/1?imgurl=\(encodedUrl)"
    if useImageCache {
      urlString += "&cache=true"
    }
    return URL(string: urlString)
  }

  guard let encodedUrl = encodeURIComponent(value) else {
    return nil
  }

  if useImageCache {
    return URL(string: "\(baseURL)/api/v1/system/cache/image?url=\(encodedUrl)")
  }

  if value.contains("doubanio.com") {
    return URL(string: "\(baseURL)/api/v1/system/img/0?imgurl=\(encodedUrl)")
  }

  return URL(string: value)
}

nonisolated func isMoviePilotAPIURL(_ url: URL, baseURL: String) -> Bool {
  guard let server = URLComponents(string: baseURL),
    let target = URLComponents(url: url, resolvingAgainstBaseURL: false),
    server.scheme?.lowercased() == target.scheme?.lowercased(),
    server.host?.lowercased() == target.host?.lowercased()
  else { return false }

  let serverPort = server.port ?? (server.scheme?.lowercased() == "https" ? 443 : 80)
  let targetPort = target.port ?? (target.scheme?.lowercased() == "https" ? 443 : 80)
  guard serverPort == targetPort else { return false }

  let serverPath = server.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
  let apiPath = serverPath.isEmpty ? "/api/v1/" : "/\(serverPath)/api/v1/"
  return url.path.hasPrefix(apiPath) && !url.path.split(separator: "/").contains("..")
}

nonisolated func isProtectedMoviePilotImageURL(_ url: URL, baseURL: String) -> Bool {
  guard isMoviePilotAPIURL(url, baseURL: baseURL),
    let server = URLComponents(string: baseURL)
  else { return false }

  let serverPath = server.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
  let apiPath = serverPath.isEmpty ? "/api/v1" : "/\(serverPath)/api/v1"
  return url.path.hasPrefix("\(apiPath)/system/img/")
    || url.path == "\(apiPath)/system/cache/image"
}

nonisolated func encodeURIComponent(_ value: String) -> String? {
  let allowed = CharacterSet(
    charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")
  return value.addingPercentEncoding(withAllowedCharacters: allowed)
}

nonisolated enum TopShelfImageLoader {
  /// 字节消费和 ImageIO 工作离开 MainActor，避免更新主屏推荐占住详情页交互。
  @concurrent
  static func downloadTopShelfImage(
    request: URLRequest,
    transport: URLSession,
    redirectDelegate: TopShelfImageRedirectDelegate,
    maximumBytes: Int,
    maximumPixels: Int
  ) async throws -> TopShelfImageResource {
    let (bytes, response) = try await transport.bytes(for: request, delegate: redirectDelegate)
    defer { bytes.task.cancel() }
    if redirectDelegate.didBlockInsecureRedirect {
      throw TopShelfImageError.insecureRedirect
    }
    guard let httpResponse = response as? HTTPURLResponse else {
      throw TopShelfImageError.invalidResponse
    }
    guard (200...299).contains(httpResponse.statusCode) else {
      throw TopShelfImageError.httpStatus(httpResponse.statusCode)
    }
    if httpResponse.expectedContentLength > Int64(maximumBytes) {
      throw TopShelfImageError.tooLarge
    }

    var data = Data()
    data.reserveCapacity(
      min(maximumBytes, max(0, Int(httpResponse.expectedContentLength)))
    )
    for try await byte in bytes {
      if data.count >= maximumBytes {
        bytes.task.cancel()
        throw TopShelfImageError.tooLarge
      }
      data.append(byte)
    }
    try Task.checkCancellation()
    return try originalImage(from: data, maximumPixels: maximumPixels)
  }

  static let cardShape: TVTopShelfSectionedItem.ImageShape = .hdtv
  static var cardSize: CGSize { TVTopShelfSectionedContent.imageSize(for: cardShape) }

  /// 只读下载数据的编码格式和尺寸，不展开原图像素。
  static func originalImage(from data: Data, maximumPixels: Int = 40_000_000) throws
    -> TopShelfImageResource
  {
    guard !data.isEmpty,
      let source = CGImageSourceCreateWithData(
        data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
      let type = CGImageSourceGetType(source),
      let fileExtension = UTType(type as String)?.preferredFilenameExtension,
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
      let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
      width.intValue > 0, height.intValue > 0
    else { throw TopShelfImageError.invalidImage }
    guard maximumPixels > 0, width.intValue <= maximumPixels / height.intValue else {
      throw TopShelfImageError.tooLarge
    }
    return TopShelfImageResource(data: data, fileExtension: fileExtension)
  }

  /// 两份图片分别从下载数据直接降采样，不展开原图或把原图写入缓存。
  @concurrent
  static func prepareImages(from data: Data) async throws -> (
    card: TopShelfImageResource, background: TopShelfImageResource
  ) {
    try Task.checkCancellation()
    _ = try originalImage(from: data)
    let card = try downsampleImage(from: data, size: cardSize, scale: 2, quality: 0.86)
    try Task.checkCancellation()
    let edge = MediaDetailImageSizing.longEdgePixels
    let background = try downsampleImage(
      from: data, size: CGSize(width: edge, height: edge), scale: 1, quality: 0.9)
    return (card, background)
  }

  private static func downsampleImage(
    from data: Data, size: CGSize, scale: CGFloat, quality: CGFloat
  ) throws -> TopShelfImageResource {
    return try autoreleasepool {
      let processor = DownsamplingImageProcessor(size: size)
      guard
        let image = processor.process(
          item: .data(data), options: KingfisherParsedOptionsInfo([.scaleFactor(scale)])),
        let encoded = image.jpegData(compressionQuality: quality)
      else { throw TopShelfImageError.invalidImage }
      return TopShelfImageResource(data: encoded, fileExtension: "jpg")
    }
  }
}

nonisolated func appendPercentEncodedQueryParams(
  to components: inout URLComponents,
  params: [String: String?]
) {
  let additions = params.compactMap { name, value -> String? in
    guard let value,
      let encodedName = encodeURIComponent(name),
      let encodedValue = encodeURIComponent(value)
    else {
      return nil
    }
    return "\(encodedName)=\(encodedValue)"
  }
  guard !additions.isEmpty else { return }
  let suffix = additions.joined(separator: "&")
  if let existing = components.percentEncodedQuery, !existing.isEmpty {
    components.percentEncodedQuery = existing + "&" + suffix
  } else {
    components.percentEncodedQuery = suffix
  }
}
