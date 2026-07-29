import Foundation

/// 履歴の永続化。
/// - `items.json` … メタデータのインデックス
/// - `flavors/<UUID>.plist` … 各アイテムの生データ（UTI → Data の辞書）
public struct Persistence {
    public let rootURL: URL
    private let indexURL: URL
    private let flavorsDir: URL

    public init(rootURL: URL) throws {
        self.rootURL = rootURL
        self.indexURL = rootURL.appendingPathComponent("items.json")
        self.flavorsDir = rootURL.appendingPathComponent("flavors", isDirectory: true)
        try FileManager.default.createDirectory(at: flavorsDir, withIntermediateDirectories: true)
    }

    public static func defaultRootURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let root = base.appendingPathComponent("PasteDeck", isDirectory: true)

        // 旧アプリ名（PasteLocal）時代の履歴があれば一度だけ引き継ぐ
        let legacyRoot = base.appendingPathComponent("PasteLocal", isDirectory: true)
        if !FileManager.default.fileExists(atPath: root.path),
           FileManager.default.fileExists(atPath: legacyRoot.path) {
            do {
                try FileManager.default.moveItem(at: legacyRoot, to: root)
            } catch {
                Log.error("旧履歴ディレクトリの移行に失敗しました: \(error)")
            }
        }
        return root
    }

    private struct IndexFile: Codable {
        var version: Int
        var items: [ClipboardItem]
    }

    public func loadIndex() -> [ClipboardItem] {
        guard FileManager.default.fileExists(atPath: indexURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: indexURL)
            return try JSONDecoder().decode(IndexFile.self, from: data).items
        } catch {
            Log.error("履歴インデックスの読み込みに失敗しました: \(error)")
            let backupURL = rootURL.appendingPathComponent("items.corrupt.json")
            try? FileManager.default.removeItem(at: backupURL)
            try? FileManager.default.moveItem(at: indexURL, to: backupURL)
            return []
        }
    }

    public func saveIndex(_ items: [ClipboardItem]) throws {
        let encoder = JSONEncoder()
        // Date は内部表現 (timeIntervalSinceReferenceDate) のまま保存する。
        // secondsSince1970 等へ変換すると浮動小数点誤差で復元時に値がズレる
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(IndexFile(version: 1, items: items))
        try data.write(to: indexURL, options: .atomic)
    }

    public func saveFlavors(_ flavors: [String: Data], id: UUID) throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: flavors,
            format: .binary,
            options: 0
        )
        try data.write(to: flavorURL(id), options: .atomic)
    }

    public func loadFlavors(id: UUID) -> [String: Data]? {
        guard let data = try? Data(contentsOf: flavorURL(id)) else { return nil }
        let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return plist as? [String: Data]
    }

    public func deleteFlavors(id: UUID) {
        try? FileManager.default.removeItem(at: flavorURL(id))
    }

    /// インデックスに存在しない孤児データファイルを削除する（クラッシュ時の整合性回復）
    public func pruneFlavors(keeping ids: Set<UUID>) {
        let keepNames = Set(ids.map { $0.uuidString + ".plist" })
        let files = (try? FileManager.default.contentsOfDirectory(atPath: flavorsDir.path)) ?? []
        for file in files where !keepNames.contains(file) {
            try? FileManager.default.removeItem(at: flavorsDir.appendingPathComponent(file))
        }
    }

    private func flavorURL(_ id: UUID) -> URL {
        flavorsDir.appendingPathComponent(id.uuidString + ".plist")
    }
}
