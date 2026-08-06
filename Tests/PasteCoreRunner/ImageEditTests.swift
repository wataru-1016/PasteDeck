import CoreGraphics
import Foundation
import PasteCore

private func makeTempPersistence() throws -> Persistence {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("PasteDeckTests-\(UUID().uuidString)", isDirectory: true)
    return try Persistence(rootURL: root)
}

/// スクリーンショットのコピー相当。実データは使わず PNG のシグネチャだけ置く
private func imageContent(
    _ marker: UInt8 = 0x01,
    sizeLabel: String = "1200 × 800"
) -> CapturedContent {
    CapturedContent(
        flavors: [CaptureRules.pngType: Data([0x89, 0x50, 0x4E, 0x47, marker])],
        sourceAppName: "スクリーンショット",
        sourceAppBundleID: "com.apple.screencaptureui",
        imageSizeLabel: sizeLabel
    )
}

private func isClose(_ a: CGFloat, _ b: CGFloat, tolerance: CGFloat = 0.0001) -> Bool {
    abs(a - b) <= tolerance
}

private func isClose(_ a: CGPoint, _ b: CGPoint, tolerance: CGFloat = 0.0001) -> Bool {
    isClose(a.x, b.x, tolerance: tolerance) && isClose(a.y, b.y, tolerance: tolerance)
}

private func stroke(
    _ tool: ImageTool,
    _ points: [CGPoint],
    lineWidth: CGFloat = 6,
    text: String = ""
) -> ImageStroke {
    ImageStroke(tool: tool, points: points, lineWidth: lineWidth, text: text)
}

func runImageEditTests(_ t: TestHarness) {
    print("ImageEditRules:")

    t.run("編集できるのは画像だけ") { t in
        t.expect(ImageEditRules.canEdit(kind: .image, byteSize: 100), "画像は編集できる")
        t.expect(!ImageEditRules.canEdit(kind: .text, byteSize: 100), "テキストは対象外")
        t.expect(!ImageEditRules.canEdit(kind: .link, byteSize: 100), "リンクは対象外")
        t.expect(!ImageEditRules.canEdit(kind: .fileList, byteSize: 100), "ファイルは対象外")
    }

    t.run("巨大な画像は編集画面に載せない") { t in
        t.expect(
            ImageEditRules.canEdit(kind: .image, byteSize: ImageEditRules.maxEditableBytes),
            "上限ちょうどは編集できる"
        )
        t.expect(
            !ImageEditRules.canEdit(kind: .image, byteSize: ImageEditRules.maxEditableBytes + 1),
            "上限超過は編集できない"
        )
        t.expect(ImageEditRules.canEdit(pixelWidth: 5000, pixelHeight: 4000), "2000 万画素は展開できる")
        t.expect(!ImageEditRules.canEdit(pixelWidth: 20000, pixelHeight: 20000), "4 億画素は展開しない")
        t.expect(!ImageEditRules.canEdit(pixelWidth: 0, pixelHeight: 100), "幅 0 は編集できない")
    }

    t.run("何も操作していなければ保存しない") { t in
        t.expect(!ImageEditRules.shouldSave([]), "操作なしは保存しない")
        t.expect(
            ImageEditRules.shouldSave([.stroke(stroke(.pen, [CGPoint(x: 1, y: 1)]))]),
            "描き込みがあれば保存する"
        )
        t.expect(
            ImageEditRules.shouldSave([.crop(CGRect(x: 0, y: 0, width: 10, height: 10))]),
            "切り抜きだけでも保存する"
        )
    }

    t.run("編集後の flavor は PNG のみ") { t in
        let png = Data([0x89, 0x50])
        let flavors = ImageEditRules.flavors(forEditedPNG: png)
        t.expect(flavors.count == 1, "flavor は 1 つだけ")
        t.expect(flavors[CaptureRules.pngType] == png, "PNG が入っている")
        t.expect(flavors["public.tiff"] == nil, "TIFF は残さない")
    }

    print("ImageEditRules（表示と座標）:")

    t.run("画像はキャンバスに収まるよう縮小し、拡大はしない") { t in
        let fit = ImageEditRules.fit(
            sourceSize: CGSize(width: 2000, height: 1000),
            in: CGSize(width: 500, height: 500)
        )
        t.expect(isClose(fit.scale, 4), "長辺基準で 1/4 に縮む")
        t.expect(isClose(fit.displayRect.width, 500), "幅はキャンバスいっぱい")
        t.expect(isClose(fit.displayRect.height, 250), "高さは比率を保つ")
        t.expect(isClose(fit.displayRect.minY, 125), "縦は中央に置く")
        t.expect(isClose(fit.displayRect.minX, 0), "横は余白なし")

        let small = ImageEditRules.fit(
            sourceSize: CGSize(width: 100, height: 50),
            in: CGSize(width: 500, height: 500)
        )
        t.expect(isClose(small.scale, 1), "小さい画像でも等倍のまま")
        t.expect(isClose(small.displayRect.width, 100), "引き伸ばさない")
        t.expect(isClose(small.displayRect.minX, 200), "中央に置く")
    }

    t.run("大きさ 0 のキャンバスでも破綻しない") { t in
        let fit = ImageEditRules.fit(
            sourceSize: CGSize(width: 100, height: 100),
            in: CGSize(width: 0, height: 0)
        )
        t.expect(fit.scale == 1, "倍率は 1 に落とす")
        t.expect(fit.displayRect == .zero, "描画領域は空")
    }

    t.run("キャンバスの位置を画像のピクセルへ変換する") { t in
        // 1000×1000 の画像を 500×500 のキャンバスへ。縮小率は 2
        let size = CGSize(width: 1000, height: 1000)
        let fit = ImageEditRules.fit(sourceSize: size, in: CGSize(width: 500, height: 500))
        let full = CGRect(origin: .zero, size: size)

        let center = ImageEditRules.imagePoint(
            fromCanvas: CGPoint(x: 250, y: 250),
            fit: fit,
            cropRect: full
        )
        t.expect(isClose(center, CGPoint(x: 500, y: 500)), "中央は画像の中央になる")

        let origin = ImageEditRules.imagePoint(
            fromCanvas: CGPoint(x: 0, y: 0),
            fit: fit,
            cropRect: full
        )
        t.expect(isClose(origin, .zero), "左上は原点になる")
    }

    t.run("画像の外へドラッグしても範囲内に収める") { t in
        let size = CGSize(width: 1000, height: 1000)
        let fit = ImageEditRules.fit(sourceSize: size, in: CGSize(width: 500, height: 500))
        let full = CGRect(origin: .zero, size: size)

        let outside = ImageEditRules.imagePoint(
            fromCanvas: CGPoint(x: -100, y: 9999),
            fit: fit,
            cropRect: full
        )
        t.expect(isClose(outside, CGPoint(x: 0, y: 1000)), "画像の縁で止まる")
    }

    t.run("切り抜き中でも描き込みは元画像の座標で記録する") { t in
        // 1000×1000 の右下 500×500 を切り抜いて 500×500 のキャンバスへ出す（等倍）
        let crop = CGRect(x: 500, y: 500, width: 500, height: 500)
        let fit = ImageEditRules.fit(sourceSize: crop.size, in: CGSize(width: 500, height: 500))
        t.expect(isClose(fit.scale, 1), "切り抜き後は等倍で表示される")

        let point = ImageEditRules.imagePoint(
            fromCanvas: CGPoint(x: 10, y: 20),
            fit: fit,
            cropRect: crop
        )
        t.expect(
            isClose(point, CGPoint(x: 510, y: 520)),
            "切り抜きの左上ぶんだけずれた元画像の座標になる"
        )
    }

    t.run("画像座標とキャンバス座標を往復しても同じ位置に戻る") { t in
        let crop = CGRect(x: 120, y: 40, width: 800, height: 600)
        let fit = ImageEditRules.fit(sourceSize: crop.size, in: CGSize(width: 400, height: 400))
        let original = CGPoint(x: 300, y: 200)

        let canvas = ImageEditRules.canvasPoint(fromImage: original, fit: fit, cropRect: crop)
        let restored = ImageEditRules.imagePoint(fromCanvas: canvas, fit: fit, cropRect: crop)
        t.expect(isClose(restored, original, tolerance: 0.001), "変換して戻すと元の点になる")
    }

    t.run("2 点から作る矩形はドラッグの向きに依らない") { t in
        let downRight = ImageEditRules.rect(from: CGPoint(x: 10, y: 20), to: CGPoint(x: 40, y: 60))
        let upLeft = ImageEditRules.rect(from: CGPoint(x: 40, y: 60), to: CGPoint(x: 10, y: 20))
        t.expect(downRight == upLeft, "始点と終点を入れ替えても同じ矩形")
        t.expect(downRight == CGRect(x: 10, y: 20, width: 30, height: 40), "正の幅・高さになる")
    }

    print("ImageEditRules（操作の畳み込み）:")

    t.run("切り抜きがなければ画像全体が対象") { t in
        let size = CGSize(width: 800, height: 600)
        let rect = ImageEditRules.cropRect(in: [], imageSize: size)
        t.expect(rect == CGRect(origin: .zero, size: size), "画像全体を返す")

        let onlyStroke = ImageEditRules.cropRect(
            in: [.stroke(stroke(.pen, [CGPoint(x: 1, y: 1)]))],
            imageSize: size
        )
        t.expect(onlyStroke == CGRect(origin: .zero, size: size), "描き込みだけなら全体のまま")
    }

    t.run("切り抜きは最後のものが効き、取り消すと 1 つ前へ戻る") { t in
        let size = CGSize(width: 800, height: 600)
        let first = CGRect(x: 0, y: 0, width: 400, height: 300)
        let second = CGRect(x: 100, y: 100, width: 200, height: 150)
        let edits: [ImageEdit] = [
            .crop(first),
            .stroke(stroke(.arrow, [.zero, CGPoint(x: 50, y: 50)])),
            .crop(second),
        ]

        t.expect(ImageEditRules.cropRect(in: edits, imageSize: size) == second, "最後の切り抜きが効く")
        t.expect(
            ImageEditRules.cropRect(in: Array(edits.dropLast()), imageSize: size) == first,
            "取り消すと 1 つ前の切り抜きへ戻る"
        )
    }

    t.run("画像からはみ出した切り抜きは画像の内側へ収める") { t in
        let size = CGSize(width: 100, height: 100)
        let rect = ImageEditRules.cropRect(
            in: [.crop(CGRect(x: 50, y: 50, width: 200, height: 200))],
            imageSize: size
        )
        t.expect(rect == CGRect(x: 50, y: 50, width: 50, height: 50), "画像の外側は落とす")
    }

    t.run("描き込みだけを取り出す") { t in
        let pen = stroke(.pen, [CGPoint(x: 1, y: 1)])
        let edits: [ImageEdit] = [
            .stroke(pen),
            .crop(CGRect(x: 0, y: 0, width: 10, height: 10)),
            .stroke(stroke(.redaction, [.zero, CGPoint(x: 10, y: 10)])),
        ]
        let strokes = ImageEditRules.strokes(in: edits)
        t.expect(strokes.count == 2, "切り抜きは含まない")
        t.expect(strokes.first == pen, "順序を保つ")
    }

    t.run("小さすぎる切り抜きは受け付けない") { t in
        let bounds = CGRect(x: 0, y: 0, width: 500, height: 500)
        t.expect(
            ImageEditRules.isValidCrop(CGRect(x: 10, y: 10, width: 100, height: 100), in: bounds),
            "十分な大きさなら受け付ける"
        )
        t.expect(
            !ImageEditRules.isValidCrop(CGRect(x: 10, y: 10, width: 2, height: 100), in: bounds),
            "細すぎる範囲は誤操作とみなす"
        )
        t.expect(
            !ImageEditRules.isValidCrop(CGRect(x: 900, y: 900, width: 100, height: 100), in: bounds),
            "範囲外の切り抜きは受け付けない"
        )
    }

    t.run("ドラッグにならなかった描き込みは捨てる") { t in
        t.expect(
            ImageEditRules.isDrawable(stroke(.pen, [CGPoint(x: 5, y: 5)])),
            "ペンは点を打つだけでも残す"
        )
        t.expect(!ImageEditRules.isDrawable(stroke(.pen, [])), "点が無ければ残さない")
        t.expect(
            !ImageEditRules.isDrawable(stroke(.redaction, [.zero, CGPoint(x: 1, y: 1)])),
            "極小の黒塗りは誤クリックとみなす"
        )
        t.expect(
            ImageEditRules.isDrawable(stroke(.redaction, [.zero, CGPoint(x: 40, y: 30)])),
            "十分な大きさの黒塗りは残す"
        )
        t.expect(
            !ImageEditRules.isDrawable(stroke(.mosaic, [.zero, CGPoint(x: 1, y: 1)])),
            "極小のモザイクは誤クリックとみなす"
        )
        t.expect(
            ImageEditRules.isDrawable(stroke(.mosaic, [.zero, CGPoint(x: 40, y: 30)])),
            "十分な大きさのモザイクは残す"
        )
        t.expect(
            !ImageEditRules.isDrawable(stroke(.arrow, [.zero, CGPoint(x: 1, y: 1)])),
            "極端に短い矢印は残さない"
        )
        // 潰れた四角・丸はただの線と見分けがつかない。囲んだつもりのない操作として捨てる
        t.expect(
            !ImageEditRules.isDrawable(stroke(.rectangle, [.zero, CGPoint(x: 1, y: 40)])),
            "幅の無い四角は残さない"
        )
        t.expect(
            ImageEditRules.isDrawable(stroke(.rectangle, [.zero, CGPoint(x: 40, y: 30)])),
            "十分な大きさの四角は残す"
        )
        t.expect(
            !ImageEditRules.isDrawable(stroke(.ellipse, [.zero, CGPoint(x: 40, y: 1)])),
            "高さの無い丸は残さない"
        )
        t.expect(
            ImageEditRules.isDrawable(stroke(.ellipse, [.zero, CGPoint(x: 40, y: 30)])),
            "十分な大きさの丸は残す"
        )
        t.expect(
            !ImageEditRules.isDrawable(stroke(.crop, [.zero, CGPoint(x: 40, y: 40)])),
            "切り抜きは描き込みではない"
        )
    }

    t.run("中身のない文字は書き込まない") { t in
        let anchor = [CGPoint(x: 10, y: 10)]
        t.expect(ImageEditRules.isDrawable(stroke(.text, anchor, text: "ここ")), "文字があれば残す")
        t.expect(!ImageEditRules.isDrawable(stroke(.text, anchor, text: "")), "空文字は残さない")
        t.expect(!ImageEditRules.isDrawable(stroke(.text, anchor, text: "　 \n")), "空白だけも残さない")
        t.expect(!ImageEditRules.isDrawable(stroke(.text, [], text: "ここ")), "置く位置が無ければ残さない")
    }

    t.run("線幅は画像の大きさに合わせて決まる") { t in
        let small = ImageEditRules.lineWidth(forImageSize: CGSize(width: 100, height: 80))
        let medium = ImageEditRules.lineWidth(forImageSize: CGSize(width: 1600, height: 1000))
        let huge = ImageEditRules.lineWidth(forImageSize: CGSize(width: 8000, height: 8000))

        t.expect(small >= 2, "小さい画像でも見える太さを保つ")
        t.expect(medium > small, "大きい画像ほど太くなる")
        t.expect(huge <= 20, "太くなりすぎない")
    }

    print("ImageEditRules（色・太さ・文字・モザイク）:")

    t.run("隠す道具は色を選ばせず黒で固定する") { t in
        let blue = StrokeColor(red: 0, green: 0, blue: 1)

        t.expect(ImageTool.pen.usesStyle, "ペンは色と太さを選べる")
        t.expect(ImageTool.arrow.usesStyle, "矢印は色と太さを選べる")
        t.expect(ImageTool.rectangle.usesStyle, "四角は色と太さを選べる")
        t.expect(ImageTool.ellipse.usesStyle, "丸は色と太さを選べる")
        t.expect(ImageTool.text.usesStyle, "文字は色と大きさを選べる")
        t.expect(!ImageTool.redaction.usesStyle, "黒塗りは選ばせない")
        t.expect(!ImageTool.mosaic.usesStyle, "モザイクは選ばせない")
        t.expect(!ImageTool.crop.usesStyle, "トリミングに色は無い")

        t.expect(ImageTool.pen.color(selected: blue) == blue, "ペンは選んだ色で描く")
        t.expect(
            ImageTool.redaction.color(selected: blue) == .black,
            "黒塗りは何を選んでいても不透明な黒で塗る"
        )
        t.expect(StrokeColor.black.alpha == 1, "隠す色は透けない")
    }

    t.run("描き込みの色は道具が決める") { t in
        let blue = StrokeColor(red: 0, green: 0, blue: 1)
        let points = [CGPoint.zero, CGPoint(x: 40, y: 30)]

        // 呼び出し側の渡し忘れ・渡し間違いで隠す色が変わってはいけない
        t.expect(
            ImageStroke(tool: .redaction, points: points, lineWidth: 6, color: blue).color == .black,
            "黒塗りは渡した色を無視して黒になる"
        )
        t.expect(
            ImageStroke(tool: .mosaic, points: points, lineWidth: 6, color: blue).color == .black,
            "モザイクも色を持ち込ませない"
        )
        t.expect(
            ImageStroke(tool: .pen, points: points, lineWidth: 6, color: blue).color == blue,
            "ペンは渡した色をそのまま使う"
        )
        t.expect(
            ImageStroke(tool: .pen, points: points, lineWidth: 6).color == .marker,
            "色を渡さなければ既定の赤になる"
        )
    }

    t.run("選べる色はすべて名前が付いていて重複しない") { t in
        let choices = StrokeColor.choices
        t.expect(choices.count >= 4, "使い分けられるだけの数がある")
        t.expect(choices.contains { $0.color == .marker }, "既定の赤が含まれる")
        t.expect(
            Set(choices.map(\.name)).count == choices.count,
            "名前が重複しない（ForEach の id に使う）"
        )
        t.expect(choices.allSatisfy { $0.color.alpha == 1 }, "半透明の色は混ぜない")
    }

    t.run("太さの選択で線幅が変わる") { t in
        let size = CGSize(width: 1600, height: 1000)
        let thin = ImageEditRules.lineWidth(forImageSize: size, weight: .thin)
        let regular = ImageEditRules.lineWidth(forImageSize: size, weight: .regular)
        let bold = ImageEditRules.lineWidth(forImageSize: size, weight: .bold)

        t.expect(thin < regular && regular < bold, "細 < 中 < 太 の順になる")
        t.expect(
            isClose(regular, ImageEditRules.lineWidth(forImageSize: size)),
            "既定は中と同じ"
        )

        // 上限に張り付く大きさでも、選んだ太さの差は残す
        let huge = CGSize(width: 8000, height: 8000)
        t.expect(
            ImageEditRules.lineWidth(forImageSize: huge, weight: .bold)
                > ImageEditRules.lineWidth(forImageSize: huge, weight: .regular),
            "大きい画像でも太さの違いが潰れない"
        )
    }

    t.run("文字の大きさは線幅から決まる") { t in
        let size = CGSize(width: 1600, height: 1000)
        let regular = ImageEditRules.lineWidth(forImageSize: size, weight: .regular)
        let bold = ImageEditRules.lineWidth(forImageSize: size, weight: .bold)

        t.expect(
            ImageEditRules.fontSize(forLineWidth: regular) > regular,
            "線幅そのままでは小さすぎるので拡大する"
        )
        t.expect(
            ImageEditRules.fontSize(forLineWidth: bold)
                > ImageEditRules.fontSize(forLineWidth: regular),
            "太さを上げると文字も大きくなる"
        )
    }

    t.run("文字の大きさはピクセルで指定できる") { t in
        let point = [CGPoint(x: 10, y: 10)]
        let specified = ImageStroke(
            tool: .text, points: point, lineWidth: 6, text: "ここ", fontSize: 37
        )
        t.expect(isClose(specified.fontSize, 37), "指定した値をそのまま使う")

        let omitted = ImageStroke(tool: .text, points: point, lineWidth: 6, text: "ここ")
        t.expect(
            isClose(omitted.fontSize, ImageEditRules.fontSize(forLineWidth: 6)),
            "指定しなければ従来どおり線幅から決まる"
        )
    }

    t.run("指定した文字の大きさは画像に収まる範囲へ丸める") { t in
        let size = CGSize(width: 1600, height: 1000)
        let upper = ImageEditRules.maxFontSize(forImageSize: size)

        t.expect(
            isClose(ImageEditRules.clampedFontSize(24.4, forImageSize: size), 24),
            "ピクセル単位なので整数に丸める"
        )
        t.expect(
            isClose(
                ImageEditRules.clampedFontSize(1, forImageSize: size),
                ImageEditRules.minFontSize
            ),
            "小さすぎる指定は下限まで戻す"
        )
        t.expect(
            isClose(ImageEditRules.clampedFontSize(99_999, forImageSize: size), upper.rounded()),
            "画像からはみ出す大きさは上限で止める"
        )
        t.expect(upper < min(size.width, size.height), "上限でも画像の短辺には収まる")
        t.expect(
            ImageEditRules.clampedFontSize(.nan, forImageSize: size) >= ImageEditRules.minFontSize,
            "数値にならない入力でも壊れた値を返さない"
        )

        // 極端に小さい画像でも、下限を割り込む範囲を作らない
        let tiny = CGSize(width: 8, height: 6)
        t.expect(
            ImageEditRules.maxFontSize(forImageSize: tiny) >= ImageEditRules.minFontSize,
            "上限が下限を下回らない"
        )
    }

    t.run("既定の文字の大きさは画像の大きさから決まる") { t in
        let smallImage = CGSize(width: 400, height: 300)
        let largeImage = CGSize(width: 3840, height: 2160)
        let small = ImageEditRules.defaultFontSize(forImageSize: smallImage)
        let large = ImageEditRules.defaultFontSize(forImageSize: largeImage)

        t.expect(large > small, "大きい画像ほど既定も大きい")
        t.expect(
            isClose(small, small.rounded()) && isClose(large, large.rounded()),
            "既定値も整数ピクセルで始まる"
        )
        t.expect(
            isClose(large, ImageEditRules.clampedFontSize(large, forImageSize: largeImage)),
            "既定値は指定できる範囲に入っている"
        )
    }

    t.run("モザイクのマス目は画像の大きさに合わせて決まる") { t in
        let small = ImageEditRules.mosaicBlockSize(forImageSize: CGSize(width: 120, height: 90))
        let medium = ImageEditRules.mosaicBlockSize(forImageSize: CGSize(width: 2880, height: 1800))
        let huge = ImageEditRules.mosaicBlockSize(forImageSize: CGSize(width: 8000, height: 8000))

        t.expect(small >= 8, "小さい画像でも読めない粗さを確保する")
        t.expect(medium > small, "大きい画像ほどマスも大きくなる")
        t.expect(huge <= 40, "粗くなりすぎない")
        t.expect(
            medium > ImageEditRules.lineWidth(forImageSize: CGSize(width: 2880, height: 1800)),
            "線幅より粗い。細かいと元の文字が読み取れてしまう"
        )
    }

    t.run("書き込む文字は 1 行に整える") { t in
        t.expect(ImageEditRules.sanitizedText("  ここ  ") == "ここ", "前後の空白を落とす")
        t.expect(
            ImageEditRules.sanitizedText("上\n下") == "上 下",
            "改行は空白にする（行送りの計算を二重にしないため）"
        )
        t.expect(ImageEditRules.sanitizedText("\n\n") == "", "空白だけなら空になる")

        let long = String(repeating: "あ", count: ImageEditRules.maxTextLength + 50)
        t.expect(
            ImageEditRules.sanitizedText(long).count == ImageEditRules.maxTextLength,
            "上限を超えた分は切り捨てる"
        )
    }

    t.run("道具の数は数字キーの割り当てと釣り合っている") { t in
        // 増やしたときは PanelController.tool(forKeyCode:) のキーコードも足すこと
        t.expect(ImageTool.allCases.count == 8, "道具は 8 つ（1〜8 のキーに対応）")
        t.expect(ImageTool.allCases.first == .redaction, "既定の道具が先頭にある")
    }

    t.run("四角と丸はドラッグの向きに依らず同じ範囲になる") { t in
        // 右下へ引いても左上へ引いても囲まれる範囲は同じでなければならない。
        // 向きで結果が変わると、引き直すたびに枠の位置が動いて狙った場所を囲めない
        let expected = CGRect(x: 20, y: 30, width: 100, height: 60)
        let forward = stroke(.rectangle, [CGPoint(x: 20, y: 30), CGPoint(x: 120, y: 90)])
        let backward = stroke(.ellipse, [CGPoint(x: 120, y: 90), CGPoint(x: 20, y: 30)])

        t.expect(forward.rect == expected, "右下へ引いた四角")
        t.expect(backward.rect == expected, "左上へ引いた丸")

        // 途中の通過点は形に関わらない。拾ってしまうとドラッグの経路で枠が歪む
        t.expect(!ImageTool.rectangle.usesAllPoints, "四角は始点と終点だけで決まる")
        t.expect(!ImageTool.ellipse.usesAllPoints, "丸は始点と終点だけで決まる")
    }

    t.run("矢印の頭は先端から手前に向かって作られる") { t in
        let from = CGPoint(x: 0, y: 0)
        let to = CGPoint(x: 100, y: 0)
        let geometry = try t.require(
            ImageEditRules.arrowGeometry(from: from, to: to, lineWidth: 4),
            "矢印の形が求まる"
        )

        t.expect(geometry.tip == to, "先端は終点そのもの")
        t.expect(geometry.shaftEnd.x < to.x, "軸は先端の手前で終わる")
        t.expect(isClose(geometry.shaftEnd.y, 0), "まっすぐな矢印は軸もまっすぐ")
        t.expect(
            isClose(geometry.left.x, geometry.right.x) && geometry.left.y != geometry.right.y,
            "頭は進行方向に直交して広がる"
        )
        t.expect(isClose(geometry.left.y, -geometry.right.y), "頭は軸を挟んで左右対称")
    }

    t.run("短すぎる矢印は形を作らない") { t in
        let geometry = ImageEditRules.arrowGeometry(
            from: .zero,
            to: CGPoint(x: 1, y: 0),
            lineWidth: 4
        )
        t.expect(geometry == nil, "誤クリック相当は描かない")
    }

    t.run("矢印の頭は軸より長くならない") { t in
        // 線幅 20 なら頭は本来 90 だが、全長 30 の矢印では 30 で頭打ちになる
        let geometry = try t.require(
            ImageEditRules.arrowGeometry(from: .zero, to: CGPoint(x: 30, y: 0), lineWidth: 20),
            "矢印の形が求まる"
        )
        t.expect(geometry.shaftEnd.x >= 0, "軸の終わりが始点より手前へ行かない")
    }

    print("HistoryStore.replaceImage:")

    t.run("編集すると派生値がすべて引き直される") { t in
        let store = HistoryStore(persistence: try makeTempPersistence())
        store.ingest(imageContent())
        let original = try t.require(store.items.first, "取り込まれる")

        let edited = Data(repeating: 0x42, count: 128)
        store.replaceImage(edited, pixelWidth: 600, pixelHeight: 400, for: original.id)
        let result = try t.require(store.items.first, "アイテムが残る")

        t.expect(store.items.count == 1, "件数は増えない")
        t.expect(result.id == original.id, "同じアイテムを書き換える")
        t.expect(result.kind == .image, "種別は画像のまま")
        t.expect(result.preview == "画像 600 × 400", "切り抜き後の大きさが preview に出る")
        t.expect(result.byteSize == 128, "バイト数が編集後のものになる")
        t.expect(result.contentHash != original.contentHash, "ハッシュが引き直される")
        t.expect(result.charCount == nil, "文字数は持たない")
        t.expect(result.sourceAppName == "スクリーンショット", "コピー元アプリは保持する")
    }

    t.run("新規保存は元のアイテムを残したまま履歴を増やす") { t in
        // 新規保存は取り込みと同じ経路（ingest）に乗せている。
        // 元の画像が消えないこと・別 ID になることがこの保存の存在意義
        let store = HistoryStore(persistence: try makeTempPersistence())
        store.ingest(imageContent())
        let original = try t.require(store.items.first, "取り込まれる")

        let edited = Data(repeating: 0x55, count: 96)
        store.ingest(CapturedContent(
            flavors: ImageEditRules.flavors(forEditedPNG: edited),
            sourceAppName: original.sourceAppName,
            sourceAppBundleID: original.sourceAppBundleID,
            imageSizeLabel: ImageEditRules.sizeLabel(pixelWidth: 600, pixelHeight: 400)
        ))

        t.expect(store.items.count == 2, "件数が 1 つ増える")
        let added = try t.require(store.items.first, "先頭に入る")
        t.expect(added.id != original.id, "元とは別のアイテムになる")
        t.expect(added.preview == "画像 600 × 400", "編集後の大きさが preview に出る")
        t.expect(added.sourceAppName == original.sourceAppName, "コピー元アプリを引き継ぐ")
        t.expect(!added.isPinned, "ピン留めは引き継がない")

        let kept = try t.require(store.items.last, "元のアイテムが残る")
        t.expect(kept.id == original.id, "元の ID はそのまま")
        t.expect(
            store.flavors(for: original.id)?[CaptureRules.pngType]
                == imageContent().flavors[CaptureRules.pngType],
            "元の画像データは書き換わらない"
        )
        t.expect(store.flavors(for: added.id)?[CaptureRules.pngType] == edited, "編集後の画像が残る")
    }

    t.run("編集すると画像データが差し替わり PNG だけが残る") { t in
        let store = HistoryStore(persistence: try makeTempPersistence())
        store.ingest(CapturedContent(
            flavors: [
                CaptureRules.pngType: Data([0x89, 0x50]),
                "public.tiff": Data([0x4D, 0x4D]),
            ],
            imageSizeLabel: "10 × 10"
        ))
        let id = try t.require(store.items.first?.id, "取り込まれる")

        let edited = Data(repeating: 0x77, count: 64)
        store.replaceImage(edited, pixelWidth: 10, pixelHeight: 10, for: id)
        let flavors = try t.require(store.flavors(for: id), "flavor が読める")

        t.expect(flavors.count == 1, "PNG のみになる")
        t.expect(flavors[CaptureRules.pngType] == edited, "編集後の画像が保存される")
        t.expect(flavors["public.tiff"] == nil, "古い TIFF は破棄される")
    }

    t.run("ピン留め・並び順・コピー時刻は編集後も変わらない") { t in
        let store = HistoryStore(persistence: try makeTempPersistence())
        store.ingest(imageContent(0x01))
        store.ingest(imageContent(0x02))
        let target = store.items[1]
        store.togglePin(target.id)

        store.replaceImage(
            Data(repeating: 0x33, count: 32),
            pixelWidth: 5,
            pixelHeight: 5,
            for: target.id
        )

        t.expect(store.items[1].id == target.id, "並び順は変わらない")
        t.expect(store.items[1].isPinned, "ピン状態を保持する")
        t.expect(store.items[1].createdAt == target.createdAt, "コピー時刻は変えない")
        t.expect(store.items[1].preview == "画像 5 × 5", "内容は更新される")
    }

    t.run("テキストアイテムは画像編集で変化しない") { t in
        let store = HistoryStore(persistence: try makeTempPersistence())
        store.ingest(CapturedContent(
            flavors: [CaptureRules.plainTextType: Data("もとのテキスト".utf8)],
            sourceAppName: "TestApp"
        ))
        let original = try t.require(store.items.first, "取り込まれる")

        store.replaceImage(
            Data(repeating: 0x11, count: 16),
            pixelWidth: 10,
            pixelHeight: 10,
            for: original.id
        )

        t.expect(store.items[0] == original, "アイテムは変化しない")
        t.expect(
            store.flavors(for: original.id)?[CaptureRules.plainTextType] != nil,
            "本文が残る"
        )
    }

    t.run("空のデータでは履歴を書き換えない") { t in
        let store = HistoryStore(persistence: try makeTempPersistence())
        store.ingest(imageContent())
        let original = try t.require(store.items.first, "取り込まれる")

        store.replaceImage(Data(), pixelWidth: 10, pixelHeight: 10, for: original.id)

        t.expect(store.items[0] == original, "書き出しに失敗した内容は保存しない")
    }

    t.run("存在しない ID の編集は何もしない") { t in
        let store = HistoryStore(persistence: try makeTempPersistence())
        store.ingest(imageContent())
        store.replaceImage(
            Data(repeating: 0x55, count: 8),
            pixelWidth: 1,
            pixelHeight: 1,
            for: UUID()
        )
        t.expect(store.items.count == 1, "件数は変わらない")
        t.expect(store.items[0].preview == "画像 1200 × 800", "内容も変わらない")
    }
}
