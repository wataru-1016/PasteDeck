import Foundation

/// OCR の行を自然な文章へ連結する（純粋関数のみ・テスト対象）
public enum LineJoining {
    /// 1 文字が CJK（日本語・中国語など全角圏の文字）かどうかを判定する
    public static func isCJK(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first else { return false }
        let v = scalar.value
        return (0x3000...0x303F).contains(v)   // 句読点など（。、「」）
            || (0x3040...0x30FF).contains(v)   // ひらがな・カタカナ
            || (0x3400...0x4DBF).contains(v)   // 漢字（拡張A）
            || (0x4E00...0x9FFF).contains(v)   // 漢字
            || (0xF900...0xFAFF).contains(v)   // 漢字（互換）
            || (0xFF00...0xFFEF).contains(v)   // 全角英数・記号
    }

    /// OCR で得た行のリストを、自然な文章になるよう連結する。
    /// - 日本語の行同士: 改行を消してそのまま連結
    /// - 英語の行同士: 半角スペースで連結（行末ハイフンは単語の分割とみなして結合）
    /// - `paragraphBreaks` に含まれる行番号の直前では空行（段落の区切り）を入れる
    public static func join(_ lines: [String], paragraphBreaks: Set<Int> = []) -> String {
        var result = ""
        for (index, rawLine) in lines.enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            if result.isEmpty {
                result = line
                continue
            }

            if paragraphBreaks.contains(index) {
                result += "\n\n" + line
                continue
            }

            let last = result.last!
            let first = line.first!

            if isCJK(last) || isCJK(first) {
                // 日本語が絡む行境界: 改行を除去してそのまま連結
                result += line
            } else if last == "-" {
                // 英語の行末ハイフン: "infor-" + "mation" → "information"
                result.removeLast()
                result += line
            } else {
                // 英語同士: スペースで連結
                result += " " + line
            }
        }
        return result
    }
}
