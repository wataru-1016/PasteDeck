import Foundation

/// 履歴の絞り込み（インクリメンタル検索・ピン留めフィルター）
public enum SearchFilter {
    public static func apply(_ items: [ClipboardItem], query: String, pinnedOnly: Bool) -> [ClipboardItem] {
        let base = pinnedOnly ? items.filter(\.isPinned) : items
        let tokens = SearchText.normalized(query)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard !tokens.isEmpty else { return base }
        return base.filter { item in
            let haystack = haystack(for: item)
            return tokens.allSatisfy { haystack.contains($0) }
        }
    }

    static func haystack(for item: ClipboardItem) -> String {
        // preview は先頭 400 文字で切れているため、その先を持っているものはそちらを見る。
        // 長いメール本文の後半にある語で探せないと「あの文どこだっけ」に応えられない
        var parts = [item.searchText ?? item.preview]
        if let appName = item.sourceAppName {
            parts.append(appName)
        }
        if let urls = item.fileURLs {
            parts.append(contentsOf: urls.compactMap { URL(string: $0)?.lastPathComponent })
        }
        // 部品ごとに正規化すると同じ処理を何度も走らせることになるため、繋いでから一度だけ掛ける
        return SearchText.normalized(parts.joined(separator: "\n"))
    }
}
