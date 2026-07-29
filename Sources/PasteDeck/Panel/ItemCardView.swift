import PasteCore
import SwiftUI

extension ItemKind {
    var symbolName: String {
        switch self {
        case .text: return "text.alignleft"
        case .link: return "link"
        case .image: return "photo"
        case .fileList: return "doc.on.doc"
        }
    }

    var tint: Color {
        switch self {
        case .text: return .blue
        case .link: return .purple
        case .image: return .orange
        case .fileList: return .green
        }
    }
}

/// 履歴 1 件分のカード
struct ItemCardView: View {
    let item: ClipboardItem
    let isSelected: Bool
    @ObservedObject var viewModel: PanelViewModel

    @State private var isHovering = false

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.dateTimeStyle = .named
        return formatter
    }()

    var body: some View {
        VStack(spacing: 0) {
            header
            bodyContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
        }
        .frame(width: 240, height: 214)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.92))
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    isSelected ? Color.accentColor : Color.primary.opacity(0.09),
                    lineWidth: isSelected ? 2.5 : 1
                )
        )
        .shadow(
            color: .black.opacity(isHovering || isSelected ? 0.22 : 0.12),
            radius: isHovering || isSelected ? 12 : 6,
            y: 4
        )
        .offset(y: isHovering ? -2 : 0)
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .onHover { isHovering = $0 }
        .simultaneousGesture(TapGesture().onEnded { viewModel.select(item) })
        .onTapGesture(count: 2) { viewModel.activate(item) }
    }

    // MARK: - ヘッダー

    private var header: some View {
        HStack(spacing: 8) {
            Image(nsImage: AppIconProvider.icon(forBundleID: item.sourceAppBundleID))
                .resizable()
                .frame(width: 17, height: 17)
            Text(item.sourceAppName ?? "不明なアプリ")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 4)

            if isHovering {
                hoverActions
            } else {
                if item.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.accentColor)
                }
                Image(systemName: item.kind.symbolName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(item.kind.tint)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(item.kind.tint.opacity(0.10))
    }

    private var hoverActions: some View {
        HStack(spacing: 6) {
            Button {
                viewModel.togglePin(item)
            } label: {
                Image(systemName: item.isPinned ? "pin.slash" : "pin")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.plain)
            .help(item.isPinned ? "ピンを外す" : "ピン留め")

            Button {
                viewModel.delete(item)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.plain)
            .help("削除")
        }
        .foregroundStyle(.secondary)
    }

    // MARK: - 本文

    @ViewBuilder
    private var bodyContent: some View {
        switch item.kind {
        case .text:
            Text(item.preview)
                .font(.system(size: 12.5))
                .lineLimit(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(12)

        case .link:
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "link")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(ItemKind.link.tint)
                Text(item.preview)
                    .font(.system(size: 12))
                    .foregroundStyle(ItemKind.link.tint)
                    .lineLimit(4)
                if let host = URL(string: item.preview)?.host {
                    Text(host)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(12)

        case .image:
            ImageThumbnailView(item: item, persistence: viewModel.store.persistence)

        case .fileList:
            fileListBody
        }
    }

    private var fileListBody: some View {
        let urls = (item.fileURLs ?? []).compactMap { URL(string: $0) }
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(urls.prefix(2).enumerated()), id: \.offset) { _, url in
                HStack(spacing: 6) {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(ItemKind.fileList.tint)
                    Text(url.lastPathComponent)
                        .font(.system(size: 12))
                        .lineLimit(1)
                }
            }
            if urls.count > 2 {
                Text("ほか \(urls.count - 2) 件")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let firstURL = urls.first {
                FileThumbnailView(
                    url: firstURL,
                    cacheKey: item.id.uuidString + firstURL.absoluteString
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
    }

    // MARK: - フッター

    private var footer: some View {
        HStack {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(Self.relativeFormatter.localizedString(for: item.createdAt, relativeTo: context.date))
            }
            Spacer()
            Text(metaLabel)
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 12)
        .frame(height: 26)
    }

    private var metaLabel: String {
        switch item.kind {
        case .text:
            return "\(item.charCount ?? 0) 文字"
        case .link:
            return "リンク"
        case .image:
            return ByteCountFormatter.string(fromByteCount: Int64(item.byteSize), countStyle: .file)
        case .fileList:
            return "\(item.fileURLs?.count ?? 0) ファイル"
        }
    }
}

/// ファイルアイテムの Quick Look サムネイル表示。
/// 生成が終わるまではファイルアイコンをプレースホルダーとして出す
private struct FileThumbnailView: View {
    let url: URL
    let cacheKey: String

    @State private var thumbnail: NSImage?

    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.04))
            .overlay {
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                        .resizable()
                        .scaledToFit()
                        .frame(width: 40, height: 40)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                FileThumbnailProvider.shared.thumbnail(for: url, cacheKey: cacheKey) { image in
                    thumbnail = image
                }
            }
    }
}

/// 画像アイテムのサムネイル表示
private struct ImageThumbnailView: View {
    let item: ClipboardItem
    let persistence: Persistence

    @State private var thumbnail: NSImage?

    var body: some View {
        // scaledToFill した Image を直接レイアウトに置くと親のサイズ提案を超えて
        // レイアウト自体を押し広げてしまうため、サイズに関与しない overlay に載せる
        Rectangle()
            .fill(Color.primary.opacity(0.04))
            .overlay {
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 22))
                        .foregroundStyle(.quaternary)
                }
            }
            .clipped()
            .onAppear {
                ThumbnailProvider.shared.thumbnail(for: item, persistence: persistence) { image in
                    thumbnail = image
                }
            }
    }
}
