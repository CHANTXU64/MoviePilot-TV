import Combine
import Foundation

/// 影视来源选项。先显示内置来源，加载到后端目录后按目录替换；目录不可用或为空时保留内置来源。
@MainActor
final class MediaSourceOptionsModel: ObservableObject {
  // 显式非隔离析构，避开 tvOS 18 的隔离析构回部署崩溃。
  nonisolated deinit {}

  @Published private(set) var options = MediaSourceOption.builtinMedia
  private let apiService: APIService

  init(apiService: APIService = .shared) {
    self.apiService = apiService
  }

  func load() async {
    do {
      let options = MediaSourceInfo.videoSources(from: try await apiService.fetchMediaSources())
      guard !Task.isCancelled, !options.isEmpty else { return }
      self.options = options
    } catch is CancellationError {
      return
    } catch {
      Logger.error("[MediaSourceOptions] 加载媒体来源失败: \(error)")
    }
  }

  /// 当前值不在目录中时仍列出，保证选择器显示的来源就是实际提交的来源。
  func options(including current: MediaSearchSource?) -> [MediaSourceOption] {
    guard let current, !options.contains(where: { $0.source == current }) else { return options }
    return options + [MediaSourceOption(source: current, title: current.title)]
  }

  func title(for source: MediaSearchSource) -> String {
    options.first { $0.source == source }?.title ?? source.title
  }
}
