// PasteDeck のアプリアイコンを描画して PNG 出力するスクリプト
// 使い方: swift scripts/generate-icon.swift <出力パス.png>
// モチーフ: 扇状に広がったカードのデッキ（履歴パネルのカード UI を表現）
import AppKit

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"

let canvasSize = 1024
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: canvasSize,
    pixelsHigh: canvasSize,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fatalError("ビットマップの作成に失敗しました")
}
guard let nsContext = NSGraphicsContext(bitmapImageRep: rep) else {
    fatalError("描画コンテキストの作成に失敗しました")
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = nsContext
let ctx = nsContext.cgContext
let colorSpace = CGColorSpaceCreateDeviceRGB()

func roundedPath(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

// MARK: 背景（macOS 標準の角丸スクエア + インディゴのグラデーション）

let bgRect = CGRect(x: 100, y: 100, width: 824, height: 824)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: CGColor(gray: 0, alpha: 0.30))
ctx.addPath(roundedPath(bgRect, 185))
ctx.setFillColor(CGColor(red: 0.24, green: 0.24, blue: 0.75, alpha: 1))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(roundedPath(bgRect, 185))
ctx.clip()

let bgGradient = CGGradient(
    colorsSpace: colorSpace,
    colors: [
        CGColor(red: 0.38, green: 0.45, blue: 0.99, alpha: 1),
        CGColor(red: 0.19, green: 0.17, blue: 0.66, alpha: 1),
    ] as CFArray,
    locations: [0, 1]
)!
ctx.drawLinearGradient(
    bgGradient,
    start: CGPoint(x: 512, y: 924),
    end: CGPoint(x: 512, y: 100),
    options: []
)

// 上部の柔らかいハイライト
let highlight = CGGradient(
    colorsSpace: colorSpace,
    colors: [CGColor(gray: 1, alpha: 0.16), CGColor(gray: 1, alpha: 0)] as CFArray,
    locations: [0, 1]
)!
ctx.drawLinearGradient(
    highlight,
    start: CGPoint(x: 512, y: 924),
    end: CGPoint(x: 512, y: 540),
    options: []
)

// MARK: カードのデッキ

func drawCard(
    center: CGPoint,
    size: CGSize,
    rotationDegrees: CGFloat,
    fill: CGColor,
    radius: CGFloat = 44
) {
    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y)
    ctx.rotate(by: rotationDegrees * .pi / 180)
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 34, color: CGColor(gray: 0, alpha: 0.32))
    let rect = CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)
    ctx.addPath(roundedPath(rect, radius))
    ctx.setFillColor(fill)
    ctx.fillPath()
    ctx.restoreGState()
}

// 奥のカード（左右へ扇状に開く）
drawCard(
    center: CGPoint(x: 420, y: 512),
    size: CGSize(width: 360, height: 470),
    rotationDegrees: 14,
    fill: CGColor(red: 0.88, green: 0.91, blue: 1.0, alpha: 0.94)
)
drawCard(
    center: CGPoint(x: 604, y: 512),
    size: CGSize(width: 360, height: 470),
    rotationDegrees: -14,
    fill: CGColor(red: 0.80, green: 0.84, blue: 0.99, alpha: 0.94)
)

// 前面カード
drawCard(
    center: CGPoint(x: 512, y: 486),
    size: CGSize(width: 400, height: 500),
    rotationDegrees: 0,
    fill: CGColor(gray: 1, alpha: 1)
)

// MARK: 前面カードの中身（アクセントバー + テキスト行）

let contentLeft: CGFloat = 512 - 200 + 48
let contentTop: CGFloat = 486 + 250 - 48

ctx.setFillColor(CGColor(red: 0.36, green: 0.43, blue: 0.98, alpha: 1))
ctx.addPath(roundedPath(CGRect(x: contentLeft, y: contentTop - 44, width: 132, height: 44), 22))
ctx.fillPath()

let lineWidths: [CGFloat] = [304, 304, 304, 200]
var lineY = contentTop - 44 - 64
for width in lineWidths {
    ctx.setFillColor(CGColor(gray: 0.86, alpha: 1))
    ctx.addPath(roundedPath(CGRect(x: contentLeft, y: lineY - 30, width: width, height: 30), 15))
    ctx.fillPath()
    lineY -= 30 + 34
}

NSGraphicsContext.current = nil
NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("PNG 変換に失敗しました")
}
do {
    try png.write(to: URL(fileURLWithPath: outputPath))
    print("生成完了: \(outputPath)")
} catch {
    fatalError("書き込みに失敗しました: \(error)")
}
