import Foundation

/// OCR で得た表（行 × セル）をテキストに組み上げる（純粋関数のみ・テスト対象）
public enum TableFormatting {
    /// 2 次元の文字列配列をタブ区切り or Markdown の表テキストに変換する
    public static func format(rows: [[String]], as format: OutputFormat) -> String {
        // セルの中の改行・タブを残すと、タブ区切りの列も Markdown の行も崩れる
        let cleaned = rows.map { row in
            row.map {
                $0.replacingOccurrences(of: "\n", with: " ")
                    .replacingOccurrences(of: "\t", with: " ")
                    .trimmingCharacters(in: .whitespaces)
            }
        }
        switch format {
        case .text:
            return cleaned.map { $0.joined(separator: "\t") }.joined(separator: "\n")
        case .markdown:
            guard let header = cleaned.first else { return "" }
            func esc(_ s: String) -> String {
                s.replacingOccurrences(of: "|", with: "\\|")
            }
            var lines = ["| " + header.map(esc).joined(separator: " | ") + " |"]
            lines.append("| " + header.map { _ in "---" }.joined(separator: " | ") + " |")
            for row in cleaned.dropFirst() {
                lines.append("| " + row.map(esc).joined(separator: " | ") + " |")
            }
            return lines.joined(separator: "\n")
        }
    }
}
