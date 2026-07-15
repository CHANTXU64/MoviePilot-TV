import SwiftUI

struct LoginView: View {
  @StateObject private var viewModel = LoginViewModel()
  @EnvironmentObject private var notificationManager: NotificationManager

  var body: some View {
    HStack {
      VStack(spacing: 40) {
        Image("SettingsLogoGlass")
          .resizable()
          .scaledToFit()
          .frame(width: 500, height: 300)

        Text("MoviePilot")
          .font(.largeTitle)
          .fontWeight(.bold)

        VStack(spacing: 20) {
          TextField("服务器地址 (例如 http://192.168.1.5:3000)", text: $viewModel.serverURL)
            .keyboardType(.URL)

          TextField("用户名", text: $viewModel.username)
            .textContentType(.username)

          SecureField("密码", text: $viewModel.password)
            .textContentType(.password)

          Button(action: {
            Task {
              await viewModel.login()
            }
          }) {
            HStack(spacing: 8) {
              if viewModel.isLoading {
                ProgressView()
              }
              Text(viewModel.isLoading ? "登录中" : "登录")
            }
            .frame(maxWidth: .infinity)
          }
          .disabled(viewModel.isLoading || viewModel.serverURL.isEmpty || viewModel.username.isEmpty || viewModel.password.isEmpty)
        }
        .frame(width: 600)
      }
    }
    .onChange(of: viewModel.errorMessage) { _, newValue in
      if let message = newValue {
        notificationManager.show(message: message, type: .error)
        viewModel.errorMessage = nil
      }
    }
  }
}
