import Combine
import Foundation
import SwiftUI

@MainActor
class ContentViewModel: ObservableObject {
  @Published var isLoggedIn = false
  @Published var isSuperUser = false
  @Published var userPermissions: UserPermissions = .default

  private let apiService = APIService.shared
  private var cancellables = Set<AnyCancellable>()

  init() {
    // 初始状态
    isLoggedIn = apiService.isLoggedIn
    isSuperUser = apiService.isSuperUser
    userPermissions = apiService.currentUserPermissions

    // 监听令牌变化 -> 在登录或令牌更新时触发设置获取
    apiService.$token
      .receive(on: RunLoop.main)
      .sink { [weak self] token in
        self?.isLoggedIn = (token != nil)
        if token != nil {
          Task { [weak self] in
            try? await self?.apiService.fetchSettings()
            try? await self?.apiService.refreshCurrentUserAccess()
          }
        }
      }
      .store(in: &cancellables)

    apiService.$isSuperUser
      .receive(on: RunLoop.main)
      .assign(to: &$isSuperUser)

    apiService.$currentUserPermissions
      .receive(on: RunLoop.main)
      .assign(to: &$userPermissions)

    // 监听应用进入前台 -> 如果已登录则刷新设置
    NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
      .sink { [weak self] _ in
        guard let self = self, self.isLoggedIn else { return }
        Task { [weak self] in
          try? await self?.apiService.fetchSettings()
        }
      }
      .store(in: &cancellables)

    // 如果已经登录则进行初始获取（例如：应用带有效令牌冷启动）
    if isLoggedIn {
      Task { [weak self] in
        try? await self?.apiService.fetchSettings()
      }
    }
  }

  func logout() {
    // 清理预加载缓存，避免残留旧 Cookie 的图片 URL、旧订阅状态等脏数据
    MediaPreloader.shared.clearAll()
    apiService.logout()
  }

  func canAccess(_ permission: UserPermissionKey) -> Bool {
    userPermissions.allows(permission, isSuperUser: isSuperUser)
  }
}
