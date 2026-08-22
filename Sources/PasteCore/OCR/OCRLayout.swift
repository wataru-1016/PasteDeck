import CoreGraphics
import Foundation

/// Vision の観測を「上から順に並んだ行」と「段落の区切り」へ変換する（純粋関数のみ・テスト対象）。
///
/// Vision の正規化座標は左下が原点のため、画面の上から順に読むには midY の降順で並べる。
/// 移植元ではこの計算が OCR のコールバックに埋まっていて一度も検証できていなかった
public enum OCRLayout {
    /// 段落の区切りとみなす行間。平均の行の高さに対する倍率
    public static let paragraphGapRatio: CGFloat = 1.6

    public struct Line: Equatable {
        public let text: String
        /// Vision の boundingBox（正規化座標・左下原点）
        public let box: CGRect

        public init(text: String, box: CGRect) {
            self.text = text
            self.box = box
        }
    }

    public struct Layout: Equatable {
        public let lines: [String]
        /// この行番号の直前に空行を入れる
        public let paragraphBreaks: Set<Int>

        public init(lines: [String], paragraphBreaks: Set<Int>) {
            self.lines = lines
            self.paragraphBreaks = paragraphBreaks
        }
    }

    public static func arrange(_ observed: [Line]) -> Layout {
        let sorted = observed.sorted { $0.box.midY > $1.box.midY }
        let lines = sorted.map(\.text)
        guard sorted.count > 1 else { return Layout(lines: lines, paragraphBreaks: []) }

        let averageHeight = sorted.reduce(0) { $0 + $1.box.height } / CGFloat(sorted.count)
        // 高さが取れないときに全行が段落区切りになってしまうのを防ぐ
        guard averageHeight > 0 else { return Layout(lines: lines, paragraphBreaks: []) }

        var breaks: Set<Int> = []
        for index in 1..<sorted.count {
            let gap = sorted[index - 1].box.minY - sorted[index].box.maxY
            if gap > averageHeight * paragraphGapRatio { breaks.insert(index) }
        }
        return Layout(lines: lines, paragraphBreaks: breaks)
    }
}
