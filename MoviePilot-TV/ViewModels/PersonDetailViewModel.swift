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
      imageURLsProvider: { item in
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

  func loadDetails() async {
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

      // 确定要保留的正确原始名称。
      let finalOriginalName: String?
      if let newON = fullDetail.original_name, !newON.isEmpty {
        finalOriginalName = newON
      } else {
        finalOriginalName = self.person.original_name
      }

      // 创建一个新的 Person 实例，合并新旧数据。
      let newPerson = Person(
        source: fullDetail.source,
        raw_id: fullDetail.raw_id,
        name: fullDetail.name,
        latin_name: fullDetail.latin_name,
        character: self.person.character,  // 始终保留旧的角色信息
        job: self.person.job,  // 始终保留旧的职位信息
        roles: self.person.roles,  // 始终保留旧的职位信息
        profile_path: fullDetail.profile_path,
        original_name: finalOriginalName,  // 使用保留的名称
        known_for_department: fullDetail.known_for_department,
        place_of_birth: fullDetail.place_of_birth,
        popularity: fullDetail.popularity,
        biography: fullDetail.biography,
        birthday: fullDetail.birthday,
        also_known_as: fullDetail.also_known_as,
        avatar: fullDetail.avatar,
        images: fullDetail.images,
        id: fullDetail.id
      )

      self.person = newPerson
    } catch {
      print("加载人物作品出错: \(error)")
    }
  }

  private var hasLoaded = false

  func loadInitialData() async {
    guard !hasLoaded else { return }
    hasLoaded = true
    // 并行执行：获取人物详情 和 加载第一页作品
    _ = await (
      loadDetails(),
      paginator.refresh()
    )
  }
}
