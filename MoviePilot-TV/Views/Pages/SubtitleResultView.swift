import Flow
import SwiftUI

struct SubtitleResultsBody<Header: View>: View {
  @ObservedObject var search: SubtitleSearchSession
  let imageLifecycle: PageImageLifecycle
  private let header: Header
  private let onCancel: (() -> Void)?
  @State private var downloadTarget: SubtitleDownloadViewModel?

  init(
    search: SubtitleSearchSession,
    imageLifecycle: PageImageLifecycle,
    onCancel: (() -> Void)? = nil,
    @ViewBuilder header: () -> Header
  ) {
    self.search = search
    self.imageLifecycle = imageLifecycle
    self.onCancel = onCancel
    self.header = header()
  }

  var body: some View {
    Group {
      if search.rows.isEmpty {
        emptyContent
      } else {
        resultsContent
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .focusSection()
    .sheet(item: Binding(
      get: { downloadTarget },
      set: { target in
        if target == nil { downloadTarget?.close() }
        downloadTarget = target
      }
    )) { target in
      SubtitleDownloadSheet(viewModel: target)
    }
    .onAppear { imageLifecycle.registerStackObserver(search) }
    .onDisappear {
      imageLifecycle.unregisterStackObserver(search)
      search.deactivate()
    }
    .id(ObjectIdentifier(search))
  }

  private var emptyContent: some View {
    VStack(spacing: 24) {
      header
      GeometryReader { geometry in
        ScrollView(.vertical) {
          Group {
            if search.isSearching {
              progressContent
            } else if search.didFinish || search.state == .interrupted {
              EmptyDataView(
                title: "未找到相关字幕",
                systemImage: "captions.bubble",
                description: search.errorMessage,
                actionTitle: search.canRestart ? "重新搜索" : nil,
                action: { search.restart() }
              )
            }
          }
          .frame(maxWidth: .infinity, minHeight: geometry.size.height)
          .focusSection()
        }
      }
    }
  }

  private var progressContent: some View {
    VStack(spacing: 20) {
      ProgressView {
        Text(search.progressText)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
      }
      if search.progress > 0 {
        ProgressView(value: search.progress, total: 100)
          .progressViewStyle(.linear)
          .frame(width: 420)
      }
      if !search.rows.isEmpty {
        Button("停止并查看") { search.deactivate() }
      } else if let onCancel {
        Button("取消", action: onCancel)
      }
    }
    .padding(.horizontal, 40)
    .frame(maxWidth: .infinity)
    .focusSection()
  }

  private var resultsContent: some View {
    ScrollView(.vertical) {
      VStack(spacing: 24) {
        header
        if search.isSearching {
          progressContent
        }
        if let error = search.errorMessage {
          Text(error).font(.caption).foregroundColor(.orange)
        }
        HStack(spacing: 24) {
          TorrentResultCount(count: search.rows.count, unit: "个字幕")
          if search.canRestart {
            Button("重新搜索") { search.restart() }
              .disabled(downloadTarget != nil)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
        TorrentResultsGrid(items: search.rows, alignment: .top) { row in
          SubtitleResultCard(
            subtitle: row.subtitle,
            downloaded: row.subtitle.enclosure.map {
              search.downloadedEnclosures.contains($0)
            } ?? false
          ) {
            downloadTarget = search.downloadModel(for: row.subtitle)
          }
          .disabled(!search.canDownload)
        }
      }
    }
  }

}

private struct SubtitleResultCard: View {
  let subtitle: SubtitleInfo
  let downloaded: Bool
  let onSelect: () -> Void

  var body: some View {
    Button(action: onSelect) {
      cardContent
    }
    .buttonStyle(.card)
  }

  private var cardContent: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .top, spacing: 12) {
        Text(subtitle.displayTitle)
          .font(.headline)
          .fontWeight(.bold)
          .lineLimit(2)
          .multilineTextAlignment(.leading)
        Spacer(minLength: 0)
        if let season = MediaIdentifier.normalizedString(subtitle.season_episode) {
          Text(season.formattedSeasonEpisode())
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
              RoundedRectangle(cornerRadius: 6)
                .fill(.secondary.opacity(0.2))
            )
        }
      }

      if let description = MediaIdentifier.normalizedString(subtitle.description) {
        Text(description)
          .font(.caption)
          .foregroundColor(.secondary)
          .lineLimit(2)
      }

      HStack {
        HStack(spacing: 15) {
          if let size = subtitle.sizeInBytes, size > 0 {
            Text(size.formattedBytes())
              .accessibilityLabel("文件大小 \(size.formattedBytes())")
          }
          if let elapsed = MediaIdentifier.normalizedString(subtitle.date_elapsed)
            ?? MediaIdentifier.normalizedString(subtitle.pubdate) {
            if (subtitle.sizeInBytes ?? 0) > 0 { Text("•").accessibilityHidden(true) }
            Text(elapsed.toRelativeDateString())
              .accessibilityLabel("发布时间 \(elapsed.toRelativeDateString())")
          }
        }
        Spacer(minLength: 12)
        if let grabs = subtitle.grabs {
          Label("\(grabs) 次", systemImage: "arrow.down")
            .accessibilityLabel("下载 \(grabs) 次")
            .fixedSize()
        }
      }
      .multilineTextAlignment(.leading)
      .font(.caption2)
      .foregroundColor(.secondary)

      Divider()
        .background(Color.primary)
        .padding(.vertical, 4)

      HFlow(itemSpacing: 20, rowSpacing: 8) {
        if let site = MediaIdentifier.normalizedString(subtitle.site_name) {
          TorrentCardTag(text: site)
        }
        if let language = MediaIdentifier.normalizedString(subtitle.language) {
          TorrentCardTag(text: language)
        }
        if downloaded {
          TorrentCardTag(text: "已下载")
        }
      }
      .font(.caption2)
      .foregroundColor(.secondary)
    }
    .padding(20)
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .background(.ultraThinMaterial)
    .clipShape(RoundedRectangle(cornerRadius: 20))
  }
}

struct SubtitleResultView: View {
  @Environment(\.dismiss) private var dismiss
  @StateObject private var search: SubtitleSearchSession
  @ObservedObject var imageLifecycle: PageImageLifecycle
  private let mediaInfo: MediaInfo?

  init(request: SubtitleSearchRequest, imageLifecycle: PageImageLifecycle) {
    self.mediaInfo = request.mediaInfo
    self.imageLifecycle = imageLifecycle
    _search = StateObject(wrappedValue: SubtitleSearchSession(request: request))
  }

  var body: some View {
    SubtitleResultsBody(search: search, imageLifecycle: imageLifecycle, onCancel: {
      search.cancel()
      dismiss()
    }) {
      Text(search.request.navigationTitle)
        .font(.largeTitle.bold())
        .foregroundColor(.secondary)
    }
    .background {
      SearchResultBackdrop(url: mediaInfo?.imageURLs.backdrop)
    }
    .task { search.start() }
  }
}
