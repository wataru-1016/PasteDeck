import Combine
import Foundation

/// クリップボード履歴の中核。取り込み・重複排除・ピン留め・上限管理・永続化を担う。
/// UI からは ObservableObject として購読する。メインスレッドからの利用を前提とする。
public final class HistoryStore: ObservableObject {
    @Published public private(set) var items: [ClipboardItem] = []

    /// 値型のため読み取り用途なら他スレッドへ渡しても安全。
    /// バックグラウンドでの flavor 読み込みは HistoryStore を経由せずこちらを直接使う
    public let persistence: Persistence
    public private(set) var policy: RetentionPolicy

    public init(persistence: Persistence, policy: RetentionPolicy = .default) {
        self.persistence = persistence
        self.policy = policy
        self.items = persistence.loadIndex()
        applyRetention()
        persistence.pruneFlavors(keeping: Set(items.map(\.id)))
    }

    // MARK: - 保持ポリシー

    public func updatePolicy(_ newPolicy: RetentionPolicy, now: Date = Date()) {
        policy = newPolicy
        applyRetention(now: now)
    }

    /// 現在のポリシーで期限切れ・件数超過を整理する。
    /// 起動時・ポリシー変更時・定期チェックから呼ばれる
    public func applyRetention(now: Date = Date()) {
        let retained = retainedItems(from: items, now: now)
        guard retained != items else { return }
        items = retained
        persistIndex()
    }

    // MARK: - 取り込み

    public func ingest(_ content: CapturedContent, at now: Date = Date()) {
        let plainText = content.flavors[CaptureRules.plainTextType]
            .flatMap { String(data: $0, encoding: .utf8) }
        let hasImage = CaptureRules.imageTypes.contains { content.flavors[$0] != nil }

        guard let kind = CaptureRules.detectKind(
            text: plainText,
            hasImage: hasImage,
            fileURLCount: content.fileURLs.count
        ) else { return }

        let byteSize = content.flavors.values.reduce(0) { $0 + $1.count }
        guard byteSize <= CaptureRules.maxItemBytes else { return }

        let hash = CaptureRules.contentHash(flavors: content.flavors, fileURLs: content.fileURLs)

        // 既存アイテムと同一内容なら先頭へ移動（ピン状態・保存済みデータは維持）
        if let index = items.firstIndex(where: { $0.contentHash == hash }) {
            var moved = items[index]
            moved.createdAt = now
            var updated = items
            updated.remove(at: index)
            updated.insert(moved, at: 0)
            items = updated
            persistIndex()
            return
        }

        let item = ClipboardItem(
            id: UUID(),
            kind: kind,
            preview: Self.preview(for: kind, text: plainText, content: content),
            searchText: Self.searchText(for: kind, text: plainText),
            charCount: plainText?.count,
            fileURLs: content.fileURLs.isEmpty ? nil : content.fileURLs,
            sourceAppName: content.sourceAppName,
            sourceAppBundleID: content.sourceAppBundleID,
            createdAt: now,
            isPinned: false,
            byteSize: byteSize,
            contentHash: hash
        )

        if !content.flavors.isEmpty {
            do {
                try persistence.saveFlavors(content.flavors, id: item.id)
            } catch {
                Log.error("データの保存に失敗しました: \(error)")
                return
            }
        }

        var updated = items
        updated.insert(item, at: 0)
        items = retainedItems(from: updated, now: now)
        persistIndex()
    }

    // MARK: - 操作

    public func flavors(for id: UUID) -> [String: Data]? {
        persistence.loadFlavors(id: id)
    }

    public func togglePin(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        var updated = items
        updated[index].isPinned.toggle()
        items = updated
        persistIndex()
    }

    public func delete(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        persistence.deleteFlavors(id: id)
        var updated = items
        updated.remove(at: index)
        items = updated
        persistIndex()
    }

    /// 貼り付け時に呼ぶ。アイテムを先頭へ移動し、コピー時刻を更新する
    public func moveToFront(_ id: UUID, at now: Date = Date()) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        var moved = items[index]
        moved.createdAt = now
        var updated = items
        updated.remove(at: index)
        updated.insert(moved, at: 0)
        items = updated
        persistIndex()
    }

    public func clearUnpinned() {
        for item in items where !item.isPinned {
            persistence.deleteFlavors(id: item.id)
        }
        items = items.filter(\.isPinned)
        persistIndex()
    }

    public var unpinnedCount: Int {
        items.lazy.filter { !$0.isPinned }.count
    }

    // MARK: - 編集

    /// アイテムのテキストを差し替える（⌘E での編集）。
    ///
    /// 装飾（RTF・HTML）や画像の flavor は破棄し、プレーンテキストだけのアイテムにする。
    /// 理由は `TextEditRules` を参照。派生値（種別・preview・文字数・バイト数・ハッシュ）は
    /// すべて引き直す。ID・ピン状態・並び順・コピー元アプリは保持する
    public func replaceText(_ text: String, for id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let original = items[index]
        guard TextEditRules.canEdit(kind: original.kind, byteSize: original.byteSize) else { return }

        // URL を編集して URL でなくなる（またはその逆）ことがあるため種別も引き直す
        guard let kind = CaptureRules.detectKind(
            text: text,
            hasImage: false,
            fileURLCount: 0
        ) else { return }

        let flavors = TextEditRules.flavors(forEditedText: text)
        do {
            try persistence.saveFlavors(flavors, id: id)
        } catch {
            Log.error("編集内容の保存に失敗しました: \(error)")
            return
        }

        var updated = items
        updated[index] = ClipboardItem(
            id: original.id,
            kind: kind,
            preview: CaptureRules.makePreview(text),
            searchText: CaptureRules.searchText(text),
            charCount: text.count,
            fileURLs: nil,
            sourceAppName: original.sourceAppName,
            sourceAppBundleID: original.sourceAppBundleID,
            createdAt: original.createdAt,
            isPinned: original.isPinned,
            byteSize: flavors.values.reduce(0) { $0 + $1.count },
            contentHash: CaptureRules.contentHash(flavors: flavors, fileURLs: [])
        )
        items = updated
        persistIndex()
    }

    /// アイテムの画像を差し替える（⌘E での編集）。
    ///
    /// `replaceText` と同じく、派生値（preview・バイト数・ハッシュ）を引き直し、
    /// ID・ピン状態・並び順・コピー元アプリ・コピー時刻は保持する。
    /// 画像以外の flavor は破棄する（理由は `ImageEditRules.flavors(forEditedPNG:)`）
    public func replaceImage(
        _ png: Data,
        pixelWidth: Int,
        pixelHeight: Int,
        for id: UUID
    ) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let original = items[index]
        guard ImageEditRules.canEdit(kind: original.kind, byteSize: original.byteSize) else { return }
        guard ImageEditRules.canStore(byteCount: png.count) else {
            Log.error("編集後の画像が大きすぎるため保存しませんでした: \(png.count) バイト")
            return
        }

        let flavors = ImageEditRules.flavors(forEditedPNG: png)
        do {
            try persistence.saveFlavors(flavors, id: id)
        } catch {
            Log.error("編集した画像の保存に失敗しました: \(error)")
            return
        }

        let sizeLabel = ImageEditRules.sizeLabel(pixelWidth: pixelWidth, pixelHeight: pixelHeight)
        var updated = items
        updated[index] = ClipboardItem(
            id: original.id,
            kind: .image,
            preview: Self.imagePreview(sizeLabel: sizeLabel),
            // 画像に検索できる本文は無い
            searchText: nil,
            charCount: nil,
            fileURLs: nil,
            sourceAppName: original.sourceAppName,
            sourceAppBundleID: original.sourceAppBundleID,
            createdAt: original.createdAt,
            isPinned: original.isPinned,
            byteSize: png.count,
            contentHash: CaptureRules.contentHash(flavors: flavors, fileURLs: [])
        )
        items = updated
        persistIndex()
    }

    // MARK: - 内部処理

    private func persistIndex() {
        do {
            try persistence.saveIndex(items)
        } catch {
            Log.error("履歴インデックスの保存に失敗しました: \(error)")
        }
    }

    /// 保持ポリシーを適用した結果を返す。
    /// 期限切れ → 件数超過の順に、ピン留め以外の古いアイテムから削除する
    private func retainedItems(from list: [ClipboardItem], now: Date) -> [ClipboardItem] {
        var result = list

        if let maxAge = policy.maxAge {
            let cutoff = now.addingTimeInterval(-maxAge)
            for item in result where !item.isPinned && item.createdAt < cutoff {
                persistence.deleteFlavors(id: item.id)
            }
            result = result.filter { $0.isPinned || $0.createdAt >= cutoff }
        }

        if let maxItems = policy.maxItems {
            while result.count > maxItems, let index = result.lastIndex(where: { !$0.isPinned }) {
                persistence.deleteFlavors(id: result[index].id)
                result.remove(at: index)
            }
        }

        return result
    }

    /// 画像カードの見出し。取り込み時と ⌘E の編集後で同じ文言にする
    private static func imagePreview(sizeLabel: String?) -> String {
        sizeLabel.map { "画像 \($0)" } ?? "画像"
    }

    /// 検索用に持っておく本文。画像とファイルは preview（サイズ表記・ファイル名）で
    /// 全部言い尽くしているため、余分に持つものが無い
    private static func searchText(for kind: ItemKind, text: String?) -> String? {
        switch kind {
        case .text, .link:
            return CaptureRules.searchText(text ?? "")
        case .image, .fileList:
            return nil
        }
    }

    private static func preview(for kind: ItemKind, text: String?, content: CapturedContent) -> String {
        switch kind {
        case .text, .link:
            return CaptureRules.makePreview(text ?? "")
        case .image:
            return imagePreview(sizeLabel: content.imageSizeLabel)
        case .fileList:
            return content.fileURLs
                .compactMap { URL(string: $0)?.lastPathComponent }
                .joined(separator: ", ")
        }
    }
}
