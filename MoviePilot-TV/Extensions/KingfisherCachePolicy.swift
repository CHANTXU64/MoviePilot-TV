import Foundation
import Kingfisher

enum KingfisherCachePolicy {
  static let memoryExpirationSeconds: TimeInterval = 300

  static func apply(memoryOptimizationEnabled: Bool, to cache: ImageCache = .default) {
    var config = cache.memoryStorage.config
    config.totalCostLimit = (memoryOptimizationEnabled ? 250 : 300) * 1024 * 1024
    config.expiration = .seconds(memoryExpirationSeconds)
    cache.memoryStorage.config = config
  }
}
