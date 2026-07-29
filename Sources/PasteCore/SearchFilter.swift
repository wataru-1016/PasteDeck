import Foundation

/// 履歴の絞り込み（インクリメンタル検索・ピン留めフィルター）
public enum SearchFilter {
    public static func apply(_ items: [ClipboardItem], query: String, pinnedOnly: Bool) -> [ClipboardItem] {
        let base = pinnedOnly ? items.filter(\.isPinned) : items
        let tokens = query.lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard !tokens.isEmpty else { return base }
        return base.filter { item in
            let haystack = haystack(for: item)
            return tokens.allSatisfy { haystack.contains($0) }
        }
    }

    static func haystack(for item: ClipboardItem) -> String {
        var parts = [item.preview.lowercased()]
        if let appName = item.sourceAppName {
            parts.append(appName.lowercased())
        }
        if let urls = item.fileURLs {
            parts.append(contentsOf: urls.compactMap { URL(string: $0)?.lastPathComponent.lowercased() })
        }
        return parts.joined(separator: "\n")
    }
}
