import Foundation

/// 装飾テキストプレビューの表示調整ルール（純粋関数のみ・テスト対象）。
///
/// RTF flavor をそのままカードへ描くと 2 つの問題が起きるため、ここで補正する。
/// - Excel の 16pt などをそのまま出すとカードの本文領域に収まらない
/// - Excel の既定文字色は黒で、ダークモードのカード背景に埋もれて読めなくなる
public enum RichTextStyle {
    /// カード本文の基準フォントサイズ（プレーン表示と揃える）
    public static let baseFontSize: Double = 12.5
    /// カードへ収めるための上限サイズ
    public static let maxFontSize: Double = 15
    /// 縮小しても読める下限サイズ
    public static let minFontSize: Double = 8
    /// これを超える RTF はデコードせずプレーン表示へフォールバックする。
    /// 使うのは先頭 `CaptureRules.previewMaxLength` 文字だけだが、RTF は全体を
    /// パースしないと先頭が取り出せないため、パース時間が伸びすぎる前に打ち切る
    public static let maxDecodableBytes = 512 * 1024
    /// この彩度を下回る色は「ドキュメントの既定色」とみなして捨てる
    public static let colorSaturationThreshold: Double = 0.15

    /// プレビューとして表示する範囲の最大フォントサイズを、上限へ収める倍率。
    /// 全 run へ同じ倍率を掛けることで、サイズの大小関係を保ったまま全体を縮小する。
    /// 倍率が 1 を超えることはない（元の書式より大きくは表示しない）
    public static func fontScale(maxSourceSize: Double) -> Double {
        guard maxSourceSize > maxFontSize else { return 1 }
        return maxFontSize / maxSourceSize
    }

    /// 倍率を適用したフォントサイズ。
    /// 縮小の有無にかかわらず、カード上で判読できない大きさにはしない
    public static func scaledFontSize(_ size: Double, scale: Double) -> Double {
        max(minFontSize, size * scale)
    }

    /// HSV の彩度。無彩色（黒・白・グレー）で 0 になる
    public static func saturation(red: Double, green: Double, blue: Double) -> Double {
        let maxComponent = max(red, green, blue)
        guard maxComponent > 0 else { return 0 }
        return (maxComponent - min(red, green, blue)) / maxComponent
    }

    /// 色を保持すべきか。無彩色・透明はドキュメント側の既定値とみなし、
    /// カード側の配色（ライト／ダーク対応）へ任せる
    public static func isMeaningfulColor(
        red: Double,
        green: Double,
        blue: Double,
        alpha: Double
    ) -> Bool {
        guard alpha > 0 else { return false }
        return saturation(red: red, green: green, blue: blue) >= colorSaturationThreshold
    }

    /// 前景色を保持すべきか。
    ///
    /// 背景色を保持する run では、無彩色（白・黒）であっても「その背景の上で読める
    /// ように選ばれた色」なので必ず保持する。捨てると OS 既定色に置き換わり、
    /// 残った塗りつぶし背景とのコントラストが失われて判読できなくなる
    /// （Excel の「濃色セル ＋ 白の太字」という見出し行がこれに当たる）
    public static func keepsForegroundColor(
        red: Double,
        green: Double,
        blue: Double,
        alpha: Double,
        hasBackgroundColor: Bool
    ) -> Bool {
        guard alpha > 0 else { return false }
        if hasBackgroundColor { return true }
        return isMeaningfulColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    public static func canDecode(byteCount: Int) -> Bool {
        byteCount <= maxDecodableBytes
    }

    /// 前後の空白・改行を除いた範囲。全体が空白なら nil。
    /// 装飾を保ったまま切り出すため、文字列ではなく範囲を返す
    public static func trimmedRange(of text: String) -> Range<String.Index>? {
        guard let first = text.firstIndex(where: { !$0.isWhitespace }),
              let last = text[first...].lastIndex(where: { !$0.isWhitespace })
        else { return nil }
        return first..<text.index(after: last)
    }
}
