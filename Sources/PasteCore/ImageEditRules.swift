import CoreGraphics
import Foundation

/// 画像編集（⌘E）のルール（純粋関数のみ・テスト対象）。
///
/// 座標系が 3 つあり、取り違えると「黒く塗ったつもりの場所がずれる」という
/// 隠し損ねに直結する。変換はすべてここへ集める。
/// - **画像座標** … 元画像のピクセル（左上原点）。描き込みの保持と保存に使う
/// - **切り抜き範囲** … 画像座標の矩形。いま画面に映している部分
/// - **キャンバス座標** … 表示ポイント。マウス操作が届く座標
public enum ImageEditRules {
    /// 編集画面に載せる画像の上限。手で直せる分量を超えた巨大画像は対象外にする
    public static let maxEditableBytes = 32 * 1024 * 1024
    /// 展開後のピクセル数の上限。1 ピクセル 4 バイトで約 200MB
    public static let maxEditablePixels = 50_000_000

    /// 誤クリックとみなさない最小の長さ（画像ピクセル）
    public static let minStrokeSpan: CGFloat = 4
    /// 切り抜きとして受け付ける最小の辺（画像ピクセル）
    public static let minCropSide: CGFloat = 16

    /// 線幅を画像の短辺から決めるときの比率と上下限。
    /// 固定値にすると、小さい画像では太すぎ、4K のスクリーンショットでは細すぎる
    private static let lineWidthRatio: CGFloat = 0.006
    private static let minLineWidth: CGFloat = 2
    private static let maxLineWidth: CGFloat = 20

    /// 矢印の頭の長さ（線幅に対する比）と、頭の広がり（頭の長さに対する比）
    private static let arrowHeadRatio: CGFloat = 4.5
    private static let arrowHeadSpreadRatio: CGFloat = 0.42

    /// 文字の大きさを線幅から決めるときの比率
    private static let fontSizeRatio: CGFloat = 3.5
    /// 書き込める文字数の上限。1 行の注釈に必要な長さは超えている
    public static let maxTextLength = 120

    /// 指定できる文字の大きさ（画像ピクセル）の下限と、上限を画像の短辺から決めるときの比率。
    /// 上限を画像に対する比で持つのは、画像からはみ出すほどの文字を指定できても
    /// 書き込んだ結果が読めず、指定できること自体が誤操作の入口になるため
    public static let minFontSize: CGFloat = 6
    private static let maxFontSizeRatio: CGFloat = 0.5

    /// モザイク 1 マスの大きさを画像の短辺から決めるときの比率と上下限。
    /// 粗さを選ばせないのは、細かいモザイクだと元の文字が読み取れてしまうため
    private static let mosaicBlockRatio: CGFloat = 0.016
    private static let minMosaicBlock: CGFloat = 8
    private static let maxMosaicBlock: CGFloat = 40

    // MARK: - 編集できるか

    /// 編集できるアイテムか。テキストとファイルは画像を持たない
    public static func canEdit(kind: ItemKind, byteSize: Int) -> Bool {
        guard kind == .image else { return false }
        return byteSize <= maxEditableBytes
    }

    /// 展開して編集できる大きさか。読み込んでピクセル数が分かってから判定する
    public static func canEdit(pixelWidth: Int, pixelHeight: Int) -> Bool {
        guard pixelWidth > 0, pixelHeight > 0 else { return false }
        return pixelWidth * pixelHeight <= maxEditablePixels
    }

    /// 編集結果を履歴に収められる大きさか。取り込み時と同じ上限で判定する
    public static func canStore(byteCount: Int) -> Bool {
        byteCount > 0 && byteCount <= CaptureRules.maxItemBytes
    }

    /// 保存すべき編集か。何も操作していなければ履歴を書き換えない
    public static func shouldSave(_ edits: [ImageEdit]) -> Bool {
        !edits.isEmpty
    }

    // MARK: - 描き込み

    /// 線幅。画像の短辺に対する比で決め、極端な太さにならないよう頭打ちにする。
    ///
    /// 選んだ太さは頭打ちのあとに掛ける。先に掛けてしまうと、大きい画像では
    /// 上限に張り付いて「太」と「中」の区別がつかなくなる
    public static func lineWidth(forImageSize size: CGSize, weight: StrokeWeight = .regular) -> CGFloat {
        let shortSide = min(size.width, size.height)
        let base = min(max(shortSide * lineWidthRatio, minLineWidth), maxLineWidth)
        return base * weight.multiplier
    }

    /// 書き込む文字の大きさ（画像ピクセル）。線幅と同じ倍率で大小が変わる
    public static func fontSize(forLineWidth lineWidth: CGFloat) -> CGFloat {
        lineWidth * fontSizeRatio
    }

    /// 画像を開いたときに最初に入れておく文字の大きさ（画像ピクセル）。
    /// 線幅と同じ決め方にしてあるので、4K でも小さな画像でも読める大きさから始まる
    public static func defaultFontSize(forImageSize size: CGSize) -> CGFloat {
        clampedFontSize(fontSize(forLineWidth: lineWidth(forImageSize: size)), forImageSize: size)
    }

    /// その画像で指定できる文字の大きさの上限（画像ピクセル）
    public static func maxFontSize(forImageSize size: CGSize) -> CGFloat {
        max(min(size.width, size.height) * maxFontSizeRatio, minFontSize)
    }

    /// 指定された大きさを、その画像で扱える範囲の整数ピクセルに収める。
    /// ピクセル単位で指定させる以上、半端な小数を持ち回っても意味がないため丸める
    public static func clampedFontSize(_ size: CGFloat, forImageSize imageSize: CGSize) -> CGFloat {
        guard size.isFinite else { return minFontSize }
        return min(max(size.rounded(), minFontSize), maxFontSize(forImageSize: imageSize).rounded())
    }

    /// モザイク 1 マスの大きさ（画像ピクセル）
    public static func mosaicBlockSize(forImageSize size: CGSize) -> CGFloat {
        let shortSide = min(size.width, size.height)
        return min(max(shortSide * mosaicBlockRatio, minMosaicBlock), maxMosaicBlock)
    }

    /// 書き込む文字を 1 行に整える。
    /// 改行を許すと行送りの計算がプレビューと保存で二重になり、ずれの原因になる
    public static func sanitizedText(_ text: String) -> String {
        let singleLine = text
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(singleLine.prefix(maxTextLength))
    }

    /// 履歴へ残す価値のある描き込みか。ドラッグにならなかったクリックを弾く
    public static func isDrawable(_ stroke: ImageStroke) -> Bool {
        switch stroke.tool {
        case .pen:
            // 点を打っただけでも印にはなるため、1 点でも受け付ける
            return !stroke.points.isEmpty
        case .redaction, .mosaic:
            guard let rect = stroke.rect else { return false }
            return rect.width >= minStrokeSpan && rect.height >= minStrokeSpan
        case .arrow:
            guard let endpoints = stroke.endpoints else { return false }
            return distance(endpoints.from, endpoints.to) >= minStrokeSpan
        case .text:
            // 文字は押した 1 点に置く。中身が空なら何も書き込まない
            return !stroke.points.isEmpty && !sanitizedText(stroke.text).isEmpty
        case .crop:
            // 切り抜きは描き込みではない（`ImageEdit.crop` として積む）
            return false
        }
    }

    /// 矢印の各頂点。キャンバスのプレビューと保存時の描画で同じ形にするため共有する
    public struct ArrowGeometry: Equatable, Sendable {
        /// 軸線の終わり（頭の付け根）
        public let shaftEnd: CGPoint
        /// 先端
        public let tip: CGPoint
        /// 頭の左右の角
        public let left: CGPoint
        public let right: CGPoint
    }

    public static func arrowGeometry(
        from: CGPoint,
        to: CGPoint,
        lineWidth: CGFloat
    ) -> ArrowGeometry? {
        let length = distance(from, to)
        guard length >= minStrokeSpan else { return nil }

        // 短い矢印で頭が軸より長くならないよう、頭の長さは全長で頭打ちにする
        let head = min(lineWidth * arrowHeadRatio, length)
        let unitX = (to.x - from.x) / length
        let unitY = (to.y - from.y) / length
        let shaftEnd = CGPoint(x: to.x - unitX * head, y: to.y - unitY * head)

        // 進行方向に直交する向きへ頭を広げる
        let spread = head * arrowHeadSpreadRatio
        let normalX = -unitY
        let normalY = unitX
        return ArrowGeometry(
            shaftEnd: shaftEnd,
            tip: to,
            left: CGPoint(x: shaftEnd.x + normalX * spread, y: shaftEnd.y + normalY * spread),
            right: CGPoint(x: shaftEnd.x - normalX * spread, y: shaftEnd.y - normalY * spread)
        )
    }

    // MARK: - 操作の畳み込み

    /// いま有効な切り抜き範囲（画像座標）。
    /// 切り抜きを重ねた場合は最後のものだけが効く。取り消すと 1 つ前の範囲へ戻る
    public static func cropRect(in edits: [ImageEdit], imageSize: CGSize) -> CGRect {
        let full = CGRect(origin: .zero, size: imageSize)
        for edit in edits.reversed() {
            guard case .crop(let rect) = edit else { continue }
            let clipped = rect.intersection(full)
            return clipped.isNull ? full : clipped
        }
        return full
    }

    /// 描き込みだけを取り出す
    public static func strokes(in edits: [ImageEdit]) -> [ImageStroke] {
        edits.compactMap { edit in
            guard case .stroke(let stroke) = edit else { return nil }
            return stroke
        }
    }

    /// 切り抜きとして受け付ける範囲か。誤クリックで画像が消し飛ぶのを防ぐ
    public static func isValidCrop(_ rect: CGRect, in bounds: CGRect) -> Bool {
        let clipped = rect.intersection(bounds)
        guard !clipped.isNull else { return false }
        return clipped.width >= minCropSide && clipped.height >= minCropSide
    }

    // MARK: - 座標変換

    /// キャンバスに画像を収める位置と倍率
    public struct CanvasFit: Equatable, Sendable {
        /// キャンバス内で画像が占める領域（キャンバス座標）
        public let displayRect: CGRect
        /// 画像ピクセル ÷ 表示ポイント。1 なら等倍、2 なら半分に縮んでいる
        public let scale: CGFloat

        public init(displayRect: CGRect, scale: CGFloat) {
            self.displayRect = displayRect
            self.scale = scale
        }
    }

    /// 切り抜き後の画像をキャンバス中央へ収める。
    /// 拡大はしない（scale の下限が 1）。粗い画像を引き伸ばしても編集の精度は上がらず、
    /// 実際のピクセルより細かく指せると錯覚させてしまう
    public static func fit(sourceSize: CGSize, in canvasSize: CGSize) -> CanvasFit {
        guard sourceSize.width > 0, sourceSize.height > 0,
              canvasSize.width > 0, canvasSize.height > 0
        else {
            return CanvasFit(displayRect: .zero, scale: 1)
        }

        let scale = max(
            1,
            max(sourceSize.width / canvasSize.width, sourceSize.height / canvasSize.height)
        )
        let size = CGSize(width: sourceSize.width / scale, height: sourceSize.height / scale)
        let origin = CGPoint(
            x: (canvasSize.width - size.width) / 2,
            y: (canvasSize.height - size.height) / 2
        )
        return CanvasFit(displayRect: CGRect(origin: origin, size: size), scale: scale)
    }

    /// キャンバス座標 → 画像座標。切り抜き中でも描き込みは元画像基準で記録する
    public static func imagePoint(
        fromCanvas point: CGPoint,
        fit: CanvasFit,
        cropRect: CGRect
    ) -> CGPoint {
        let converted = CGPoint(
            x: cropRect.minX + (point.x - fit.displayRect.minX) * fit.scale,
            y: cropRect.minY + (point.y - fit.displayRect.minY) * fit.scale
        )
        // 画像の外へドラッグしても、描き込みは見えている範囲に留める
        return clamp(converted, to: cropRect)
    }

    /// 画像座標 → キャンバス座標。記録済みの描き込みを画面へ戻すときに使う
    public static func canvasPoint(
        fromImage point: CGPoint,
        fit: CanvasFit,
        cropRect: CGRect
    ) -> CGPoint {
        CGPoint(
            x: fit.displayRect.minX + (point.x - cropRect.minX) / fit.scale,
            y: fit.displayRect.minY + (point.y - cropRect.minY) / fit.scale
        )
    }

    public static func clamp(_ point: CGPoint, to rect: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(point.x, rect.minX), rect.maxX),
            y: min(max(point.y, rect.minY), rect.maxY)
        )
    }

    /// 2 点から矩形を作る。ドラッグの向きに依らず正の幅・高さになる
    public static func rect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(
            x: min(a.x, b.x),
            y: min(a.y, b.y),
            width: abs(a.x - b.x),
            height: abs(a.y - b.y)
        )
    }

    // MARK: - 保存

    /// 編集後に残す flavor。
    ///
    /// 取り込み時に画像は PNG へ正規化している（`ClipboardMonitor`）ため、保存も PNG だけにする。
    /// 古い TIFF を持つアイテムでも、書き換えていない側を残してはならない。貼り付け先が
    /// そちらを選ぶと、黒く塗る前の画像がそのまま貼られてしまう
    public static func flavors(forEditedPNG png: Data) -> [String: Data] {
        [CaptureRules.pngType: png]
    }

    /// カードとフッターに出す "幅 × 高さ"。取り込み時のラベルと同じ形式にする
    public static func sizeLabel(pixelWidth: Int, pixelHeight: Int) -> String {
        "\(pixelWidth) × \(pixelHeight)"
    }

    // MARK: - 内部処理

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
    }
}
