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
              .padding(.top, 28)
              .padding(.bottom, 0)

            ScrollView {
              VStack {
                LabeledContent("标题") {
                  Text(viewModel.torrent.title ?? "未知")
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                    .truncationMode(.tail)
                }

                if let description = viewModel.torrent.description {
                  LabeledContent("描述") {
                    Text(description)
                      .foregroundColor(.secondary)
                      .lineLimit(3)
                      .truncationMode(.tail)
                  }
                }

                LabeledContent("大小") {
                  Text(viewModel.torrent.size.formattedBytes())
                    .foregroundColor(.secondary)
                }

                if let seeds = viewModel.torrent.seeders, let peers = viewModel.torrent.peers {
                  LabeledContent("做种/下载") {
                    Text("\(seeds) / \(peers)")
                      .foregroundColor(.secondary)
                  }
                }

                if let site = viewModel.torrent.site_name {
                  LabeledContent("站点") {
                    Text(site)
                      .foregroundColor(.secondary)
                  }
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
                  .if(SheetStyleFix.shouldApply) { view in
                    view.padding(.horizontal)
                  }
                }
                .focused($isAdvancedButtonFocused)

                if showAdvanced {
                  SheetTextField(
                    title: "TMDB ID",
                    placeholder: "",
                    text: $viewModel.tmdbId,
                    keyboardType: .numberPad
                  )
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

                Button {
                  dismiss()
                } label: {
                  Text("取消")
                    .frame(maxWidth: .infinity)
                }
              }
              .padding(.horizontal, 28)
              .padding(.top, 10)
              .padding(.bottom, 28)
              .applySheetStyles()
            }
          }
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
