import Foundation
import PasteCore

func runRichTextStyleTests(_ t: TestHarness) {
    print("RichTextStyle:")

    t.run("上限以下のフォントは縮小しない") { t in
        t.expect(RichTextStyle.fontScale(maxSourceSize: 0) == 1, "フォント情報なしなら等倍")
        t.expect(RichTextStyle.fontScale(maxSourceSize: 9) == 1, "小さいフォントは拡大しない")
        t.expect(
            RichTextStyle.fontScale(maxSourceSize: RichTextStyle.maxFontSize) == 1,
            "上限ちょうどは等倍"
        )
    }

    t.run("上限を超えるフォントは比率を保って縮小する") { t in
        let scale = RichTextStyle.fontScale(maxSourceSize: 30)
        t.expect(scale == RichTextStyle.maxFontSize / 30, "最大サイズが上限に収まる倍率")

        // Excel の 16pt 見出しセルを想定
        let excelScale = RichTextStyle.fontScale(maxSourceSize: 16)
        t.expect(
            RichTextStyle.scaledFontSize(16, scale: excelScale) == RichTextStyle.maxFontSize,
            "最大フォントは上限サイズになる"
        )
        t.expect(
            RichTextStyle.scaledFontSize(12, scale: excelScale) < RichTextStyle.maxFontSize,
            "同じ倍率で他のフォントも縮む＝大小関係が保たれる"
        )
    }

    t.run("縮小しても最小サイズは下回らない") { t in
        let scale = RichTextStyle.fontScale(maxSourceSize: 60)
        t.expect(
            RichTextStyle.scaledFontSize(6, scale: scale) == RichTextStyle.minFontSize,
            "極小フォントは読める下限で止まる"
        )
    }

    t.run("縮小が不要な場合でも判読できない小ささにはしない") { t in
        // 脚注などの極小フォントは、全体を縮小しない場合でも読める大きさまで持ち上げる
        let scale = RichTextStyle.fontScale(maxSourceSize: 12)
        t.expect(scale == 1, "全体が上限以下なら等倍")
        t.expect(
            RichTextStyle.scaledFontSize(6, scale: scale) == RichTextStyle.minFontSize,
            "等倍でも下限は適用する"
        )
    }

    t.run("彩度は無彩色で 0 になる") { t in
        t.expect(RichTextStyle.saturation(red: 1, green: 0, blue: 0) == 1, "純赤は彩度 1")
        t.expect(RichTextStyle.saturation(red: 0, green: 0, blue: 0) == 0, "黒は彩度 0")
        t.expect(RichTextStyle.saturation(red: 1, green: 1, blue: 1) == 0, "白は彩度 0")
        t.expect(RichTextStyle.saturation(red: 0.5, green: 0.5, blue: 0.5) == 0, "グレーは彩度 0")
    }

    t.run("無彩色の文字色は捨てて OS 既定に任せる") { t in
        // Excel の既定セル色は black。ダークモードのカードに黒文字を出すと読めなくなる
        t.expect(
            !RichTextStyle.isMeaningfulColor(red: 0, green: 0, blue: 0, alpha: 1),
            "黒は既定色として扱い保持しない"
        )
        t.expect(
            !RichTextStyle.isMeaningfulColor(red: 1, green: 1, blue: 1, alpha: 1),
            "白も保持しない"
        )
        t.expect(
            !RichTextStyle.isMeaningfulColor(red: 0.2, green: 0.21, blue: 0.2, alpha: 1),
            "ほぼ無彩色も保持しない"
        )
    }

    t.run("有彩色の文字色は保持する") { t in
        t.expect(
            RichTextStyle.isMeaningfulColor(red: 1, green: 0, blue: 0, alpha: 1),
            "Excel の赤文字は保持する"
        )
        t.expect(
            RichTextStyle.isMeaningfulColor(red: 0.1, green: 0.3, blue: 0.8, alpha: 1),
            "青系も保持する"
        )
    }

    t.run("透明な色は保持しない") { t in
        t.expect(
            !RichTextStyle.isMeaningfulColor(red: 1, green: 0, blue: 0, alpha: 0),
            "完全に透明なら意味を持たない"
        )
    }

    t.run("塗りつぶし背景の上では無彩色の文字色も保持する") { t in
        // Excel の「濃色セル ＋ 白の太字」見出し行。白を捨てると OS 既定色に戻り、
        // 残った濃色背景と重なってライトモードで判読できなくなる
        t.expect(
            RichTextStyle.keepsForegroundColor(
                red: 1, green: 1, blue: 1, alpha: 1, hasBackgroundColor: true
            ),
            "背景がある白文字は保持する"
        )
        t.expect(
            RichTextStyle.keepsForegroundColor(
                red: 0, green: 0, blue: 0, alpha: 1, hasBackgroundColor: true
            ),
            "背景がある黒文字も保持する"
        )
    }

    t.run("背景がなければ無彩色の文字色は既定色に任せる") { t in
        t.expect(
            !RichTextStyle.keepsForegroundColor(
                red: 1, green: 1, blue: 1, alpha: 1, hasBackgroundColor: false
            ),
            "背景なしの白は捨てる"
        )
        t.expect(
            !RichTextStyle.keepsForegroundColor(
                red: 0, green: 0, blue: 0, alpha: 1, hasBackgroundColor: false
            ),
            "背景なしの黒は捨てる"
        )
        t.expect(
            RichTextStyle.keepsForegroundColor(
                red: 1, green: 0, blue: 0, alpha: 1, hasBackgroundColor: false
            ),
            "背景がなくても有彩色は保持する"
        )
        t.expect(
            !RichTextStyle.keepsForegroundColor(
                red: 1, green: 1, blue: 1, alpha: 0, hasBackgroundColor: true
            ),
            "透明なら背景があっても保持しない"
        )
    }

    t.run("巨大な RTF はデコードせずプレーン表示にフォールバックする") { t in
        t.expect(RichTextStyle.canDecode(byteCount: 4096), "通常サイズはデコードする")
        t.expect(
            !RichTextStyle.canDecode(byteCount: RichTextStyle.maxDecodableBytes + 1),
            "上限超過はデコードしない"
        )
    }

    t.run("前後の空白を除いた範囲を返す") { t in
        let text = "  hello \n"
        let range = try t.require(RichTextStyle.trimmedRange(of: text), "範囲が得られる")
        t.expect(String(text[range]) == "hello", "前後の空白・改行が除かれる")

        t.expect(RichTextStyle.trimmedRange(of: " \n\t ") == nil, "空白のみなら nil")
        t.expect(RichTextStyle.trimmedRange(of: "") == nil, "空文字列なら nil")

        let intact = "a b"
        let intactRange = try t.require(RichTextStyle.trimmedRange(of: intact), "範囲が得られる")
        t.expect(String(intact[intactRange]) == "a b", "内部の空白は保持する")
    }
}
