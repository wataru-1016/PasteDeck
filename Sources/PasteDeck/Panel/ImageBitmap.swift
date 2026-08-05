import CoreGraphics

/// 画像編集で使うビットマップ操作
enum ImageBitmap {
    /// 描き込み先のビットマップ。sRGB 固定にして、色空間の違いで色味が変わらないようにする
    static func context(width: Int, height: Int) -> CGContext? {
        guard width > 0, height > 0 else { return nil }
        return CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    /// 画像全体をマス目状に粗くする（モザイク）。
    ///
    /// 縮小してから補間なしで元の大きさへ戻す。戻すときにぼかす（`.medium` など）と
    /// 元の輪郭がうっすら残り、隠したい文字が読めてしまうことがある
    static func pixelated(_ image: CGImage, block: CGFloat) -> CGImage? {
        guard block > 1 else { return image }

        let width = image.width
        let height = image.height
        let reducedWidth = max(1, Int((CGFloat(width) / block).rounded()))
        let reducedHeight = max(1, Int((CGFloat(height) / block).rounded()))

        guard let reduced = context(width: reducedWidth, height: reducedHeight) else { return nil }
        // 縮小はならして 1 マスぶんの平均色を作る
        reduced.interpolationQuality = .medium
        reduced.draw(image, in: CGRect(x: 0, y: 0, width: reducedWidth, height: reducedHeight))

        guard let blocks = reduced.makeImage(),
              let full = context(width: width, height: height)
        else { return nil }
        full.interpolationQuality = .none
        full.draw(blocks, in: CGRect(x: 0, y: 0, width: width, height: height))
        return full.makeImage()
    }
}
