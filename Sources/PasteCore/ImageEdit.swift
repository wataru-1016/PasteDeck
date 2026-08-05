import CoreGraphics
import Foundation

/// 画像編集（⌘E）で使う道具
public enum ImageTool: String, Equatable, CaseIterable, Sendable {
    /// フリーハンドの線
    case pen
    /// 塗りつぶした矩形。見せたくない部分を隠すのに使う
    case redaction
    /// 矢印
    case arrow
    /// 切り抜き範囲の指定
    case crop

    /// ドラッグの通過点をすべて形に使うか。false なら始点と終点だけで形が決まる
    public var usesAllPoints: Bool { self == .pen }

    /// 描く色。道具ごとに固定する（色の選択は持たない）
    public var color: StrokeColor {
        switch self {
        case .redaction: return .black
        case .pen, .arrow, .crop: return .marker
        }
    }
}

/// 描画色。PasteCore は AppKit に依存しないため RGBA の値で持つ
public struct StrokeColor: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// 黒塗り用。隠す用途なので不透明でなければならない
    public static let black = StrokeColor(red: 0, green: 0, blue: 0)
    /// 注釈用の赤。スクリーンショットの地の色に埋もれない彩度にする
    public static let marker = StrokeColor(red: 0.91, green: 0.17, blue: 0.16)
}

/// 1 回のドラッグで確定した描き込み。
/// 座標は元画像のピクセル（左上原点）で、線幅も画像ピクセル単位
public struct ImageStroke: Equatable, Sendable {
    public let tool: ImageTool
    public let points: [CGPoint]
    public let lineWidth: CGFloat

    public init(tool: ImageTool, points: [CGPoint], lineWidth: CGFloat) {
        self.tool = tool
        self.points = points
        self.lineWidth = lineWidth
    }

    /// 始点と終点。矩形・矢印の形はこの 2 点だけで決まる
    public var endpoints: (from: CGPoint, to: CGPoint)? {
        guard points.count >= 2, let from = points.first, let to = points.last else { return nil }
        return (from, to)
    }

    /// 矩形として見たときの範囲。ドラッグの向きに依らず正の幅・高さになる
    public var rect: CGRect? {
        guard let endpoints else { return nil }
        return ImageEditRules.rect(from: endpoints.from, to: endpoints.to)
    }
}

/// 取り消し（⌘Z）1 回分の操作。
///
/// 座標はトリミング後の座標系へ移さず、常に元画像のピクセルで持つ。
/// 移してしまうと、トリミングを取り消したときに描き込みの位置がずれる
public enum ImageEdit: Equatable, Sendable {
    case stroke(ImageStroke)
    case crop(CGRect)
}
