import SwiftUI

struct AddDownloadSheet: View {
  @Environment(\.dismiss) var dismiss
  @EnvironmentObject var notificationManager: NotificationManager
  @StateObject private var viewModel: AddDownloadViewModel
  @State private var showAdvanced = false
  @FocusState private var isInfoSectionFocused: Bool
  @FocusState private var isAdvancedButtonFocused: Bool

  init(torrent: TorrentInfo, media: MediaInfo? = nil, onSuccess: (() -> Void)? = nil) {
    _viewModel = StateObject(
      wrappedValue: AddDownloadViewModel(torrent: torrent, media: media, onSuccess: onSuccess)
    )
  }

  var body: some View {
    NavigationStack {
      Group {
        if viewModel.isLoading {
          ProgressView("加载配置中...")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.isSubmitting {
          ProgressView("提交下载任务中...")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          VStack {
            Text("添加下载")
              .font(.headline)
              .lineLimit(1)
              .foregroundColor(.secondary)
              .padding(.top, 10)

            ScrollView {
              VStack(spacing: 24) {
                LabeledContent("标题") {
                  Text(viewModel.torrent.title ?? "未知")
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                    .truncationMode(.tail)
                }
                .padding(.horizontal)

                if let description = viewModel.torrent.description {
                  LabeledContent("描述") {
                    Text(description)
                      .foregroundColor(.secondary)
                      .lineLimit(3)
                      .truncationMode(.tail)
                  }
                  .padding(.horizontal)
                }

                LabeledContent("大小") {
                  Text(viewModel.torrent.size.formattedBytes())
                    .foregroundColor(.secondary)
                }
                .padding(.horizontal)

                if let seeds = viewModel.torrent.seeders, let peers = viewModel.torrent.peers {
                  LabeledContent("做种/下载") {
                    Text("\(seeds) / \(peers)")
                      .foregroundColor(.secondary)
                  }
                  .padding(.horizontal)
                }

                if let site = viewModel.torrent.site_name {
                  LabeledContent("站点") {
                    Text(site)
                      .foregroundColor(.secondary)
                  }
                  .padding(.horizontal)
                }

                // List {
                SheetPicker(
                  title: "下载器",
                  selection: Binding(
                    get: { viewModel.selectedDownloader ?? "" },
                    set: { viewModel.selectedDownloader = $0.isEmpty ? nil : $0 }
                  ),
                  options: viewModel.downloaders.map {
                    PickerOption(title: $0.name, value: $0.name)
                  }
                )
                .padding(.horizontal)

                SheetPicker(
                  title: "保存路径",
                  selection: Binding(
                    get: { viewModel.selectedDirectory ?? "" },
                    set: { viewModel.selectedDirectory = $0.isEmpty ? nil : $0 }
                  ),
                  options: [PickerOption(title: "自动", value: "")]
                    + viewModel.targetDirectories.map {
                      PickerOption(title: $0, value: $0)
                    }
                )
                .padding(.horizontal)

                Button {
                  withAnimation {
                    showAdvanced.toggle()
                  }
                } label: {
                  HStack {
                    Text("高级配置")
                    Spacer()
                    Image(systemName: showAdvanced ? "chevron.down" : "chevron.right")
                  }
                  .foregroundColor(isAdvancedButtonFocused ? .black : .secondary)
                  .padding(.horizontal)
                }
                .padding(.horizontal)
                .focused($isAdvancedButtonFocused)

                if showAdvanced {
                  SheetTextField(
                    placeholder: "TMDB ID",
                    text: $viewModel.tmdbId,
                    keyboardType: .numberPad
                  )
                  .padding(.horizontal)
                }

                Button(action: {
                  Task {
                    await viewModel.addDownload()
                  }
                }) {
                  HStack(spacing: 8) {
                    if viewModel.isSubmitting {
                      ProgressView()
                    }
                    Text("确定")
                  }
                  .frame(maxWidth: .infinity)
                }
                .disabled(viewModel.isLoading || viewModel.isSubmitting)
                .padding(.horizontal)

                Button {
                  dismiss()
                } label: {
                  Text("取消")
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
              }
              .applySheetStyles()
            }
          }
          .padding()
          .frame(maxWidth: 1200)
        }
      }
      .task {
        await viewModel.loadData()
      }
      .onChange(of: viewModel.errorMessage) { _, newValue in
        if let message = newValue {
          notificationManager.show(message: message, type: .error)
          viewModel.errorMessage = nil
          dismiss()
        }
      }
    }
  }
}
