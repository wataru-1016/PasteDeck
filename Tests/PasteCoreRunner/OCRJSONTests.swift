import Foundation
import PasteCore

func runOCRJSONTests(_ t: TestHarness) {
    print("OCRJSON:")

    t.run("JSON らしさは開き括弧と区切り文字の両方で判定する") { t in
        t.expect(JSONFormatting.looksLikeJSON("{\"a\":1}"), "オブジェクト")
        t.expect(JSONFormatting.looksLikeJSON("[1,2]"), "配列")
        t.expect(JSONFormatting.looksLikeJSON("  \n{\"a\":1}  "), "前後の空白は無視する")
    }

    t.run("JSON でないものを JSON 扱いしない") { t in
        // ここで true になると、普通の文章が整形器にかけられて改行だらけになる
        t.expect(!JSONFormatting.looksLikeJSON(""), "空文字")
        t.expect(!JSONFormatting.looksLikeJSON("こんにちは"), "普通の文章")
        t.expect(!JSONFormatting.looksLikeJSON("{}"), "区切り文字が無い")
        t.expect(!JSONFormatting.looksLikeJSON("a: 1, b: 2"), "括弧で始まらない")
    }

    t.run("OCR で化けた引用符と全角記号を直す") { t in
        // 曲がった引用符のまま整形すると、文字列の開始を検出できず全体が壊れる
        let curly = JSONFormatting.prettyPrint("{\u{201C}a\u{201D}:1}")
        t.expect(curly.contains("\"a\""), "曲がった引用符がまっすぐになる: \(curly)")

        let fullwidth = JSONFormatting.prettyPrint("｛\"a\"：1，\"b\"：2｝")
        t.expect(fullwidth.hasPrefix("{"), "全角の開き括弧が半角になる: \(fullwidth)")
        t.expect(fullwidth.contains("\"a\": 1"), "全角コロンが半角になる: \(fullwidth)")
        t.expect(fullwidth.contains("\"b\": 2"), "全角カンマが区切りとして働く: \(fullwidth)")
    }

    t.run("キーの引用符の二重化を直す") { t in
        // OCR は閉じ引用符を 2 個に読み違えることがある
        let result = JSONFormatting.prettyPrint("{\"msg\"\": 1}")
        t.expect(result.contains("\"msg\": 1"), "\"msg\": になる: \(result)")
    }

    t.run("カンマが句点やピリオドに化けたのを直す") { t in
        // 「"値"。"次"」は JSON として存在しない並びなので、カンマの誤読とみなして安全
        let kuten = JSONFormatting.prettyPrint("[\"値\"。\"次\"]")
        t.expect(kuten.contains("\"値\","), "句点がカンマになる: \(kuten)")

        let period = JSONFormatting.prettyPrint("[\"値\".\"次\"]")
        t.expect(period.contains("\"値\","), "ピリオドがカンマになる: \(period)")
    }

    t.run("ネストの深さだけ 2 スペースで字下げする") { t in
        let result = JSONFormatting.prettyPrint("{\"a\":{\"b\":1}}")
        t.expect(result == "{\n  \"a\": {\n    \"b\": 1\n  }\n}", "2 段の字下げ: \(result)")
    }

    t.run("空の {} と [] は改行を挟まない") { t in
        // 空なのに 2 行に割ると、読み取り結果が無駄に縦に伸びる
        t.expect(JSONFormatting.prettyPrint("{\"a\":{}}").contains("\"a\": {}"), "空オブジェクト")
        t.expect(JSONFormatting.prettyPrint("{\"a\":[]}").contains("\"a\": []"), "空配列")
        t.expect(JSONFormatting.prettyPrint("{\"a\":{ }}").contains("\"a\": {}"), "中に空白があっても空とみなす")
    }

    t.run("文字列の中の記号は整形の対象にしない") { t in
        // 文字列の中のカンマで改行すると、値そのものが壊れる
        let result = JSONFormatting.prettyPrint("{\"a\":\"x,y{z}\"}")
        t.expect(result.contains("\"x,y{z}\""), "中身がそのまま残る: \(result)")
    }

    t.run("エスケープされた引用符で文字列が途中で切れない") { t in
        let result = JSONFormatting.prettyPrint("{\"a\":\"x\\\"y\",\"b\":1}")
        t.expect(result.contains("\"x\\\"y\""), "エスケープを保つ: \(result)")
        t.expect(result.contains("\"b\": 1"), "後続のキーも整形される: \(result)")
    }

    t.run("閉じ括弧が欠けていても例外を投げずに何か返す") { t in
        // OCR は末尾を読み落とすことがある。ここで落ちるとアプリごと止まる
        let result = JSONFormatting.prettyPrint("{\"a\":1")
        t.expect(!result.isEmpty, "何かしら返る: \(result)")
        t.expect(result.contains("\"a\": 1"), "読めた範囲は整形される: \(result)")
    }

    t.run("文章に埋め込まれた JSON をキー名から切り出す") { t in
        let text = "エラー時のレスポンスは \"response\": {\"code\": 200} となる"
        let extracted = try t.require(JSONFormatting.extractEmbedded(text), "抽出できる")
        t.expect(extracted.before == "エラー時のレスポンスは", "前の文章: \(extracted.before)")
        t.expect(extracted.json.hasPrefix("\"response\""), "キー名から含める: \(extracted.json)")
        t.expect(extracted.after == "となる", "後ろの文章: \(extracted.after)")
    }

    t.run("普通の文章の括弧を JSON と誤検出しない") { t in
        // 開き括弧の直後が引用符・数字・括弧でなければ JSON ではないとみなす
        t.expect(JSONFormatting.extractEmbedded("これは（例）です") == nil, "全角括弧の中が文字")
        t.expect(JSONFormatting.extractEmbedded("配列 [あ, い] を見る") == nil, "角括弧の中が文字")
    }

    t.run("短すぎる塊は JSON とみなさない") { t in
        // 10 文字未満だと、単なる記号の並びを拾ってしまう
        t.expect(JSONFormatting.extractEmbedded("結果は {\"a\":1} だ") == nil, "9 文字の塊")
    }

    t.run("コロンの無い塊は JSON とみなさない") { t in
        t.expect(JSONFormatting.extractEmbedded("座標は [1234567890] です") == nil, "配列だけでコロンが無い")
    }

    t.run("埋め込み JSON が無ければ混在整形は nil") { t in
        // nil を返すことで、呼び出し側は元のテキストをそのまま使う
        t.expect(JSONFormatting.formatMixedContent("ただの文章です", format: .text) == nil, "文章だけ")
    }

    t.run("混在整形は前後の文章を空行で挟んで残す") { t in
        let text = "前の文章 \"response\": {\"code\": 200} 後ろの文章"
        let result = try t.require(JSONFormatting.formatMixedContent(text, format: .text), "整形できる")
        let blocks = result.components(separatedBy: "\n\n")
        t.expect(blocks.count == 3, "3 ブロックになる: \(blocks.count)")
        t.expect(blocks.first == "前の文章", "先頭は前の文章")
        t.expect(blocks.last == "後ろの文章", "末尾は後ろの文章")
    }

    t.run("片側しか文章が無ければ空のブロックを作らない") { t in
        // 空文字を連結すると、先頭や末尾に余分な空行が残る
        let leading = try t.require(
            JSONFormatting.formatMixedContent("前の文章 \"a\": {\"code\": 200}", format: .text),
            "前だけ"
        )
        t.expect(leading.components(separatedBy: "\n\n").count == 2, "2 ブロック: \(leading)")

        let trailing = try t.require(
            JSONFormatting.formatMixedContent("{\"code\": 200} 後ろの文章", format: .text),
            "後ろだけ"
        )
        t.expect(trailing.components(separatedBy: "\n\n").count == 2, "2 ブロック: \(trailing)")
    }

    t.run("混在整形も出力形式に従って JSON を包む") { t in
        let text = "前の文章 \"response\": {\"code\": 200} 後ろの文章"
        let result = try t.require(JSONFormatting.formatMixedContent(text, format: .markdown), "整形できる")
        t.expect(result.contains("```json"), "コードブロックで包む: \(result)")
    }
}
