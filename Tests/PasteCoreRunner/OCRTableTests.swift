import Foundation
import PasteCore

func runOCRTableTests(_ t: TestHarness) {
    print("OCRTable:")

    t.run("テキスト形式はタブ区切りで Excel にそのまま貼れる") { t in
        let rows = [["名前", "数量"], ["りんご", "3"]]
        t.expect(
            TableFormatting.format(rows: rows, as: .text) == "名前\t数量\nりんご\t3",
            "行は改行・セルはタブ"
        )
    }

    t.run("1 行だけの表でも Markdown は区切り行を付ける") { t in
        // 区切り行が無いと Markdown の表として認識されない
        let result = TableFormatting.format(rows: [["a", "b"]], as: .markdown)
        t.expect(result == "| a | b |\n| --- | --- |", "ヘッダー行と区切り行の 2 行: \(result)")
    }

    t.run("1 行だけの表はテキストなら 1 行のまま") { t in
        t.expect(TableFormatting.format(rows: [["a", "b"]], as: .text) == "a\tb", "改行しない")
    }

    t.run("表が空なら空文字を返す") { t in
        // ヘッダーが取れないまま Markdown を組み立てると、区切り行だけの表ができる
        t.expect(TableFormatting.format(rows: [], as: .text).isEmpty, "テキスト")
        t.expect(TableFormatting.format(rows: [], as: .markdown).isEmpty, "Markdown")
    }

    t.run("空のセルは詰めずに位置を保つ") { t in
        // 詰めると列がずれて、貼り付け先の表と対応が取れなくなる
        t.expect(TableFormatting.format(rows: [["a", "", "c"]], as: .text) == "a\t\tc", "テキスト")
        t.expect(
            TableFormatting.format(rows: [["a", "", "c"]], as: .markdown).hasPrefix("| a |  | c |"),
            "Markdown"
        )
    }

    t.run("Markdown の区切り行は列数だけ --- を並べる") { t in
        let result = TableFormatting.format(rows: [["a", "b", "c"], ["1", "2", "3"]], as: .markdown)
        let lines = result.components(separatedBy: "\n")
        t.expect(lines.count == 3, "ヘッダー + 区切り + 1 行: \(lines.count)")
        t.expect(lines[1] == "| --- | --- | --- |", "3 列分の区切り: \(lines[1])")
    }

    t.run("セルの中のパイプを Markdown でエスケープする") { t in
        // エスケープしないとセルが分割され、列数が合わなくなる
        let result = TableFormatting.format(rows: [["a|b", "c"]], as: .markdown)
        t.expect(result.hasPrefix("| a\\|b | c |"), "\\| になる: \(result)")
    }

    t.run("セルの中の改行とタブは半角スペースに潰す") { t in
        // 潰さないとタブ区切り出力の列が崩れ、改行で行が分かれる
        t.expect(TableFormatting.format(rows: [["a\nb", "c"]], as: .text) == "a b\tc", "改行")
        t.expect(TableFormatting.format(rows: [["a\tb", "c"]], as: .text) == "a b\tc", "タブ")
    }

    t.run("セルの前後の空白を落とす") { t in
        t.expect(TableFormatting.format(rows: [["  a  ", " b "]], as: .text) == "a\tb", "trim される")
    }
}
