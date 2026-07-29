import Foundation

/// 履歴アイテムの種別
public enum ItemKind: String, Codable, Equatable {
    case text
    case link
    case image
    case fileList
}

/// クリップボード履歴の 1 件分。実データ（flavors）は Persistence 側で別ファイル管理する。
public struct ClipboardItem: Codable, Identifiable, Equatable {
    public let id: UUID
    public let kind: ItemKind
    /// カード表示・検索用のプレビュー文字列（先頭 400 文字程度）
    public let preview: String
    public let charCount: Int?
    /// fileList の場合のみ: file:// URL 文字列の配列
    public let fileURLs: [String]?
    public let sourceAppName: String?
    public let sourceAppBundleID: String?
    public var createdAt: Date
    public var isPinned: Bool
    public let byteSize: Int
    /// 内容の SHA-256。重複判定に使う
    public let contentHash: String

    public init(
        id: UUID,
        kind: ItemKind,
        preview: String,
        charCount: Int?,
        fileURLs: [String]?,
        sourceAppName: String?,
        sourceAppBundleID: String?,
        createdAt: Date,
        isPinned: Bool,
        byteSize: Int,
        contentHash: String
    ) {
        self.id = id
        self.kind = kind
        self.preview = preview
        self.charCount = charCount
        self.fileURLs = fileURLs
        self.sourceAppName = sourceAppName
        self.sourceAppBundleID = sourceAppBundleID
        self.createdAt = createdAt
        self.isPinned = isPinned
        self.byteSize = byteSize
        self.contentHash = contentHash
    }
}

/// NSPasteboard から読み取った 1 回分のコピー内容（PasteCore は AppKit 非依存のため、
/// 読み取り自体はアプリ側で行い、この構造体に詰めて渡す）
public struct CapturedContent {
    /// UTI 文字列 → 生データ（例: "public.utf8-plain-text", "public.rtf", "public.png"）
    public let flavors: [String: Data]
    public let fileURLs: [String]
    public let sourceAppName: String?
    public let sourceAppBundleID: String?
    /// 画像の場合の "幅 × 高さ" 表示用ラベル
    public let imageSizeLabel: String?

    public init(
        flavors: [String: Data],
        fileURLs: [String] = [],
        sourceAppName: String? = nil,
        sourceAppBundleID: String? = nil,
        imageSizeLabel: String? = nil
    ) {
        self.flavors = flavors
        self.fileURLs = fileURLs
        self.sourceAppName = sourceAppName
        self.sourceAppBundleID = sourceAppBundleID
        self.imageSizeLabel = imageSizeLabel
    }
}

public enum Log {
    public static func error(_ message: String) {
        FileHandle.standardError.write(Data("[PasteDeck] \(message)\n".utf8))
    }
}
