import SwiftUI

struct ImageNavigationDestination: View {
  let entry: ImageNavigationEntry
  @EnvironmentObject private var navigationCoordinator: ImageNavigationCoordinator

  @ViewBuilder
  var body: some View {
    let lifecycle = navigationCoordinator.lifecycle(for: entry)
    Group {
      switch entry.route {
      case .media(let media):
        if let collectionID = media.collection_id {
          CollectionDetailView(
            title: media.title ?? "合集详情",
            collectionId: collectionID,
            imageLifecycle: lifecycle
          )
        } else if let preloadTask = navigationCoordinator.preloadTask(for: entry) {
          MediaDetailContainerView(
            media: media,
            preloadTask: preloadTask,
            routeID: entry.id,
            imageLifecycle: lifecycle
          )
        } else {
          // 仅可能发生在 Pop 转场已经完成后，绝不为已移除 route 重建无 owner task。
          Color.clear
        }

      case .person(let person):
        PersonDetailView(
          person: person,
          imageLifecycle: lifecycle
        )

      case .resourceSearch(let request):
        ResourceResultView(
          request: request,
          imageLifecycle: lifecycle
        )

      case .subscribeSeason(let request):
        SubscribeSeasonView(
          mediaInfo: request.mediaInfo,
          initialSeason: request.initialSeason,
          initialEpisodeGroup: request.initialEpisodeGroup,
          imageLifecycle: lifecycle
        )
      }
    }
    .environment(\.pageImageLifecycle, lifecycle)
  }
}
