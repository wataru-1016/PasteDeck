import CoreGraphics
import Foundation
import PasteCore

/// 正規化座標（左下原点）の 1 行分。midY と高さだけを指定して読みやすくする
private func line(_ text: String, midY: CGFloat, height: CGFloat = 0.05) -> OCRLayout.Line {
    OCRLayout.Line(text: text, box: CGRect(x: 0, y: midY - height / 2, width: 1, height: height))
}

func runOCRLayoutTests(_ t: TestHarness) {
    print("OCRLayout:")

    t.run("左下原点の観測を画面の上から順に並べ替える") { t in
        // Vision の正規化座標は左下が原点。midY の昇順に読むと文章が下から出てくる
        let layout = OCRLayout.arrange([
            line("下", midY: 0.2),
            line("上", midY: 0.8),
            line("中", midY: 0.5),
        ])
        t.expect(layout.lines == ["上", "中", "下"], "上から順: \(layout.lines)")
    }

    t.run("行間が大きく空いた箇所だけを段落の区切りにする") { t in
        // 高さ 0.05 の行が 0.06 間隔で 2 行続いたあと、大きく空けて 1 行
        let layout = OCRLayout.arrange([
            line("段落1の1行目", midY: 0.90),
            line("段落1の2行目", midY: 0.84),
            line("段落2の1行目", midY: 0.50),
        ])
        t.expect(layout.paragraphBreaks == [2], "3 行目の直前だけ区切る: \(layout.paragraphBreaks)")
    }

    t.run("閾値ちょうどでは区切らず、わずかに超えたら区切る") { t in
        // 判定は > であって >= ではない。境界の向きが変わると、
        // 同じ紙面から取った文章でも段落の数が実装の都合で増減する
        let height: CGFloat = 0.125  // 2 の冪なので閾値の計算に丸め誤差が乗らない
        let threshold = height * OCRLayout.paragraphGapRatio
        let upperMinY: CGFloat = 0.5

        func arrange(gap: CGFloat) -> OCRLayout.Layout {
            OCRLayout.arrange([
                OCRLayout.Line(text: "上", box: CGRect(x: 0, y: upperMinY, width: 1, height: height)),
                OCRLayout.Line(
                    text: "下",
                    box: CGRect(x: 0, y: upperMinY - gap - height, width: 1, height: height)
                ),
            ])
        }

        t.expect(arrange(gap: threshold).paragraphBreaks.isEmpty, "ちょうどは区切らない")
        t.expect(arrange(gap: threshold * 1.01).paragraphBreaks == [1], "わずかに超えたら区切る")
    }

    t.run("1 行だけなら区切りは無い") { t in
        let layout = OCRLayout.arrange([line("ひとつ", midY: 0.5)])
        t.expect(layout.lines == ["ひとつ"], "行はそのまま")
        t.expect(layout.paragraphBreaks.isEmpty, "区切りなし")
    }

    t.run("観測が無ければ行も区切りも空") { t in
        let layout = OCRLayout.arrange([])
        t.expect(layout.lines.isEmpty, "行が空")
        t.expect(layout.paragraphBreaks.isEmpty, "区切りが空")
    }

    t.run("文字の高さがばらついても平均で判定する") { t in
        // 見出しと本文が混ざる紙面では行の高さが揃わない。
        // 1 行の高さで判定すると、見出しの直後が必ず段落区切りになる
        let layout = OCRLayout.arrange([
            line("見出し", midY: 0.90, height: 0.10),
            line("本文1", midY: 0.80, height: 0.03),
            line("本文2", midY: 0.76, height: 0.03),
        ])
        t.expect(layout.lines == ["見出し", "本文1", "本文2"], "並びは保たれる")
        t.expect(layout.paragraphBreaks.isEmpty, "平均で見れば区切りは無い: \(layout.paragraphBreaks)")
    }

    t.run("高さがすべて 0 でも全行が区切りにならない") { t in
        // 平均高が 0 だと gap > 0 が全行で成立し、1 行ごとに空行が入る
        let layout = OCRLayout.arrange([
            OCRLayout.Line(text: "a", box: CGRect(x: 0, y: 0.9, width: 1, height: 0)),
            OCRLayout.Line(text: "b", box: CGRect(x: 0, y: 0.5, width: 1, height: 0)),
            OCRLayout.Line(text: "c", box: CGRect(x: 0, y: 0.1, width: 1, height: 0)),
        ])
        t.expect(layout.lines == ["a", "b", "c"], "並びは保たれる")
        t.expect(layout.paragraphBreaks.isEmpty, "区切りは作らない: \(layout.paragraphBreaks)")
    }

    t.run("行が重なっていても区切らない") { t in
        // 縦書きや装飾でボックスが重なると gap が負になる
        let layout = OCRLayout.arrange([
            line("上", midY: 0.52),
            line("下", midY: 0.50),
        ])
        t.expect(layout.paragraphBreaks.isEmpty, "負の gap では区切らない")
    }

    t.run("段落の閾値は平均の行の高さの 1.6 倍") { t in
        // 移植元の実コードが 1.6。統合元ドキュメントの 1.4 は誤記で、
        // ここを変えると読み取り結果の段落の数が変わる
        t.expect(OCRLayout.paragraphGapRatio == 1.6, "1.6")
    }
}
