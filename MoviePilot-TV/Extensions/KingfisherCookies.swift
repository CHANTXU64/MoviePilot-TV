import Foundation
import Kingfisher

extension AnyModifier {
  /// Kingfisher 插件：用于将共享 HTTPCookieStorage 中的 Cookie 注入到图片网络请求中
  /// 场景：当媒体服务器开启了图片防盗链，且需要通过已登录的 Session Cookie 访问缩略图时非常关键
  static var cookieModifier: AnyModifier {
    AnyModifier { request in
      var r = request
      if let url = r.url, let cookies = HTTPCookieStorage.shared.cookies(for: url) {
        let headers = HTTPCookie.requestHeaderFields(with: cookies)
        for (key, value) in headers {
          r.setValue(value, forHTTPHeaderField: key)
        }
      }
      return r
    }
  }
}
