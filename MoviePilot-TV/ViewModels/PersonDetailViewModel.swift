import Combine
import Foundation
import SwiftUI

@MainActor
class PersonDetailViewModel: ObservableObject {
  @Published var person: Person
  @Published var credits: [MediaInfo] = []
  @Published var isLoading = true
  @Published var isLoadingMore = false
  @Published var hasMoreData = true

  private var currentPage = 1
  private var detectedPageSize: Int?
  private var seenKeys = Set<String>()

  private let apiService = APIService.shared

  init(person: Person) {
    self.person = person
  }

  func loadCredits() async {
    // 如果缺少 raw_id，则不调用 API。
    guard let personId = person.raw_id, !personId.isEmpty else {
      isLoading = false
      hasMoreData = false
      return
    }

    isLoading = true

    do {
      // 演员详情已就绪，仅需获取影视作品。
      let source = person.source

      // 并行获取作品列表及更新个人详细信息
      async let personCredits = apiService.fetchPersonCredits(
        personId: personId, source: source, page: 1)
      async let fullPersonDetail = apiService.fetchPersonDetail(
        personId: personId, source: source)

      let (newCredits, fullDetailResponse) = try await (personCredits, fullPersonDetail)

      let fullDetail = fullDetailResponse

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

      // 重置状态以进行完全刷新。
      currentPage = 1
      hasMoreData = true
      detectedPageSize = nil
      seenKeys.removeAll()

      self.credits = MediaInfo.deduplicate(newCredits, existingKeys: &seenKeys)

      if newCredits.isEmpty {
        hasMoreData = false
      } else {
        detectedPageSize = newCredits.count
      }

    } catch {
      print("加载人物作品出错: \(error)")
    }
    isLoading = false
  }

  func loadMoreData() async {
    guard !isLoadingMore, hasMoreData else { return }

    // 如果缺少 raw_id，则不调用 API。
    guard let personId = person.raw_id, !personId.isEmpty else {
      isLoadingMore = false
      hasMoreData = false
      return
    }

    isLoadingMore = true
    currentPage += 1

    do {
      let source = person.source
      let newItems = try await apiService.fetchPersonCredits(
        personId: personId, source: source, page: currentPage)

      if newItems.isEmpty {
        hasMoreData = false
      } else {
        if let pageSize = detectedPageSize, newItems.count < pageSize {
          hasMoreData = false
        }

        let uniqueItems = MediaInfo.deduplicate(newItems, existingKeys: &seenKeys)
        credits.append(contentsOf: uniqueItems)
      }
    } catch {
      print("加载更多人物作品出错: \(error)")
      currentPage -= 1
    }

    isLoadingMore = false
  }
}
