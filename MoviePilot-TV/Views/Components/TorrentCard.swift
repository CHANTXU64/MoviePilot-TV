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

  @State private var showDownload = false
  @FocusState private var isButtonFocused: Bool

  var body: some View {
    if let meta = meta, let torrent = torrent {
      Button(action: {
        showDownload = true
      }) {
        VStack(alignment: .leading, spacing: 8) {
          // 媒体标题
          HStack(alignment: .top, spacing: 12) {
            Text(media?.title ?? meta.name)
              .font(.headline)
              .fontWeight(.bold)
              .lineLimit(2)
              .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            if !meta.season_episode.isEmpty {
              Text(meta.season_episode)
                .font(.caption2)
                .fontWeight(.semibold)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                  RoundedRectangle(cornerRadius: 6)
                    .fill(.secondary.opacity(0.5))
                )
            }
          }

          let descriptionText = meta.subtitle ?? torrent.description
          let shouldShowDescription = (descriptionText?.isEmpty == false)

          // 种子内容
          if let title = torrent.title {
            Text(title)
              .font(.caption)
              .foregroundColor(.secondary)
              .lineLimit(shouldShowDescription ? 2 : 4)
          }

          // 种子描述
          if shouldShowDescription {
            Text(descriptionText!)
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
            if let site_name = torrent.site_name {
              TorrentCardTag(text: site_name)
            }
            // 流媒体平台
            if meta.web_source != nil && !meta.web_source!.isEmpty {
              TorrentCardTag(text: meta.web_source!)
            }
            // <!-- 版本标签 -->
            if meta.edition != nil && !meta.edition!.isEmpty {
              TorrentCardTag(text: meta.edition!)
            }
            // <!-- 分辨率标签 -->
            if let resource_pix = meta.resource_pix {
              TorrentCardTag(text: resource_pix)
            }
            // <!-- 编码标签 -->
            if let video_encode = meta.video_encode {
              TorrentCardTag(text: video_encode)
            }
            // <!-- 制作组标签 -->
            if meta.resource_team != nil && !meta.resource_team!.isEmpty {
              TorrentCardTag(text: meta.resource_team!)
            }
          }
          .font(.caption2)
          .foregroundColor(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .buttonStyle(.card)
      .focused($isButtonFocused)
      .compositingGroup()
      .contextMenu {
        Button {
          showDownload = true
        } label: {
          Label("下载", systemImage: "arrow.down.circle")
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
    } else {
      // 记录缺失的数据（可选，依赖内存或控制台，但根据请求隐藏）
      EmptyView()
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
          .fill(.secondary.opacity(0.5))
      )
  }
}
