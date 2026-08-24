import Foundation
import Kingfisher

enum KingfisherCachePolicy {
  static let memoryCostLimitBytes = 250 * 1024 * 1024
  static let memoryExpirationSeconds: TimeInterval = 300

  static func apply(to cache: ImageCache = .default) {
    var config = cache.memoryStorage.config
    config.totalCostLimit = memoryCostLimitBytes
    config.expiration = .seconds(memoryExpirationSeconds)
    cache.memoryStorage.config = config
  }
}
