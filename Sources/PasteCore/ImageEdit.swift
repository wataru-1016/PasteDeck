import CoreGraphics
import Foundation

/// 画像編集（⌘E）で使う道具。
/// 宣言した順がツールバーの並びであり、数字キー（1〜8）の割り当てでもある
public enum ImageTool: String, Equatable, CaseIterable, Sendable {
    /// 塗りつぶした矩形。見せたくない部分を隠すのに使う
    case redaction
    /// 選んだ範囲を粗くして読めなくする
    case mosaic
    /// フリーハンドの線
    case pen
    /// 矢印
    case arrow
    /// 枠だけの四角。中身は塗らない（塗って隠すのは `redaction`）
    case rectangle
    /// 枠だけの楕円。ドラッグした範囲に収まる大きさになる
    case ellipse
    /// 文字の書き込み
    case text
    /// 切り抜き範囲の指定
    case crop

    /// ドラッグの通過点をすべて形に使うか。false なら始点と終点だけで形が決まる
    public var usesAllPoints: Bool { self == .pen }

    /// 色と寸法（線なら太さ、文字なら大きさ）を選べる道具か。
    ///
    /// 隠す道具（黒塗り・モザイク）とトリミングでは選ばせない。半透明の色や
    /// 粗さの足りないモザイクを選べてしまうと、隠したつもりで隠せていない画像ができる
    public var usesStyle: Bool {
        switch self {
        case .pen, .arrow, .rectangle, .ellipse, .text: return true
        case .redaction, .mosaic, .crop: return false
        }
    }

    /// 実際に使う色。選べない道具は不透明な黒で固定する
    public func color(selected: StrokeColor) -> StrokeColor {
        usesStyle ? selected : .black
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

    /// 選べる色。白と黒も混ぜてあるのは、地の色と同系統になって
    /// 文字や矢印が見えなくなったときの逃げ道を残すため
    public static let choices: [StrokeColorChoice] = [
        StrokeColorChoice(name: "赤", color: .marker),
        StrokeColorChoice(name: "黄", color: StrokeColor(red: 0.98, green: 0.74, blue: 0.09)),
        StrokeColorChoice(name: "緑", color: StrokeColor(red: 0.16, green: 0.68, blue: 0.35)),
        StrokeColorChoice(name: "青", color: StrokeColor(red: 0.11, green: 0.47, blue: 0.95)),
        StrokeColorChoice(name: "白", color: StrokeColor(red: 1, green: 1, blue: 1)),
        StrokeColorChoice(name: "黒", color: .black),
    ]
}

/// 色の選択肢 1 つ分
public struct StrokeColorChoice: Equatable, Sendable, Identifiable {
    public let name: String
    public let color: StrokeColor

    public var id: String { name }

    public init(name: String, color: StrokeColor) {
        self.name = name
        self.color = color
    }
}

/// 線の太さの選択。実際の寸法は画像の大きさにも比例させる
/// （`ImageEditRules.lineWidth(forImageSize:weight:)`）。
/// 文字の大きさはこれを使わず、ピクセルで直に指定する（`ImageStroke.fontSize`）
public enum StrokeWeight: String, Equatable, CaseIterable, Sendable {
    case thin
    case regular
    case bold

    /// 標準の太さに対する倍率
    public var multiplier: CGFloat {
        switch self {
        case .thin: return 0.6
        case .regular: return 1
        case .bold: return 1.8
        }
    }
}

/// 1 回の操作で確定した描き込み。
/// 座標は元画像のピクセル（左上原点）で、線幅も画像ピクセル単位
public struct ImageStroke: Equatable, Sendable {
    public let tool: ImageTool
    public let points: [CGPoint]
    /// 線の太さ（画像ピクセル）
    public let lineWidth: CGFloat
    /// 実際に描く色。`tool` が色を選べない道具なら、渡した色に関わらず黒になる
    public let color: StrokeColor
    /// `tool == .text` のときに書き込む文字。ほかの道具では空
    public let text: String
    /// 書き込む文字の大きさ（画像ピクセル）。`tool == .text` のときだけ意味を持つ。
    /// プレビューと保存で同じ値を使うため、比率ではなく確定した寸法として持つ
    public let fontSize: CGFloat

    /// - Parameter fontSize: 文字の大きさ（画像ピクセル）。省略すると線の太さから決まる
    public init(
        tool: ImageTool,
        points: [CGPoint],
        lineWidth: CGFloat,
        color: StrokeColor = .marker,
        text: String = "",
        fontSize: CGFloat? = nil
    ) {
        self.tool = tool
        self.points = points
        self.lineWidth = lineWidth
        // 道具に色を決めさせる。呼び出し側の渡し忘れで黒塗りが赤くなるような
        // 取り違えは、隠し損ねに直結するので型の側で防ぐ
        self.color = tool.color(selected: color)
        self.text = text
        self.fontSize = fontSize ?? ImageEditRules.fontSize(forLineWidth: lineWidth)
    }

    /// 始点と終点。矢印と、四角・丸・黒塗りなど範囲で決まる形はこの 2 点だけで決まる
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

/// 編集した画像の保存のしかた。
///
/// 取り違えると元の画像が戻せなくなるため、呼び出し側で bool を回さず名前で扱う
public enum ImageSaveMode: String, Equatable, CaseIterable, Sendable {
    /// 元のアイテムを編集後の画像で置き換える（履歴の件数は増えない）
    case overwrite
    /// 元のアイテムを残したまま、編集後の画像を履歴へ追加する
    case addNew
}

/// 取り消し（⌘Z）1 回分の操作。
///
/// 座標はトリミング後の座標系へ移さず、常に元画像のピクセルで持つ。
/// 移してしまうと、トリミングを取り消したときに描き込みの位置がずれる
public enum ImageEdit: Equatable, Sendable {
    case stroke(ImageStroke)
    case crop(CGRect)
}
