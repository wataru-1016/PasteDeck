import AppKit
import ImageIO
import PasteCore
import SwiftUI

/// ⌘E の画像編集で使う素材。
///
/// 保存用のフル解像度と、画面へ出す縮小版を分けて持つ。キャンバスはドラッグ中に
/// 毎フレーム描き直されるため、4K のスクリーンショットをそのまま描くと追従しない
struct ImageEditSource {
    /// 保存時に描き込みを適用する元画像
    let image: CGImage
    /// キャンバスへ出す縮小版
    let display: NSImage
    /// モザイク用に、縮小版の全体をあらかじめ粗くしたもの。
    /// 範囲ごとに作らず 1 枚で持つことで、塗り重ねてもマス目の位置がそろう
    let mosaicDisplay: NSImage
    /// ピクセル ÷ ポイント。Retina のスクリーンショットは 2。
    /// 保存時にこの比を戻さないと、貼り付け先で 2 倍の大きさになる
    let logicalScale: CGFloat

    var size: CGSize { CGSize(width: image.width, height: image.height) }
}

/// 履歴に保存された画像を編集できる形へ読み込む
enum ImageEditLoader {
    /// キャンバスへ出す縮小版の最大辺。Retina のパネル幅に対して等倍以上を確保する
    private static let displayMaxPixelSize = 2048

    static func load(flavors: [String: Data]) -> ImageEditSource? {
        guard let data = flavors[CaptureRules.pngType] ?? flavors["public.tiff"] else { return nil }

        // ピクセルは ImageIO から取る。NSImage 経由だと解像度を加味した論理サイズになり、
        // Retina のスクリーンショットが半分の大きさで書き出されてしまう
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              ImageEditRules.canEdit(pixelWidth: image.width, pixelHeight: image.height)
        else { return nil }

        guard let display = ImageDownsampler.cgImage(from: data, maxPixelSize: displayMaxPixelSize)
        else { return nil }

        let size = CGSize(width: image.width, height: image.height)
        // 縮小版のマス目は、縮んだぶんだけ小さくする。同じ大きさで作ると、
        // 画面では粗いのに保存すると細かい（またはその逆）という食い違いが出る
        let displayScale = CGFloat(display.width) / CGFloat(image.width)
        let block = ImageEditRules.mosaicBlockSize(forImageSize: size) * displayScale
        let mosaic = ImageBitmap.pixelated(display, block: block) ?? display

        return ImageEditSource(
            image: image,
            display: ImageDownsampler.nsImage(display),
            mosaicDisplay: ImageDownsampler.nsImage(mosaic),
            logicalScale: logicalScale(of: data, pixelWidth: image.width)
        )
    }

    /// 元データが持っている解像度（PNG の pHYs など）から、ピクセルとポイントの比を求める。
    /// 読めない場合は等倍として扱う
    private static func logicalScale(of data: Data, pixelWidth: Int) -> CGFloat {
        guard let nsImage = NSImage(data: data), nsImage.size.width > 0 else { return 1 }
        let scale = CGFloat(pixelWidth) / nsImage.size.width
        return scale > 0 ? scale : 1
    }
}

// MARK: - PasteCore の値を描画 API へ橋渡しする

extension StrokeColor {
    var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    var swiftUIColor: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}

/// 書き込む文字の書体。プレビュー（SwiftUI）と保存（Core Text）で同じ形になるよう、
/// 定義はここ 1 か所にまとめる
enum ImageTextStyle {
    static func swiftUIFont(size: CGFloat) -> Font {
        .system(size: size, weight: .semibold)
    }

    /// Core Text へ直接渡す属性。`NSAttributedString.Key.foregroundColor` は
    /// AppKit 側の鍵なので、`CTLineDraw` に確実に効く CT の鍵を使う
    static func coreTextAttributes(size: CGFloat, color: StrokeColor) -> [NSAttributedString.Key: Any] {
        [
            NSAttributedString.Key(kCTFontAttributeName as String):
                NSFont.systemFont(ofSize: size, weight: .semibold),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color.cgColor,
        ]
    }
}
