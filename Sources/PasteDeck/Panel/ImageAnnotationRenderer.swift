import AppKit
import CoreText
import PasteCore

/// 描き込みとトリミングを元画像へ適用して PNG を作る。
///
/// 形を決める計算は `ImageEditRules` に置き、キャンバスのプレビュー
/// （`ImageEditCanvas`）と同じ関数を使う。描画 API が別（`CGContext` と
/// `GraphicsContext`）なので描く手順は二重になるが、幾何が共通なら結果はずれない
enum ImageAnnotationRenderer {
    struct Output {
        let png: Data
        let pixelWidth: Int
        let pixelHeight: Int
    }

    static func render(source: ImageEditSource, edits: [ImageEdit]) -> Output? {
        guard let drawn = draw(ImageEditRules.strokes(in: edits), on: source.image) else {
            return nil
        }
        let cropRect = ImageEditRules.cropRect(in: edits, imageSize: source.size)
        let cropped = crop(drawn, to: cropRect)
        guard let png = pngData(from: cropped, logicalScale: source.logicalScale) else {
            return nil
        }
        return Output(png: png, pixelWidth: cropped.width, pixelHeight: cropped.height)
    }

    // MARK: - 描画

    private static func draw(_ strokes: [ImageStroke], on image: CGImage) -> CGImage? {
        guard !strokes.isEmpty else { return image }

        let size = CGSize(width: image.width, height: image.height)
        guard let context = ImageBitmap.context(width: image.width, height: image.height) else {
            return nil
        }
        context.draw(image, in: CGRect(origin: .zero, size: size))

        // モザイクは元画像から一度だけ作る。範囲ごとに作り直すとマス目の割り位置がずれ、
        // 塗り重ねたところに継ぎ目が出る
        let mosaic = strokes.contains { $0.tool == .mosaic }
            ? ImageBitmap.pixelated(image, block: ImageEditRules.mosaicBlockSize(forImageSize: size))
            : nil

        // ここから先は画像座標（左上原点）で描く。CGContext の既定は左下原点なので上下を反転する。
        // 元画像を先に描いてから反転するのは、反転後に描くと画像自体が裏返るため
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        for stroke in strokes {
            apply(stroke, in: context, mosaic: mosaic, imageSize: size)
        }
        return context.makeImage()
    }

    private static func apply(
        _ stroke: ImageStroke,
        in context: CGContext,
        mosaic: CGImage?,
        imageSize: CGSize
    ) {
        let color = stroke.color.cgColor
        context.setStrokeColor(color)
        context.setFillColor(color)
        context.setLineWidth(stroke.lineWidth)

        switch stroke.tool {
        case .pen:
            drawPen(stroke, in: context)

        case .redaction:
            guard let rect = stroke.rect else { return }
            context.fill(rect)

        case .mosaic:
            guard let rect = stroke.rect, let mosaic else { return }
            drawMosaic(mosaic, in: rect, context: context, imageSize: imageSize)

        // 四角と丸は枠だけを描く。中を塗ると下が見えなくなり、隠す道具と区別がつかない
        case .rectangle:
            guard let rect = stroke.rect else { return }
            context.stroke(rect)

        case .ellipse:
            guard let rect = stroke.rect else { return }
            context.strokeEllipse(in: rect)

        case .arrow:
            guard let endpoints = stroke.endpoints,
                  let geometry = ImageEditRules.arrowGeometry(
                      from: endpoints.from,
                      to: endpoints.to,
                      lineWidth: stroke.lineWidth
                  )
            else { return }
            context.move(to: endpoints.from)
            context.addLine(to: geometry.shaftEnd)
            context.strokePath()
            context.move(to: geometry.tip)
            context.addLine(to: geometry.left)
            context.addLine(to: geometry.right)
            context.closePath()
            context.fillPath()

        case .text:
            guard let anchor = stroke.points.first else { return }
            drawText(stroke, at: anchor, in: context)

        case .crop:
            // 切り抜きは描き込みではない（`ImageEditRules.strokes(in:)` が除いている）
            break
        }
    }

    private static func drawPen(_ stroke: ImageStroke, in context: CGContext) {
        guard let first = stroke.points.first else { return }
        guard stroke.points.count > 1 else {
            // 点を打っただけでは線にならないので、線幅と同じ直径の丸を置く
            let radius = stroke.lineWidth / 2
            context.fillEllipse(in: CGRect(
                x: first.x - radius,
                y: first.y - radius,
                width: stroke.lineWidth,
                height: stroke.lineWidth
            ))
            return
        }
        context.addLines(between: stroke.points)
        context.strokePath()
    }

    /// 粗くした画像を、指定の範囲だけ元の位置に重ねる。
    ///
    /// 切り抜きは反転したままの座標系で指定してよい（clip はその時点の座標系で確定する）が、
    /// 画像は反転を戻してから描く。戻さずに `draw` すると絵が上下逆に貼り付く
    private static func drawMosaic(
        _ mosaic: CGImage,
        in rect: CGRect,
        context: CGContext,
        imageSize: CGSize
    ) {
        context.saveGState()
        context.clip(to: rect)
        context.translateBy(x: 0, y: imageSize.height)
        context.scaleBy(x: 1, y: -1)
        context.draw(mosaic, in: CGRect(origin: .zero, size: imageSize))
        context.restoreGState()
    }

    /// 文字も反転したままでは裏返るため、置く位置で座標系を起こし直す。
    /// 起点は文字の左上で、ベースラインはそこから ascent ぶん下になる
    private static func drawText(_ stroke: ImageStroke, at anchor: CGPoint, in context: CGContext) {
        let text = ImageEditRules.sanitizedText(stroke.text)
        guard !text.isEmpty else { return }

        let attributed = NSAttributedString(
            string: text,
            attributes: ImageTextStyle.coreTextAttributes(
                size: stroke.fontSize,
                color: stroke.color
            )
        )
        let line = CTLineCreateWithAttributedString(attributed)
        var ascent: CGFloat = 0
        _ = CTLineGetTypographicBounds(line, &ascent, nil, nil)

        context.saveGState()
        context.translateBy(x: anchor.x, y: anchor.y + ascent)
        context.scaleBy(x: 1, y: -1)
        context.textPosition = .zero
        CTLineDraw(line, context)
        context.restoreGState()
    }

    // MARK: - 切り抜きと書き出し

    private static func crop(_ image: CGImage, to rect: CGRect) -> CGImage {
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let pixelRect = rect.integral.intersection(bounds)
        guard !pixelRect.isNull, pixelRect != bounds,
              pixelRect.width >= 1, pixelRect.height >= 1
        else { return image }
        return image.cropping(to: pixelRect) ?? image
    }

    /// `NSBitmapImageRep` の size をポイントへ戻して PNG 化する。
    /// 省くと解像度の情報が落ち、Retina のスクリーンショットが貼り付け先で 2 倍の大きさになる
    private static func pngData(from image: CGImage, logicalScale: CGFloat) -> Data? {
        let rep = NSBitmapImageRep(cgImage: image)
        let scale = logicalScale > 0 ? logicalScale : 1
        rep.size = NSSize(
            width: CGFloat(image.width) / scale,
            height: CGFloat(image.height) / scale
        )
        return rep.representation(using: .png, properties: [:])
    }
}
