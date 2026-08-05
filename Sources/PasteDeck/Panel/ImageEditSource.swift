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
    /// ピクセル ÷ ポイント。Retina のスクリーンショットは 2。
    /// 保存時にこの比を戻さないと、貼り付け先で 2 倍の大きさになる
    let logicalScale: CGFloat
    /// この画像に対する線の太さ（画像ピクセル単位）
    let lineWidth: CGFloat

    var pixelWidth: Int { image.width }
    var pixelHeight: Int { image.height }
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

        guard let display = ImageDownsampler.image(from: data, maxPixelSize: displayMaxPixelSize)
        else { return nil }

        let size = CGSize(width: image.width, height: image.height)
        return ImageEditSource(
            image: image,
            display: display,
            logicalScale: logicalScale(of: data, pixelWidth: image.width),
            lineWidth: ImageEditRules.lineWidth(forImageSize: size)
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

extension StrokeColor {
    var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    var swiftUIColor: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}
