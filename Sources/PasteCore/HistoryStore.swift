import Combine
import Foundation

/// クリップボード履歴の中核。取り込み・重複排除・ピン留め・上限管理・永続化を担う。
/// UI からは ObservableObject として購読する。メインスレッドからの利用を前提とする。
public final class HistoryStore: ObservableObject {
    @Published public private(set) var items: [ClipboardItem] = []

    private let persistence: Persistence
    private let maxItems: Int

    public init(persistence: Persistence, maxItems: Int = CaptureRules.maxItems) {
        self.persistence = persistence
        self.maxItems = maxItems
        self.items = persistence.loadIndex()
        persistence.pruneFlavors(keeping: Set(items.map(\.id)))
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
        items = trimmed(updated)
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

    // MARK: - 内部処理

    private func persistIndex() {
        do {
            try persistence.saveIndex(items)
        } catch {
            Log.error("履歴インデックスの保存に失敗しました: \(error)")
        }
    }

    /// 上限超過分を「ピン留めされていない最も古いもの」から削除する
    private func trimmed(_ list: [ClipboardItem]) -> [ClipboardItem] {
        var result = list
        while result.count > maxItems, let index = result.lastIndex(where: { !$0.isPinned }) {
            persistence.deleteFlavors(id: result[index].id)
            result.remove(at: index)
        }
        return result
    }

    private static func preview(for kind: ItemKind, text: String?, content: CapturedContent) -> String {
        switch kind {
        case .text, .link:
            return CaptureRules.makePreview(text ?? "")
        case .image:
            return content.imageSizeLabel.map { "画像 \($0)" } ?? "画像"
        case .fileList:
            return content.fileURLs
                .compactMap { URL(string: $0)?.lastPathComponent }
                .joined(separator: ", ")
        }
    }
}
