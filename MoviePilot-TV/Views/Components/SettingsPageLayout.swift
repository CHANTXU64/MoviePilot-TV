import SwiftUI

/// 设置页分组容器（SystemView 与共享设置组件共用）。
struct SettingsSection<Content: View>: View {
  let title: String?
  @ViewBuilder let content: () -> Content

  init(_ title: String?, @ViewBuilder content: @escaping () -> Content) {
    self.title = title
    self.content = content
  }

  var body: some View {
    VStack(alignment: .leading) {
      if let title, !title.isEmpty {
        Text(title)
          .font(.callout)
          .foregroundStyle(.secondary)
          .padding(.leading, 16)
      }
      VStack {
        content()
          .padding(.horizontal, 10)
      }
    }
  }
}

/// 设置页行标签（SystemView 与共享设置组件共用）。
struct SettingsRowLabel: View {
  let title: String
  var value: String? = nil
  var showsProgress: Bool = false
  var showsDisclosure: Bool = false

  init(_ title: String, value: String? = nil, showsProgress: Bool = false, showsDisclosure: Bool = false) {
    self.title = title
    self.value = value
    self.showsProgress = showsProgress
    self.showsDisclosure = showsDisclosure
  }

  var body: some View {
    HStack {
      Text(title)
        .font(.body.bold())
        .lineLimit(1)

      Spacer()

      HStack(spacing: 8) {
        if showsProgress {
          ProgressView()
        }

        if let value {
          Text(value)
            .font(.body.bold())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .multilineTextAlignment(.trailing)
            .truncationMode(.middle)
        }

        if showsDisclosure {
          Image(systemName: AppSymbol.disclosure)
            .foregroundStyle(.secondary)
        }
      }
    }
  }
}