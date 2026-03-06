import SwiftUI

struct EmptyDataView: View {
  let title: String
  let systemImage: String
  let description: String?
  let actionTitle: String?
  let action: (() -> Void)?

  init(
    title: String = "暂无数据",
    systemImage: String = "tray",
    description: String? = nil,
    actionTitle: String? = nil,
    action: (() -> Void)? = nil
  ) {
    self.title = title
    self.systemImage = systemImage
    self.description = description
    self.actionTitle = actionTitle
    self.action = action
  }

  var body: some View {
    VStack(spacing: 40) {
      VStack(spacing: 20) {
        Image(systemName: systemImage)
          .font(.system(size: 100))
          .foregroundColor(.secondary)

        Text(title)
          .font(.headline)
          .foregroundColor(.primary)

        if let description = description {
          Text(description)
            .font(.body)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
        }
      }

      if let actionTitle = actionTitle, let action = action {
        Button(action: action) {
          Text(actionTitle)
        }
      } else {
        // 即使没有操作，我们也使其可聚焦，以避免焦点跳到导航栏
        Color.clear
          .frame(height: 1)
          .focusable()
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding()
  }
}

