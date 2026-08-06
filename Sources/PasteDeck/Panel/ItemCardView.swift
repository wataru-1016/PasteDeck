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
    /// このカードを直接貼り付けるキーの表記（先頭 9 枚だけ。10 枚目以降は nil）
    let quickPasteKey: String?
    @ObservedObject var viewModel: PanelViewModel

    /// ここまで動かしたらドラッグと見なす。小さすぎると、
    /// 選ぼうとしたクリックの手ぶれでカードが飛び出してしまう
    private static let dragThreshold: CGFloat = 8

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
        // 掴んで Finder などへ直接置けるようにする。AppKit のドラッグセッションを
        // 自分で始めるため、ここでは「動かし始めた」ことだけを拾う。
        // 二重に始まらないよう、実際の開始判定は PanelViewModel 側で行う
        .simultaneousGesture(
            DragGesture(minimumDistance: Self.dragThreshold)
                .onChanged { _ in viewModel.beginDrag(item) }
        )
    }

    // MARK: - ヘッダー

    private var header: some View {
        HStack(spacing: 8) {
            // 押せるキーをカード自身に出しておく。ヒント欄に「⌘1〜9」とだけ書いても、
            // 何枚目が何番なのかは数えないと分からない
            if let quickPasteKey {
                KeycapView(key: quickPasteKey, fontSize: 10, minWidth: 24)
                    // 長いアプリ名との横幅の取り合いで潰れないようにする。
                    // 「⌘…」と切られては、どのキーなのか読めない
                    .fixedSize()
                    .help("\(quickPasteKey) でこの項目を貼り付け")
            }
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
            TextBodyView(item: item, persistence: viewModel.store.persistence)

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
            FileListBodyView(item: item)
        }
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

/// テキストアイテムの本文表示。
/// Excel・Word などのコピーは RTF flavor に元の書式を持つため、読み込めた場合は
/// コピー元の色・太さ・サイズ・フォントを反映する。無ければプレーン表示のまま
private struct TextBodyView: View {
    let item: ClipboardItem
    let persistence: Persistence

    @State private var richText: AttributedString?

    var body: some View {
        content
            .lineLimit(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(12)
            .onAppear { loadRichText() }
            // ⌘E で編集したあとも同じカードが使い回されて onAppear が再発火しないため、
            // 内容の変化（ハッシュ）を見て読み直す
            .onChange(of: item.contentHash) { loadRichText() }
    }

    private func loadRichText() {
        RichTextProvider.shared.richText(for: item, persistence: persistence) { result in
            richText = result
        }
    }

    @ViewBuilder
    private var content: some View {
        if let richText {
            Text(richText)
        } else {
            Text(item.preview)
                .font(.system(size: RichTextStyle.baseFontSize))
        }
    }
}

/// ファイルアイテムの本文表示。
///
/// 履歴が持っているのはファイルの場所（URL）だけで、実体は PasteDeck の外にある。
/// 移動・削除されると貼っても何も出てこないため、実体がまだ在るかを確かめて
/// 貼る前に知らせる
private struct FileListBodyView: View {
    let item: ClipboardItem

    @State private var linkStatus: FileLinkStatus = .available

    private var urls: [URL] {
        (item.fileURLs ?? []).compactMap { URL(string: $0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
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
            if let warning = FileLinkRules.warning(for: linkStatus) {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                    Text(warning)
                        .lineLimit(2)
                }
                .font(.caption2)
                .foregroundStyle(.orange)
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
        .onAppear(perform: checkLinks)
    }

    /// 外付けやネットワークのボリュームだと 1 件の確認でも待たされることがあるため、
    /// パネルが固まらないようメインスレッドの外で確かめる
    private func checkLinks() {
        let targets = urls
        DispatchQueue.global(qos: .utility).async {
            let status = FileLinkRules.status(of: targets)
            DispatchQueue.main.async { linkStatus = status }
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
            .onAppear { loadThumbnail() }
            // ⌘E で描き込んだあとも同じカードが使い回されて onAppear が再発火しないため、
            // 内容の変化（ハッシュ）を見て読み直す
            .onChange(of: item.contentHash) { loadThumbnail() }
    }

    private func loadThumbnail() {
        ThumbnailProvider.shared.thumbnail(for: item, persistence: persistence) { image in
            thumbnail = image
        }
    }
}
