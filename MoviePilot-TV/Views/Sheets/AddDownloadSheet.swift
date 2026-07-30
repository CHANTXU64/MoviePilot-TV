import SwiftUI

struct AddDownloadSheet: View {
  @Environment(\.dismiss) var dismiss
  @ObservedObject private var apiService = APIService.shared
  @StateObject private var viewModel: AddDownloadViewModel
  @State private var showAdvanced = false
  @State private var showMediaSearch = false
  @FocusState private var isInfoSectionFocused: Bool
  @FocusState private var isAdvancedButtonFocused: Bool

  init(torrent: TorrentInfo, media: MediaInfo? = nil, onSuccess: (() -> Void)? = nil) {
    _viewModel = StateObject(
      wrappedValue: AddDownloadViewModel(torrent: torrent, media: media, onSuccess: onSuccess)
    )
  }

  var body: some View {
    Group {
      if viewModel.isLoading {
        ProgressView("加载配置中...")
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
                  .lineLimit(5)
                  .fixedSize(horizontal: false, vertical: true)
              }

              if let description = viewModel.torrent.description {
                LabeledContent("描述") {
                  Text(description)
                    .foregroundColor(.secondary)
                    .lineLimit(5)
                    .fixedSize(horizontal: false, vertical: true)
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
                HStack(spacing: 20) {
                  SheetTextField(
                    title: "\(viewModel.mediaSource.title) ID",
                    placeholder: "自动判断",
                    text: $viewModel.mediaId,
                    keyboardType: .numberPad
                  )

                  Button {
                    showMediaSearch = true
                  } label: {
                    Image(systemName: "magnifyingglass")
                  }
                  .accessibilityLabel("搜索媒体")
                }
                if !viewModel.isMediaIdValid {
                  Text("媒体 ID 只能包含数字")
                    .foregroundStyle(.red)
                }
              }

              SheetActionButton(
                title: "确定",
                loadingTitle: "添加中",
                isLoading: viewModel.isSubmitting,
                isDisabled: !apiService.canAccess(.search) || !viewModel.isMediaIdValid,
                feedbackMessage: viewModel.errorMessage
              ) {
                guard apiService.canAccess(.search) else { return }
                Task {
                  await viewModel.addDownload()
                }
              }

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
    .sheet(isPresented: $showMediaSearch) {
      ManualMediaSearchSheet(source: viewModel.mediaSource) { mediaId, _ in
        viewModel.mediaId = mediaId
        showMediaSearch = false
      }
    }
    .frame(width: 1200)
  }
}
