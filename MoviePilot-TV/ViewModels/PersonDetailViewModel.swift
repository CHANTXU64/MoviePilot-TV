import Combine
import Foundation
import SwiftUI

@MainActor
class PersonDetailViewModel: ObservableObject {
  @Published var person: Person
  @Published var isLoadingDetails = true  // 用于控制个人简介加载状态的新属性

  let paginator: Paginator<MediaInfo>
  private let apiService = APIService.shared
  private var cancellables = Set<AnyCancellable>()

  init(person: Person) {
    self.person = person
    var seenKeys = Set<String>()  // Paginator 内部管理

    self.paginator = Paginator<MediaInfo>(
      threshold: 12,
      fetcher: { @MainActor [apiService, person] page in
        // 确保 person.raw_id 存在
        guard let personId = person.raw_id, !personId.isEmpty else {
          return []
        }
        return try await apiService.fetchPersonCredits(
          personId: personId,
          source: person.source,
          page: page
        )
      },
      processor: { @MainActor items, newItems in
        // 使用现有的去重逻辑
        let unique = MediaInfo.deduplicate(newItems, existingKeys: &seenKeys)
        if !unique.isEmpty {
          items.append(contentsOf: unique)
          return true  // 返回 true 表示有新内容添加
        }
        return false  // 没有新内容
      },
      imageWarmURLsProvider: { item in
        [item.imageURLs.poster].compactMap(\.self)
      },
      onReset: { @MainActor in
        seenKeys.removeAll()  // 重置时清空 seenKeys
      }
    )

    self.paginator.objectWillChange
      .sink { [weak self] _ in
        self?.objectWillChange.send()
      }
      .store(in: &cancellables)
  }

  func loadDetails() async throws {
    // 如果缺少 raw_id，则不获取详情数据。
    guard let personId = person.raw_id, !personId.isEmpty else {
      isLoadingDetails = false
      return
    }
    isLoadingDetails = true
    defer { isLoadingDetails = false }

    do {
      let source = person.source

      // 获取人物详细信息（如生平、履历等）
      let fullDetail = try await apiService.fetchPersonDetail(
        personId: personId, source: source)

      // 详情响应可能是稀疏的 200；只补充有效字段，不覆盖入口人物的身份和已有展示数据。
      self.person = person.mergingDetails(from: fullDetail)
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      print("加载人物作品出错: \(error)")
    }
  }

  private var hasLoaded = false

  func loadInitialData() async {
    guard !hasLoaded else { return }
    hasLoaded = true
    // 刻意串行：先取人物详情，再加载第一页作品；详情被取消时不再启动分页请求。
    try? await loadDetails()
    guard !Task.isCancelled else { return }
    await paginator.refresh()
  }
}
