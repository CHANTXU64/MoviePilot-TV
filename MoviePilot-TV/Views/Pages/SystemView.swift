import SwiftUI

struct SystemView: View {

  @StateObject private var viewModel = SystemViewModel()

  var body: some View {
    NavigationStack {
      List {
        Section(header: Text("状态")) {
          LabeledContent("登录状态") {
            Text(viewModel.storageDescription)
              .foregroundStyle(statusColor)
              .animation(.default, value: viewModel.storageMechanism)
          }
        }

        Section(header: Text("常规"), footer: Text("修改配置后需要重启APP生效")) {
          // Placeholder for future frontend config
          Text("前端配置 (开发中)")
            .foregroundColor(.secondary)
        }

        Section(header: Text("账户"), footer: Text(viewModel.refreshMessage ?? "")) {
          Button(action: {
            Task {
              await viewModel.relogin()
            }
          }) {
            HStack {
              if viewModel.isRefreshing {
                ProgressView()
                  .controlSize(.small)
                  .padding(.trailing, 8)
              }
              Text("重新登录凭据")
              Spacer()
              Image(systemName: "arrow.clockwise")
            }
          }
          .disabled(viewModel.isRefreshing)

          Button(action: {
            APIService.shared.logout()
            // 登出后立即刷新状态
            viewModel.checkKeychainStatus()
          }) {
            HStack {
              Text("退出登录")
                .foregroundColor(.red)
              Spacer()
              Image(systemName: "rectangle.portrait.and.arrow.right")
                .foregroundColor(.red)
            }
          }
        }
      }
      .onAppear {
        // 视图每次出现时都刷新状态，确保与实际情况同步
        viewModel.checkKeychainStatus()
      }
    }
  }

  private var statusColor: Color {
    switch viewModel.storageMechanism {
    case .keychain:
      return .green
    case .userDefaults:
      return .orange
    case .none:
      return .secondary
    }
  }
}
