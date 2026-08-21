import Flow
import SwiftDate
import SwiftUI

struct TorrentCard: View {
  let context: Context
  let media: MediaInfo?
  let meta: MetaInfo?
  let torrent: TorrentInfo?
  private let apiService = APIService.shared

  init(context: Context, overrideMediaInfo: MediaInfo? = nil) {
    self.context = context
    // 如果提供了 overrideMediaInfo，则使用它，否则使用 context.media_info
    media = overrideMediaInfo ?? context.media_info
    meta = context.meta_info
    torrent = context.torrent_info
  }

  private var volumeFactorColor: Color {
    guard let torrent = torrent else { return .secondary.opacity(0.3) }
    if torrent.downloadvolumefactor == 0 {
      return Color.green.opacity(0.3)
    } else if torrent.downloadvolumefactor < 1 {
      return Color.orange.opacity(0.3)
    } else if torrent.uploadvolumefactor > 1 {
      return Color.purple.opacity(0.3)
    } else {
      return Color.secondary.opacity(0.3)
    }
  }

  private var canAddDownload: Bool {
    apiService.canAccess(.search)
  }

  /// 主标题规范链：media.title → meta.name → torrent.title；纯空白视为缺值。
  static func displayTitle(media: MediaInfo?, meta: MetaInfo?, torrent: TorrentInfo?) -> String {
    MediaIdentifier.normalizedString(media?.title)
      ?? MediaIdentifier.normalizedString(meta?.name)
      ?? MediaIdentifier.normalizedString(torrent?.title)
      ?? ""
  }

  /// 副标题规范链：meta.subtitle → torrent.description；纯空白视为缺值。
  static func descriptionText(meta: MetaInfo?, torrent: TorrentInfo?) -> String? {
    MediaIdentifier.normalizedString(meta?.subtitle)
      ?? MediaIdentifier.normalizedString(torrent?.description)
  }

  @State private var showDownload = false
  @FocusState private var isButtonFocused: Bool

  var body: some View {
    if let torrent = torrent {
      let displayTitle = Self.displayTitle(media: media, meta: meta, torrent: torrent)
      VStack(alignment: .leading, spacing: 8) {
        // 媒体标题
        HStack(alignment: .top, spacing: 12) {
          HStack(spacing: 8) {
            if context.isFilteredOut {
              Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                  RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.2))
                )
                .foregroundColor(.white)
            }
            Text(displayTitle)
              .font(.headline)
              .fontWeight(.bold)
              .lineLimit(2)
              .multilineTextAlignment(.leading)
          }
          Spacer(minLength: 0)
          if let seasonEpisode = MediaIdentifier.normalizedString(meta?.season_episode) {
            Text(seasonEpisode.formattedSeasonEpisode())
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

        let descriptionText = Self.descriptionText(meta: meta, torrent: torrent)

        // 种子内容
        if let title = MediaIdentifier.normalizedString(torrent.title) {
          Text(title)
            .font(.caption)
            .foregroundColor(.secondary)
            .lineLimit(descriptionText == nil ? 4 : 2)
        }

        // 种子描述
        if let descriptionText {
          Text(descriptionText)
            .font(.caption2)
            .foregroundColor(.secondary)
            .lineLimit(2)
        }

        Spacer().frame(height: 4)

        // 信息条
        HStack {
          HStack(spacing: 15) {
            Text(torrent.size.formattedBytes())
            if let pubdate = torrent.pubdate {
              Text("•")
              Text(pubdate.toRelativeDateString())
            }
          }
          Spacer()
          HStack(spacing: 5) {
            if torrent.downloadvolumefactor != 1 || torrent.uploadvolumefactor != 1 {
              Text(torrent.volume_factor ?? "")
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                  RoundedRectangle(cornerRadius: 6)
                    .fill(volumeFactorColor)
                )
                .padding(.horizontal, 8)
            }
            if let seeders = torrent.seeders {
              if seeders > 0 {
                Image(systemName: "arrow.up")
                  .foregroundColor(seeders <= 5 ? .orange : .green)
                Text("\(seeders)")
                  .foregroundColor(seeders <= 5 ? .orange : .green)
              }
            }
          }
        }
        .font(.caption2)
        .foregroundColor(.secondary)

        Divider()
          .background(Color.primary)
          .padding(.vertical, 4)

        // 资源标签区
        HFlow(itemSpacing: 20, rowSpacing: 8) {
          // 站点
          if let siteName = MediaIdentifier.normalizedString(torrent.site_name) {
            TorrentCardTag(text: siteName)
          }
          // 流媒体平台
          if let webSource = MediaIdentifier.normalizedString(meta?.web_source) {
            TorrentCardTag(text: webSource)
          }
          // 版本标签
          if let edition = MediaIdentifier.normalizedString(meta?.edition) {
            TorrentCardTag(text: edition)
          }
          // 分辨率标签
          if let resourcePix = MediaIdentifier.normalizedString(meta?.resource_pix) {
            TorrentCardTag(text: resourcePix)
          }
          // 编码标签
          if let videoEncode = MediaIdentifier.normalizedString(meta?.video_encode) {
            TorrentCardTag(text: videoEncode)
          }
          // 制作组标签
          if let resourceTeam = MediaIdentifier.normalizedString(meta?.resource_team) {
            TorrentCardTag(text: resourceTeam)
          }
        }
        .font(.caption2)
        .foregroundColor(.secondary)
      }
      .padding(20)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.ultraThinMaterial)
      .clipShape(RoundedRectangle(cornerRadius: 20))
      .shadow(
        color: .black.opacity(isButtonFocused ? 0.5 : 0),
        radius: 20,
        y: 10
      )
      .scaleEffect(isButtonFocused ? 1.08 : 1.0)
      .animation(.easeInOut(duration: 0.2), value: isButtonFocused)
      .opacity(context.isFilteredOut ? 0.6 : 1.0)
      .grayscale(context.isFilteredOut ? 0.7 : 0.0)
      .focusable(true)
      .focused($isButtonFocused)
      .onTapGesture {
        guard canAddDownload else { return }
        showDownload = true
      }
      .contextMenu {
        if canAddDownload {
          Button {
            showDownload = true
          } label: {
            Label("下载", systemImage: "arrow.down.circle")
          }
        }
      }
      .sheet(
        isPresented: $showDownload,
        onDismiss: {
          // Sheet 关闭后将焦点恢复到此按钮
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isButtonFocused = true
          }
        }
      ) {
        AddDownloadSheet(torrent: torrent, media: media) {
          showDownload = false
        }
      }
    }
  }
}

struct TorrentCardTag: View {
  let text: String
  var body: some View {
    Text(text)
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(
        RoundedRectangle(cornerRadius: 6)
          .fill(.secondary.opacity(0.2))
      )
  }
}
