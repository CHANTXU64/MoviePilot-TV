import Combine
import SwiftUI

@MainActor
class ReorganizeViewModel: ObservableObject {
  @Published var form: ReorganizeForm
  @Published var directories: [TransferDirectoryConf] = []
  @Published var storages: [StorageConf] = []
  @Published var targetDirectoryOptions: [PickerOption<String>] = []
  @Published var isLoading = true
  @Published var isSubmitting = false
  @Published var isEpisodeDetailDisabled = false  // 视图绑定，表示“指定集数”是否禁用

  @Published var errorMessage: String?

  private let apiService = APIService.shared
  private var cancellables = Set<AnyCancellable>()

  private var logIds: [Int] = []

  // 用于视图判断当前是否是对历史记录发起整理
  var isFromHistory: Bool {
    return !logIds.isEmpty
  }

  init(logIds: [Int] = [], fileItem: FileItem?) {
    self.logIds = logIds

    // 在 init() 中初始化 form，为必须的属性提供默认值
    self.form = ReorganizeForm(
      fileitem: fileItem ?? FileItem(name: "", path: "", type: "", size: nil),
      logid: logIds.first ?? 0,
      target_storage: "local",
      transfer_type: "",
      target_path: "",
      min_filesize: 0,
      scrape: false,
      from_history: false
    )

    // 监听 target_path 的变化
    $form
      .map(\.target_path)
      .removeDuplicates()
      .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
      .sink { [weak self] newPath in
        self?.updateForm(for: newPath)
      }
      .store(in: &cancellables)

    // 监听表单变化以更新“指定集数”的禁用状态
    $form
      // 只关心影响禁用逻辑的字段
      .map(\.episode_format)
      .removeDuplicates()
      .sink { [weak self] _ in
        self?.updateEpisodeDetailDisabledState()
      }
      .store(in: &cancellables)

    // 初始化禁用状态
    updateEpisodeDetailDisabledState()
  }

  func loadConfig() async {
    isLoading = true
    defer { isLoading = false }
    do {
      async let dirsTask = apiService.fetchDirectories()
      async let storagesTask = apiService.fetchStorages()

      self.directories = try await dirsTask
      self.storages = try await storagesTask

      self.targetDirectoryOptions =
        [PickerOption(title: "自动", value: "")]
        + Array(
          Set(self.directories.compactMap { $0.library_path })
        ).sorted().map {
          PickerOption(title: $0, value: $0)
        }

    } catch {
      self.errorMessage = "加载配置失败: \(error.localizedDescription)"
    }
  }

  func submit(background: Bool) async -> Bool {
    isSubmitting = true
    defer { isSubmitting = false }
    do {
      var allSuccess = true
      if logIds.count > 1 {
        // 批量重做
        for id in logIds {
          var batchForm = form
          batchForm.logid = id
          // 历史重做不需要 fileitem，但为满足非可选属性，提供一个空对象
          batchForm.fileitem = FileItem(name: "", path: "", type: "", size: nil)
          let success = try await apiService.manualTransfer(form: batchForm, background: background)
          if !success {
            allSuccess = false
          }
        }
      } else {
        let success = try await apiService.manualTransfer(form: form, background: background)
        allSuccess = success
      }

      if allSuccess {
        return true
      } else {
        self.errorMessage = "部分或全部操作失败，请查看日志"
        return false
      }
    } catch {
      self.errorMessage = "请求出错: \(error.localizedDescription)"
      return false
    }
  }

  private func updateForm(for newPath: String?) {
    guard let newPath = newPath, !newPath.isEmpty else {
      // 路径为空时, 恢复到`自动`条件
      form.transfer_type = ""
      form.library_type_folder = nil
      form.library_category_folder = nil
      return
    }

    if let directory = directories.first(where: { $0.library_path == newPath }) {
      form.target_storage = directory.library_storage ?? "local"
      if form.transfer_type.isEmpty {
        form.transfer_type = directory.transfer_type
      }
      form.scrape = directory.scraping?.value ?? false
      form.library_category_folder = directory.library_category_folder?.value ?? false
      form.library_type_folder = directory.library_type_folder?.value ?? false
    } else {
      if form.transfer_type.isEmpty {
        form.transfer_type = "copy"
      }
      form.scrape = false
      form.library_category_folder = false
      form.library_type_folder = false
    }
  }

  /// 根据表单状态更新“指定集数”输入框的禁用状态
  private func updateEpisodeDetailDisabledState() {
    // 如果指定了剧集格式，则应允许用户输入指定的集数
    if let format = form.episode_format, !format.isEmpty {
      isEpisodeDetailDisabled = false
      return
    }
    // 如果是从历史记录模式进入，意味着没有实体文件，应允许用户手动指定
    if isFromHistory {
      isEpisodeDetailDisabled = false
      return
    }
    // 对于文件整理模式，如果是文件夹类型，则禁用此功能
    isEpisodeDetailDisabled = (form.fileitem.type == "dir")
  }
}
