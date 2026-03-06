import SwiftUI

struct LoginView: View {
  @StateObject private var viewModel = LoginViewModel()

  var body: some View {
    HStack {
      VStack(spacing: 40) {
        Image(systemName: "film.stack.fill")
          .resizable()
          .aspectRatio(contentMode: .fit)
          .frame(width: 200, height: 200)
          .foregroundColor(.accentColor)

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

          if let errorMessage = viewModel.errorMessage {
            Text(errorMessage)
              .foregroundColor(.red)
          }

          Button(action: {
            Task {
              await viewModel.login()
            }
          }) {
            if viewModel.isLoading {
              ProgressView()
            } else {
              Text("登录")
                .frame(maxWidth: .infinity)
            }
          }
          .disabled(viewModel.isLoading || viewModel.serverURL.isEmpty || viewModel.username.isEmpty || viewModel.password.isEmpty)
        }
        .frame(width: 600)
      }
    }
  }
}
