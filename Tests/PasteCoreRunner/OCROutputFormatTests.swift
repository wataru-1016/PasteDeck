import Foundation
import PasteCore

func runOCROutputFormatTests(_ t: TestHarness) {
    print("OCROutputFormat:")

    t.run("テキスト形式は整形済み JSON をそのまま返す") { t in
        // Excel などへ貼るときにコードブロックの記号が混ざると使いものにならない
        t.expect(OutputFormat.text.wrapJSON("{}") == "{}", "囲まない")
        t.expect(OutputFormat.text.wrapJSON("{\n  \"a\": 1\n}") == "{\n  \"a\": 1\n}", "改行入りもそのまま")
    }

    t.run("Markdown 形式は json のコードブロックで包む") { t in
        t.expect(OutputFormat.markdown.wrapJSON("{}") == "```json\n{}\n```", "```json で始まり ``` で終わる")
    }

    t.run("rawValue が変わると保存済みの設定が読めなくなる") { t in
        // OCRPreferences が rawValue で永続化するため、綴りを変えてはいけない
        t.expect(OutputFormat.text.rawValue == "text", "text")
        t.expect(OutputFormat.markdown.rawValue == "markdown", "markdown")
        t.expect(OutputFormat.allCases.count == 2, "形式は 2 種")
    }
}
