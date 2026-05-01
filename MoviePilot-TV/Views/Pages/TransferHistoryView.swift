import SwiftUI

struct TransferHistoryView: View {
  @ObservedObject var viewModel: TransferHistoryViewModel
  @State private var itemToDelete: TransferHistory? = nil
  @State private var itemToReorganize: TransferHistory? = nil
  @State private var historyIdToRestoreFocus: Int? = nil
  @State private var isRefreshingAfterReorganize = false
  @State private var itemForInfoSheet: TransferHistory? = nil
  @State private var showBatchDeleteAlert = false
  @State private var showBatchRedoSheet = false
  @State private var localSearchText: String = ""
  @FocusState private var focusedHistoryId: Int?

  init(viewModel: TransferHistoryViewModel) {
    self.viewModel = viewModel
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text("媒体整理历史")
          .font(.body)
          .fontWeight(.bold)
          .foregroundStyle(.secondary)
          .padding(.leading, 8)

        Spacer()

        HStack(spacing: 20) {
          // 批量操作状态显示
          if !viewModel.selectedIds.isEmpty {
            Button("取消全选(\(viewModel.selectedIds.count))") {
              viewModel.deselectAll()
            }
          }

          // 新增的搜索框和按钮
          TextField("搜索整理记录", text: $localSearchText)
            .frame(width: 400)
            .onSubmit {
              // 当用户提交输入时 (例如，移开焦点)，调用搜索方法
              viewModel.search(with: localSearchText)
            }
        }
      }
      .focusSection()

      // 加载中：正在首次加载
      if viewModel.isFirstLoading {
        ProgressView().frame(maxWidth: .infinity, alignment: .center).padding()
      } else if viewModel.items.isEmpty {
        EmptyDataView(title: "没有数据")
      } else {
        // 使用 LazyVStack 提高性能
        LazyVStack {
          ForEach(viewModel.items) { item in
            ActionRow(
              actions: actionDescriptors(for: item),
              onTap: {
                viewModel.toggleSelection(id: item.id)
              },
              onLongPress: {
                itemForInfoSheet = item
              }
            ) { isFocused in
              HStack(spacing: 10) {
                // 多选勾选框
                Image(
                  systemName: viewModel.selectedIds.contains(item.id)
                    ? "checkmark.circle.fill" : "circle"
                )
                .font(.caption)
                .foregroundColor(.secondary)

                TransferHistoryRowView(
                  item: item, isFocused: isFocused, storageDict: viewModel.storageDict
                )
                .frame(maxWidth: .infinity, alignment: .topLeading)
              }
              .padding()
              .contentShape(Rectangle())
            } background: {
              LinearGradient(
                colors: [.black.opacity(0.3), .black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
              )
            }
            .focused($focusedHistoryId, equals: item.id)
          }
          if viewModel.isLoadingMore {
            ProgressView().padding()
          }
        }
        .padding(.top, 25)
        .padding(.bottom, 30)
        .onChange(of: focusedHistoryId) { _, newId in
          if let newId = newId {
            Task {
              await viewModel.loadMore(currentItemId: newId)
            }
          }
        }
      }
    }
    .task {
      // 仅在数据为空时执行首次加载, 避免视图切换时重载
      if viewModel.items.isEmpty {
        await viewModel.refresh()
      }

      // 定期拉取最新数据，替代旧版 Timer.publish，避免后台挂起恢复后的调度失效问题
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 10 * 1_000_000_000)
        guard !Task.isCancelled else { break }
        await viewModel.fetchLatest()
      }
    }
    .overlay(
      Group {
        if viewModel.isAiRedoing {
          VStack(spacing: 20) {
            ProgressView(viewModel.aiRedoProgressText)
          }
          .padding()
          .background(.ultraThinMaterial)
          .cornerRadius(12)
        }
      },
      alignment: .center
    )
    .sheet(item: $itemForInfoSheet) { item in
      TransferHistoryDetailSheet(item: item, storageDict: viewModel.storageDict)
    }
    .sheet(
      item: $itemToReorganize,
      onDismiss: restoreHistoryFocus
    ) { item in
      ReorganizeSheet(
        logIds: [item.id],
        fileItem: item.src_fileitem,
        targetStorage: item.dest_storage
      ) {
        isRefreshingAfterReorganize = true
        Task {
          await viewModel.refresh()
          isRefreshingAfterReorganize = false
        }
      }
    }
    // 批量重做弹窗
    .sheet(isPresented: $showBatchRedoSheet) {
      ReorganizeSheet(logIds: Array(viewModel.selectedIds), fileItem: nil) {
        Task {
          viewModel.deselectAll()
          await viewModel.refresh()
        }
      }
    }
    .alert(
      "确认删除",
      isPresented: Binding(
        get: { itemToDelete != nil },
        set: { if !$0 { itemToDelete = nil } }
      ),
      actions: {
        Button("仅删除记录", role: .destructive) {
          guard let item = itemToDelete else { return }
          Task { await viewModel.deleteHistory(item: item, deleteSource: false, deleteDest: false) }
          itemToDelete = nil
        }
        Button("删除记录和源文件", role: .destructive) {
          guard let item = itemToDelete else { return }
          Task { await viewModel.deleteHistory(item: item, deleteSource: true, deleteDest: false) }
          itemToDelete = nil
        }
        Button("删除记录和目标文件", role: .destructive) {
          guard let item = itemToDelete else { return }
          Task { await viewModel.deleteHistory(item: item, deleteSource: false, deleteDest: true) }
          itemToDelete = nil
        }
        Button("全部删除", role: .destructive) {
          guard let item = itemToDelete else { return }
          Task { await viewModel.deleteHistory(item: item, deleteSource: true, deleteDest: true) }
          itemToDelete = nil
        }
        Button("取消", role: .cancel) {
          itemToDelete = nil
        }
      },
      message: {
        if let title = itemToDelete?.title, !title.isEmpty {
          Text("确认删除《\(title)》的记录吗？此操作不可撤销。")
        } else {
          Text("确认删除该记录吗？此操作不可撤销。")
        }
      }
    )
    // 批量删除确认
    .alert(
      "批量删除确认", isPresented: $showBatchDeleteAlert,
      actions: {
        Button("仅删除记录", role: .destructive) {
          Task { await viewModel.deleteSelected(deleteSource: false, deleteDest: false) }
        }
        Button("删除记录和源文件", role: .destructive) {
          Task { await viewModel.deleteSelected(deleteSource: true, deleteDest: false) }
        }
        Button("删除记录和目标文件", role: .destructive) {
          Task { await viewModel.deleteSelected(deleteSource: false, deleteDest: true) }
        }
        Button("全部删除", role: .destructive) {
          Task { await viewModel.deleteSelected(deleteSource: true, deleteDest: true) }
        }
        Button("取消", role: .cancel) {}
      },
      message: {
        Text("确定要删除选中的 \(viewModel.selectedIds.count) 条记录吗？此操作不可撤销。")
      })
  }

  private func restoreHistoryFocus() {
    guard !isRefreshingAfterReorganize else { return }
    guard let id = historyIdToRestoreFocus else { return }

    focusedHistoryId = id
    DispatchQueue.main.async {
      focusedHistoryId = id
      historyIdToRestoreFocus = nil
    }
  }

  private func actionDescriptors(for item: TransferHistory) -> [ActionDescriptor] {
    var actions: [ActionDescriptor] = []

    if viewModel.selectedIds.isEmpty && viewModel.isAiRedoEnabled {
      actions.append(
        ActionDescriptor(
          id: "ai-redo",
          title: viewModel.aiRedoingIds.contains(item.id) ? "AI 整理中" : "AI 自动整理",
          icon: "sparkles",
          isEnabled: !viewModel.isAiRedoing || viewModel.aiRedoingIds.contains(item.id),
          action: {
            Task {
              await viewModel.triggerAiRedo(for: item)
            }
          }
        )
      )
    }

    actions.append(
      ActionDescriptor(
        id: "redo",
        title: viewModel.selectedIds.isEmpty
          ? "重新整理" : "重新批量整理(\(viewModel.selectedIds.count))",
        icon: "arrow.clockwise",
        action: {
          if viewModel.selectedIds.isEmpty {
            historyIdToRestoreFocus = item.id
            itemToReorganize = item
          } else {
            showBatchRedoSheet = true
          }
        }
      )
    )

    actions.append(
      ActionDescriptor(
        id: "delete",
        title: viewModel.selectedIds.isEmpty
          ? "删除" : "批量删除(\(viewModel.selectedIds.count))",
        icon: "trash",
        role: .destructive,
        action: {
          if viewModel.selectedIds.isEmpty {
            itemToDelete = item
          } else {
            showBatchDeleteAlert = true
          }
        }
      )
    )

    return actions
  }
}

private func transferModeDisplayName(for mode: String) -> String {
  switch mode {
  case "copy": return "拷贝"
  case "move": return "移动"
  case "link": return "硬链接"
  case "softlink": return "软链接"
  case "rclone_copy": return "Rclone 拷贝"
  case "rclone_move": return "Rclone 移动"
  default: return mode.capitalized
  }
}

private struct TransferHistoryRowView: View {
  let item: TransferHistory
  let isFocused: Bool
  let storageDict: [String: String]

  var body: some View {
    // 1. 核心信息
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 20) {
        Text(item.title ?? "未知标题")
          .foregroundColor(isFocused ? .primary : .primary.opacity(0.6))
        if item.type == "电视剧" {
          Text("\(item.seasons ?? "") \(item.episodes ?? "")")
            .foregroundColor(.secondary)
        }
      }
      .font(.headline)
      .lineLimit(1)

      let srcStorageName =
        item.src_storage.flatMap {
          $0.isEmpty ? nil : "[\(storageDict[$0] ?? $0)] "
        } ?? ""
      let srcText = srcStorageName + (item.src ?? "N/A")
      Text("源: \(srcText)")
        .font(.caption2)
        .foregroundColor(.secondary)
        .lineLimit(1)

      let destStorageName =
        item.dest_storage.flatMap {
          $0.isEmpty ? nil : "[\(storageDict[$0] ?? $0)] "
        } ?? ""
      let destText = destStorageName + (item.dest ?? "N/A")
      Text("目标: \(destText)")
        .font(.caption2)
        .foregroundColor(.secondary)
        .lineLimit(1)

      // 3. 状态与元数据
      HStack(spacing: 20) {
        statusChip

        if let category = item.category, !category.isEmpty {
          Text(category)
            .font(.caption)
            .foregroundColor(.secondary)
        }

        if let mode = item.mode, !mode.isEmpty {
          Text(transferModeDisplayName(for: mode))
            .font(.caption)
            .foregroundColor(.secondary)
        }
        Text(item.date ?? "")
          .font(.caption)
          .foregroundColor(.secondary)
        Text((item.src_fileitem?.size ?? 0).formattedBytes())
          .font(.caption)
          .foregroundColor(.secondary)
      }
    }
  }

  @ViewBuilder
  private var statusChip: some View {
    if item.status.value {
      Text("成功")
        .font(.caption)
        .fontWeight(.medium)
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(Color.green.opacity(0.3))
        .foregroundColor(.green)
        .cornerRadius(6)
    } else {
      Text("失败")
        .font(.caption)
        .fontWeight(.medium)
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(Color.red.opacity(0.3))
        .foregroundColor(.red)
        .cornerRadius(6)
    }
  }
}

private struct TransferHistoryDetailSheet: View {
  let item: TransferHistory
  let storageDict: [String: String]
  @Environment(\.dismiss) var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: 30) {
      HStack(spacing: 40) {
        Text(item.title ?? "详情")
          .fontWeight(.bold)
          .foregroundColor(.primary)
        if item.type == "电视剧" {
          Text("\(item.seasons ?? "") \(item.episodes ?? "")")
            .foregroundColor(.secondary)
        }
      }
      .font(.title2)

      VStack(alignment: .leading, spacing: 20) {
        let srcStorageName = item.src_storage.flatMap { storageDict[$0] ?? $0 } ?? "未知"
        let srcContent = "[\(srcStorageName)] \(item.src ?? "N/A")"
        TransferInfoRow(label: "源文件", content: srcContent)
        Divider()

        let destStorageName = item.dest_storage.flatMap { storageDict[$0] ?? $0 } ?? "未知"
        let destContent = "[\(destStorageName)] \(item.dest ?? "N/A")"
        TransferInfoRow(label: "目标文件", content: destContent)
      }

      HStack(spacing: 30) {
        Text("状态：")
          .fontWeight(.bold)
          + Text(item.status.value ? "成功" : "失败")
        Text("分类：")
          .fontWeight(.bold)
          + Text(item.category ?? "未知")
        Text("转移方式：")
          .fontWeight(.bold)
          + Text(transferModeDisplayName(for: item.mode ?? "未知"))
        Text("日期：")
          .fontWeight(.bold)
          + Text(item.date ?? "N/A")
        Text("大小：")
          .fontWeight(.bold)
          + Text((item.src_fileitem?.size ?? 0).formattedBytes())
      }
      .foregroundColor(.secondary)
      .font(.footnote)
    }
    .frame(width: 1600)
    .padding(50)
  }
}

private struct TransferInfoRow: View {
  let label: String
  let content: String

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      Text(label)
        .fontWeight(.bold)
        .foregroundColor(.primary)
        .frame(width: 130, alignment: .leading)
      Text(content)
        .foregroundColor(.secondary)
    }
    .font(.footnote)
  }
}
