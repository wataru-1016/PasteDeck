import Foundation
import PasteCore

func runOCRLineJoiningTests(_ t: TestHarness) {
    print("OCRLineJoining:")

    t.run("日本語の行はスペースを入れずに連結する") { t in
        // 日本語に半角スペースが混ざると、そのまま貼ったときに不自然な文章になる
        t.expect(LineJoining.join(["これは", "日本語"]) == "これは日本語", "無スペース")
    }

    t.run("英語の行は半角スペースで連結する") { t in
        t.expect(LineJoining.join(["This is", "English"]) == "This is English", "スペース区切り")
    }

    t.run("英語の行末ハイフンは単語の分割とみなして結合する") { t in
        // 紙面の折り返しで割れた単語を、ハイフンごと繋ぎ直す
        t.expect(LineJoining.join(["infor-", "mation"]) == "information", "ハイフンが消える")
    }

    t.run("日英が混ざる境界はスペースを入れない") { t in
        // 片方でも CJK なら無スペース。日本語の直後に半角スペースが入るのを防ぐ
        t.expect(LineJoining.join(["日本語", "English"]) == "日本語English", "日 → 英")
        t.expect(LineJoining.join(["English", "日本語"]) == "English日本語", "英 → 日")
    }

    t.run("段落の区切りに空行を入れる") { t in
        t.expect(LineJoining.join(["a", "b"], paragraphBreaks: [1]) == "a\n\nb", "1 の直前で区切る")
    }

    t.run("先頭への段落区切りは効かない") { t in
        // 0 の直前は文章の先頭。空行を入れると、貼り付けたテキストが空行から始まる
        t.expect(LineJoining.join(["a", "b"], paragraphBreaks: [0]) == "a b", "空行が付かない")
    }

    t.run("空行は結果に残さない") { t in
        // OCR は行間の余白を空の観測として返すことがある。
        // 空行を境界として扱うと、そこで無用な区切りやスペースが増える
        t.expect(LineJoining.join(["a", "", "b"]) == "a b", "空文字を捨てる")
        t.expect(LineJoining.join(["あ", "   ", "い"]) == "あい", "空白だけの行も捨てる")
    }

    t.run("捨てた空行の直後にある段落区切りは効いたままにする") { t in
        // 空行を捨てても行番号はずれない。ここで区切りが消えると、
        // 余白のある紙面ほど段落が失われる
        t.expect(
            LineJoining.join(["a", "", "b"], paragraphBreaks: [2]) == "a\n\nb",
            "index 2 の区切りが生きている"
        )
    }

    t.run("すべて空なら空文字を返す") { t in
        t.expect(LineJoining.join(["", "  "]).isEmpty, "空文字")
        t.expect(LineJoining.join([]).isEmpty, "そもそも行が無い")
    }

    t.run("CJK の判定は全角圏の文字を拾う") { t in
        t.expect(LineJoining.isCJK("。"), "句読点")
        t.expect(LineJoining.isCJK("あ"), "ひらがな")
        t.expect(LineJoining.isCJK("ア"), "カタカナ")
        t.expect(LineJoining.isCJK("漢"), "漢字")
        t.expect(LineJoining.isCJK("Ａ"), "全角英字")
    }

    t.run("CJK の判定は半角英数を拾わない") { t in
        // ここで true になると、英文がスペースなしで繋がって読めなくなる
        t.expect(!LineJoining.isCJK("A"), "半角英字")
        t.expect(!LineJoining.isCJK("1"), "半角数字")
        t.expect(!LineJoining.isCJK(" "), "半角スペース")
    }
}
