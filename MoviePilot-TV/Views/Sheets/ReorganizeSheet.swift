import SwiftUI

struct ReorganizeSheet: View {
  @Environment(\.dismiss) var dismiss
  @EnvironmentObject var notificationManager: NotificationManager
  let onDone: () -> Void

  @StateObject private var viewModel: ReorganizeViewModel
  @State private var showAdvanced = false
  @FocusState private var isAdvancedButtonFocused: Bool

  // 从 APIService 获取全局设置
  private let recognizeSource = APIService.shared.settings?.RECOGNIZE_SOURCE ?? "themoviedb"

  init(logIds: [Int] = [], fileItem: FileItem? = nil, onDone: @escaping () -> Void) {
    _viewModel = StateObject(
      wrappedValue: ReorganizeViewModel(logIds: logIds, fileItem: fileItem)
    )
    self.onDone = onDone
  }

  var body: some View {
    NavigationStack {
      Group {
        if viewModel.isLoading {
          ProgressView("正在加载配置...")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          VStack {
            Text("手动整理")
              .font(.headline)
              .foregroundColor(.secondary)
              .padding(.top, 28)
              .padding(.bottom, 0)

            ScrollView {
              VStack {
                basicSettings
                recognitionInfo
                if viewModel.form.type_name == "电视剧" {
                  seriesInfo
                }
                advancedSection
                actionButtons
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
        await viewModel.loadConfig()
      }
      .onChange(of: viewModel.errorMessage) { _, newValue in
        if let message = newValue {
          notificationManager.show(message: message, type: .error)
          viewModel.errorMessage = nil
        }
      }
    }
  }

  private var basicSettings: some View {
    Group {
      SheetPicker(
        title: "目的存储",
        selection: Binding(
          get: { viewModel.form.target_storage },
          set: { viewModel.form.target_storage = $0 }
        ),
        options: viewModel.storages.map { PickerOption(title: $0.name, value: $0.type) }
      )

      SheetPicker(
        title: "整理方式",
        selection: Binding(
          get: { viewModel.form.transfer_type },
          set: { viewModel.form.transfer_type = $0 }
        ),
        options: [
          PickerOption(title: "自动", value: ""),
          PickerOption(title: "复制", value: "copy"),
          PickerOption(title: "移动", value: "move"),
          PickerOption(title: "硬链接", value: "hardlink"),
          PickerOption(title: "软链接", value: "link"),
        ]
      )

      SheetPicker(
        title: "目的目录",
        selection: Binding(
          get: { viewModel.form.target_path },
          set: { viewModel.form.target_path = $0 }
        ),
        options: viewModel.targetDirectoryOptions
      )
    }
  }

  private var recognitionInfo: some View {
    Group {
      SheetPicker(
        title: "媒体类型",
        selection: Binding(
          get: { viewModel.form.type_name ?? "" },
          set: { viewModel.form.type_name = $0.isEmpty ? nil : $0 }
        ),
        options: [
          PickerOption(title: "自动", value: ""),
          PickerOption(title: "电影", value: "电影"),
          PickerOption(title: "电视剧", value: "电视剧"),
        ]
      )

      if recognizeSource == "themoviedb" {
        SheetTextField(
          title: "TMDB ID",
          placeholder: "留空自动识别",
          text: Binding(
            get: {
              if let id = viewModel.form.tmdbid {
                return String(id)
              }
              return ""
            },
            set: {
              if $0.isEmpty {
                viewModel.form.tmdbid = nil
              } else if let id = Int($0) {
                viewModel.form.tmdbid = id
              }
            }
          ),
          keyboardType: .numberPad
        )
      } else {
        SheetTextField(
          title: "豆瓣 ID",
          placeholder: "留空自动识别",
          text: Binding(
            get: { viewModel.form.doubanid ?? "" },
            set: { viewModel.form.doubanid = $0.isEmpty ? nil : $0 }
          ),
          keyboardType: .numberPad
        )
      }
    }
  }

  private var seriesInfo: some View {
    Group {
      SheetTextField(
        title: "指定剧集",
        placeholder: "剧集组编号",
        text: Binding(
          get: { viewModel.form.episode_group ?? "" },
          set: { viewModel.form.episode_group = $0.isEmpty ? nil : $0 }
        )
      )

      SheetTextField(
        title: "指定季数",
        placeholder: "第几季",
        text: Binding(
          get: {
            if let season = viewModel.form.season { return String(season) }
            return ""
          },
          set: { viewModel.form.season = Int($0) }
        ),
        keyboardType: .numberPad
      )

      SheetTextField(
        title: "指定集数",
        placeholder: "集数或范围，如 1 或 1,10",
        text: Binding(
          get: { viewModel.form.episode_detail ?? "" },
          set: { viewModel.form.episode_detail = $0.isEmpty ? nil : $0 }
        )
      )
      .disabled(viewModel.isEpisodeDetailDisabled)

      SheetTextField(
        title: "集数定位",
        placeholder: "辅助识别集数部分",
        text: Binding(
          get: { viewModel.form.episode_format ?? "" },
          set: { viewModel.form.episode_format = $0.isEmpty ? nil : $0 }
        )
      )

      SheetTextField(
        title: "集数偏移",
        placeholder: "如 -10 或 EP*2",
        text: Binding(
          get: { viewModel.form.episode_offset ?? "" },
          set: { viewModel.form.episode_offset = $0.isEmpty ? nil : $0 }
        ),
        keyboardType: .numbersAndPunctuation
      )
    }
  }

  private var advancedSection: some View {
    Group {
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
          title: "指定Part",
          placeholder: "如 part1",
          text: Binding(
            get: { viewModel.form.episode_part ?? "" },
            set: { viewModel.form.episode_part = $0.isEmpty ? nil : $0 }
          )
        )

        SheetTextField(
          title: "最小大小(MB)",
          placeholder: "只整理大于此的",
          text: Binding(
            get: {
              if viewModel.form.min_filesize == 0 {
                return ""
              }
              return String(viewModel.form.min_filesize)
            },
            set: { viewModel.form.min_filesize = Int($0) ?? 0 }
          ),
          keyboardType: .numberPad
        )

        Toggle(
          "刮削元数据",
          isOn: Binding(
            get: { viewModel.form.scrape },
            set: { viewModel.form.scrape = $0 }
          )
        )

        if !viewModel.form.target_path.isEmpty {
          Toggle(
            "层级目录 (电影/电视剧)",
            isOn: Binding(
              get: { viewModel.form.library_type_folder ?? false },
              set: { viewModel.form.library_type_folder = $0 }
            )
          )
          Toggle(
            "分类目录 (类型/产地)",
            isOn: Binding(
              get: { viewModel.form.library_category_folder ?? false },
              set: { viewModel.form.library_category_folder = $0 }
            )
          )
        }

        if viewModel.isFromHistory {
          Toggle(
            "复用历史识别记录",
            isOn: Binding(
              get: { viewModel.form.from_history },
              set: { viewModel.form.from_history = $0 }
            )
          )
        }
      }
    }
  }

  private var actionButtons: some View {
    Group {
      Button(action: {
        Task {
          if await viewModel.submit(background: true) {
            onDone()
            dismiss()
          }
        }
      }) {
        HStack(spacing: 8) {
          if viewModel.isSubmitting {
            ProgressView()
          }
          Text(viewModel.isSubmitting ? "正在处理..." : "开始整理")
        }
        .frame(maxWidth: .infinity)
      }
      .disabled(viewModel.isSubmitting)

      Button {
        dismiss()
      } label: {
        Text("取消")
          .frame(maxWidth: .infinity)
      }
    }
  }
}
