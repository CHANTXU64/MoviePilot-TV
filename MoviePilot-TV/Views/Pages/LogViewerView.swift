import SwiftUI

struct LogViewerView: View {
  @ObservedObject var viewModel: LogViewerViewModel
  var focusedItem: FocusState<SystemSettingsFocus?>.Binding
  @Binding var selectedRecord: LogRecord?

  var body: some View {
    ScrollView(.vertical) {
      LazyVStack(alignment: .leading, spacing: 28) {
        VStack(alignment: .leading, spacing: 0) {
          Toggle("记录日志", isOn: $viewModel.isRecordingEnabled)
            .font(.body.weight(.semibold))
            .focused(focusedItem, equals: .logRecording)

          Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .contentShape(Rectangle())
            .focusable(
              focusedItem.wrappedValue == .logRecording
                || focusedItem.wrappedValue == .logDownRedirector
            )
            .focusEffectDisabled()
            .focused(focusedItem, equals: .logDownRedirector)
            .onChange(of: focusedItem.wrappedValue) { _, newValue in
              guard newValue == .logDownRedirector else { return }
              focusedItem.wrappedValue = .logLevelFilter
            }

          HStack(spacing: 24) {
            Picker("级别", selection: $viewModel.levelFilter) {
              ForEach(LogViewerViewModel.LevelFilter.allCases) { filter in
                Text("级别：" + filter.title).tag(filter)
              }
            }
            .pickerStyle(.menu)
            .focused(focusedItem, equals: .logLevelFilter)

            Picker("时间", selection: $viewModel.timeFilter) {
              ForEach(LogViewerViewModel.TimeFilter.allCases) { filter in
                Text("时间：" + filter.title).tag(filter)
              }
            }
            .pickerStyle(.menu)
            .focused(focusedItem, equals: .logTimeFilter)
          }
          .focusSection()
        }

        if let message = viewModel.storageErrorMessage {
          VStack(alignment: .leading, spacing: 12) {
            Text(message)
              .font(.callout)
              .foregroundStyle(.orange)
            Button("重新读取") {
              Task { await viewModel.reloadRecords() }
            }
          }
          .padding(.leading, 16)
        }

        if viewModel.isLoading {
          ProgressView()
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
        } else if viewModel.showsEmptyState {
          Text("没有符合条件的日志")
            .font(.body.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 16)
            .padding(.top, 12)
        } else if !viewModel.records.isEmpty {
          Text(viewModel.summaryText)
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.leading, 16)

          ForEach(viewModel.records) { record in
            Button {
              selectedRecord = record
            } label: {
              logCard(record)
            }
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.top, 8)
      .padding(.bottom, 80)
    }
    .scrollClipDisabled()
    .task {
      await viewModel.reloadRecords()
    }
    .onChange(of: viewModel.levelFilter) { _, _ in
      Task { await viewModel.reloadRecords() }
    }
    .onChange(of: viewModel.timeFilter) { _, _ in
      Task { await viewModel.reloadRecords() }
    }
  }

  private func logCard(_ record: LogRecord) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline) {
        Text(record.level.prefix)
          .foregroundStyle(logLevelColor(record.level))
        Spacer()
        Text(LogDisplayFormatting.timestamp.string(from: record.timestamp))
          .foregroundStyle(.secondary)
      }

      Text(record.message)
        .multilineTextAlignment(.leading)
        .lineLimit(6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .font(.caption.weight(.semibold))
    .padding(.vertical, 10)
  }
}

struct LogRecordDetailSheet: View {
  let record: LogRecord

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        HStack(alignment: .firstTextBaseline) {
          Text(record.level.prefix)
            .font(.title2.bold())
            .foregroundStyle(logLevelColor(record.level))
          Spacer()
          Text(LogDisplayFormatting.timestamp.string(from: record.timestamp))
            .font(.callout)
            .foregroundStyle(.secondary)
        }

        Divider()

        Text(record.message)
          .font(.callout)
          .frame(maxWidth: .infinity, alignment: .leading)
          .fixedSize(horizontal: false, vertical: true)

        if let metadata = record.metadata, !metadata.isEmpty {
          VStack(alignment: .leading, spacing: 8) {
            Text("metadata")
              .font(.subheadline.bold())
            ForEach(metadata.keys.sorted(), id: \.self) { key in
              Text("\(key): \(metadata[key] ?? "")")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 72)
      .padding(.vertical, 54)
    }
    .frame(width: 1_440, height: 1_025)
  }
}

private func logLevelColor(_ level: Logger.Level) -> Color {
  switch level {
  case .error:
    return .red
  case .warning:
    return .orange
  case .info:
    return .primary
  case .debug:
    return .secondary
  }
}
