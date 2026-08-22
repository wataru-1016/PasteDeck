import Foundation

/// OCR で読み取った JSON らしいテキストの整形（純粋関数のみ・テスト対象）
public enum JSONFormatting {
    /// 埋め込み JSON のキー名を遡って探すときの上限文字数。
    /// 上限が無いと、引用符が片方だけ現れる長文で先頭まで舐めてしまう
    private static let keyLookbackLimit = 80
    /// 埋め込み JSON として採用する最小の文字数。
    /// これより短いと、単なる記号の並びを JSON と誤検出する
    private static let embeddedMinLength = 10

    /// OCR 結果が JSON らしいかを判定する（{ か [ で始まり、: か , を含む）
    public static func looksLikeJSON(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return false }
        return (first == "{" || first == "[") && (trimmed.contains(":") || trimmed.contains(","))
    }

    /// JSON をインデント付きで整形し直す。
    ///
    /// キーの順番を保つため、パーサーではなく文字単位の走査で整形する
    /// （多少壊れた JSON でも動くので、OCR の読み取りミスがあっても整形できる）
    public static func prettyPrint(_ raw: String) -> String {
        // OCR で化けやすい文字を修正する:
        //   曲がった引用符 → まっすぐな引用符、全角の括弧・コロン・カンマ → 半角
        let quoteFixes: [Character: Character] = [
            "\u{201C}": "\"", "\u{201D}": "\"", "\u{301D}": "\"", "\u{301E}": "\"",
            "\u{FF02}": "\"", "\u{2018}": "'", "\u{2019}": "'",
            "｛": "{", "｝": "}", "［": "[", "］": "]",
            "：": ":", "，": ",", "．": ".",
        ]
        var source = String(raw.map { quoteFixes[$0] ?? $0 })

        // OCR の誤読でよくある壊れ方を修復する:
        //   1. キーの引用符の二重化      "msg"":  → "msg":
        //   2. カンマが「。」に化ける     "値"。"次 → "値","次
        //   3. カンマが「.」に化ける      "値"."次 → "値","次
        //      （JSON では 閉じ引用符+ピリオド+開き引用符 の並びは正しくは存在しないため安全）
        source = source.replacingOccurrences(
            of: "\"\"\\s*:", with: "\":", options: .regularExpression)
        source = source.replacingOccurrences(
            of: "\"\\s*。\\s*\"", with: "\",\"", options: .regularExpression)
        source = source.replacingOccurrences(
            of: "\"\\s*\\.\\s*\"", with: "\",\"", options: .regularExpression)

        let chars = Array(source)
        var out = ""
        var depth = 0
        var inString = false
        var escaped = false
        let indentUnit = "  "

        func newlineIndent(_ d: Int) {
            out += "\n" + String(repeating: indentUnit, count: max(0, d))
        }

        var i = 0
        while i < chars.count {
            let c = chars[i]

            if inString {
                out.append(c)
                if escaped {
                    escaped = false
                } else if c == "\\" {
                    escaped = true
                } else if c == "\"" {
                    inString = false
                }
                i += 1
                continue
            }

            switch c {
            case "\"":
                inString = true
                out.append(c)
            case "{", "[":
                // 空の {} / [] は改行せずそのまま出す
                var j = i + 1
                while j < chars.count, " \n\t\r".contains(chars[j]) { j += 1 }
                if j < chars.count,
                   (c == "{" && chars[j] == "}") || (c == "[" && chars[j] == "]") {
                    out.append(c)
                    out.append(chars[j])
                    i = j + 1
                    continue
                }
                out.append(c)
                depth += 1
                newlineIndent(depth)
            case "}", "]":
                depth -= 1
                newlineIndent(depth)
                out.append(c)
            case ",":
                out.append(c)
                newlineIndent(depth)
            case ":":
                out += ": "
            case " ", "\n", "\t", "\r":
                break  // 文字列の外の空白は捨てて配置し直す
            default:
                out.append(c)
            }
            i += 1
        }
        return out
    }

    /// 文章の中に埋め込まれた JSON らしい塊を探す。
    ///
    /// 例:「エラー時のレスポンス： "response": {"code": 200, ...} となる」
    /// 見つかれば (前の文章, JSON 部分, 後の文章) を返し、なければ nil。
    /// OCR で全角化した括弧（｛［）も開き括弧として扱う
    public static func extractEmbedded(_ text: String) -> (before: String, json: String, after: String)? {
        let chars = Array(text)
        let openBrackets: Set<Character> = ["{", "[", "｛", "［"]
        let closeBrackets: Set<Character> = ["}", "]", "｝", "］"]
        let quoteChars: Set<Character> = [
            "\"", "\u{201C}", "\u{201D}", "\u{301D}", "\u{301E}", "\u{FF02}",
        ]

        // 最初の開き括弧を探す
        guard let firstBracket = chars.firstIndex(where: { openBrackets.contains($0) })
        else { return nil }

        // JSON らしさの確認: 開き括弧の直後（空白を除く）が
        // 引用符・数字・括弧のどれかであること（普通の文章の括弧を誤検出しないため）
        var q = firstBracket + 1
        while q < chars.count, chars[q] == " " || chars[q] == "\n" { q += 1 }
        guard q < chars.count else { return nil }
        let nextChar = chars[q]
        guard quoteChars.contains(nextChar) || nextChar.isNumber
                || openBrackets.contains(nextChar) || nextChar == "'"
        else { return nil }

        // ブロックの終わり: 括弧の深さが 0 に戻る位置（閉じ括弧が欠けていれば末尾まで）
        var depth = 0
        var end = chars.count
        for i in firstBracket..<chars.count {
            if openBrackets.contains(chars[i]) {
                depth += 1
            } else if closeBrackets.contains(chars[i]) {
                depth -= 1
                if depth == 0 {
                    end = i + 1
                    break
                }
            }
        }

        // ブロックの始まり: 直前が『"キー名": 』の形なら、そのキーの引用符まで含める
        var start = firstBracket
        var k = firstBracket - 1
        while k >= 0, chars[k] == " " || chars[k] == "\n" { k -= 1 }
        if k >= 0, chars[k] == ":" || chars[k] == "：" {
            k -= 1
            while k >= 0, chars[k] == " " || chars[k] == "\n" { k -= 1 }
            if k >= 0, quoteChars.contains(chars[k]) {
                var j = k - 1
                var steps = 0
                while j >= 0, steps < keyLookbackLimit, !quoteChars.contains(chars[j]) {
                    j -= 1
                    steps += 1
                }
                if j >= 0, quoteChars.contains(chars[j]) {
                    start = j
                }
            }
        }

        let jsonPart = String(chars[start..<end])
        // 最低条件: コロンを含み、ある程度の長さがあること
        guard jsonPart.contains(":") || jsonPart.contains("："),
              jsonPart.count >= embeddedMinLength
        else { return nil }

        let before = String(chars[..<start]).trimmingCharacters(in: .whitespacesAndNewlines)
        let after = String(chars[end...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return (before, jsonPart, after)
    }

    /// 文章と JSON が混ざったテキストを「文章＋整形済み JSON ブロック＋文章」の形に組み立てる。
    /// JSON が見つからなければ nil
    public static func formatMixedContent(_ text: String, format: OutputFormat) -> String? {
        guard let embedded = extractEmbedded(text) else { return nil }
        var parts: [String] = []
        if !embedded.before.isEmpty { parts.append(embedded.before) }
        parts.append(format.wrapJSON(prettyPrint(embedded.json)))
        if !embedded.after.isEmpty { parts.append(embedded.after) }
        return parts.joined(separator: "\n\n")
    }
}
