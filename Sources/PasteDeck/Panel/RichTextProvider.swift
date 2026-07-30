import AppKit
import PasteCore
import SwiftUI

/// テキストアイテムの RTF flavor を、SwiftUI の `Text` が描画できる `AttributedString` へ
/// 変換する（非同期・キャッシュ付き）。
///
/// Excel や Word からのコピーは `public.rtf` に元の書式を持っているため、
/// これを読むことでコピー元の色・太さ・サイズ・フォントをカード上で再現できる。
/// RTF が無い／デコードできない場合は nil を返し、呼び出し側はプレーン表示へ戻す。
final class RichTextProvider {
    static let rtfType = "public.rtf"

    static let shared = RichTextProvider()

    /// `AttributedString` は値型で NSCache へ直接入れられないためラップする。
    /// 「RTF なし」という結果もキャッシュし、毎回ディスクを読まないようにする
    private final class Box {
        let value: AttributedString?

        init(_ value: AttributedString?) {
            self.value = value
        }
    }

    private let cache = NSCache<NSString, Box>()
    /// RTF のデコードには AppKit の API を使う。並行呼び出しの安全性が保証されて
    /// いないため直列キューで行う。結果はキャッシュされ 1 アイテムにつき 1 回で済む
    private let decodeQueue = DispatchQueue(
        label: "app.pastedeck.richtext-decode",
        qos: .userInitiated
    )

    init() {
        cache.countLimit = 200
    }

    /// アイテムの内容が変わったときにキャッシュを捨てる。
    /// ⌘E の編集で装飾を破棄しても、捨てないと古い装飾付きの表示が残ってしまう
    func invalidate(id: UUID) {
        cache.removeObject(forKey: id.uuidString as NSString)
    }

    func richText(
        for item: ClipboardItem,
        persistence: Persistence,
        completion: @escaping (AttributedString?) -> Void
    ) {
        let key = item.id.uuidString as NSString
        if let cached = cache.object(forKey: key) {
            completion(cached.value)
            return
        }

        decodeQueue.async { [weak self] in
            let data = persistence.loadFlavors(id: item.id)?[Self.rtfType]
            let richText = data.flatMap { Self.attributedString(fromRTF: $0) }
            DispatchQueue.main.async {
                self?.cache.setObject(Box(richText), forKey: key)
                completion(richText)
            }
        }
    }

    // MARK: - 変換

    /// RTF を SwiftUI が扱える属性だけの `AttributedString` へ変換する。
    /// AppKit 側の属性をそのまま渡すと SwiftUI では無視されるため、run ごとに詰め替える
    static func attributedString(fromRTF data: Data) -> AttributedString? {
        guard RichTextStyle.canDecode(byteCount: data.count),
              let source = NSAttributedString(rtf: data, documentAttributes: nil),
              let (body, didTruncate) = previewPortion(of: source)
        else { return nil }

        let scale = RichTextStyle.fontScale(maxSourceSize: maxFontSize(in: body))

        var result = AttributedString()
        var lastContainer = AttributeContainer()
        body.enumerateAttributes(
            in: NSRange(location: 0, length: body.length),
            options: []
        ) { attributes, range, _ in
            let text = body.attributedSubstring(from: range).string
            let attributeContainer = container(for: attributes, scale: scale)
            result += AttributedString(text, attributes: attributeContainer)
            lastContainer = attributeContainer
        }

        guard !result.characters.isEmpty else { return nil }
        if didTruncate {
            // 直前の run の書式を引き継ぐ。無属性のままだと省略記号だけ
            // 環境既定のサイズ・色で描かれて浮いてしまう
            result += AttributedString("…", attributes: lastContainer)
        }
        return result
    }

    /// 前後の空白を落とし、プレビュー上限で切り詰めた部分を返す。
    /// 上限を `preview` 文字列と揃えることで、装飾表示とプレーン表示の分量を一致させる
    private static func previewPortion(
        of source: NSAttributedString
    ) -> (body: NSAttributedString, didTruncate: Bool)? {
        let text = source.string
        guard var range = RichTextStyle.trimmedRange(of: text) else { return nil }

        var didTruncate = false
        if let end = text.index(
            range.lowerBound,
            offsetBy: CaptureRules.previewMaxLength,
            limitedBy: range.upperBound
        ), end < range.upperBound {
            range = range.lowerBound..<end
            didTruncate = true
        }

        return (source.attributedSubstring(from: NSRange(range, in: text)), didTruncate)
    }

    private static func maxFontSize(in source: NSAttributedString) -> Double {
        var result: Double = 0
        source.enumerateAttribute(
            .font,
            in: NSRange(location: 0, length: source.length),
            options: []
        ) { value, _, _ in
            guard let font = value as? NSFont else { return }
            result = max(result, Double(font.pointSize))
        }
        return result
    }

    /// AppKit の属性辞書から SwiftUI スコープの属性を組み立てる。
    /// `swiftUI` スコープを明示するのは、AppKit スコープの同名属性
    /// （font が NSFont、foregroundColor が NSColor）と衝突させないため
    private static func container(
        for attributes: [NSAttributedString.Key: Any],
        scale: Double
    ) -> AttributeContainer {
        var result = AttributeContainer()

        if let font = attributes[.font] as? NSFont {
            let size = RichTextStyle.scaledFontSize(Double(font.pointSize), scale: scale)
            // ファミリー・ウェイト・斜体はディスクリプタ経由でそのまま引き継ぎ、サイズだけ補正する
            let resized = NSFont(descriptor: font.fontDescriptor, size: size) ?? font
            result.swiftUI.font = Font(resized as CTFont)
        } else {
            result.swiftUI.font = .system(size: RichTextStyle.baseFontSize)
        }

        // 前景色を保持するかは背景色の有無で変わるため、背景色を先に決める
        let background = meaningfulBackground(attributes[.backgroundColor] as? NSColor)
        if let background {
            result.swiftUI.backgroundColor = Color(nsColor: background)
        }
        if let foreground = keptForeground(
            attributes[.foregroundColor] as? NSColor,
            hasBackgroundColor: background != nil
        ) {
            result.swiftUI.foregroundColor = Color(nsColor: foreground)
        }

        if let style = attributes[.underlineStyle] as? Int, style != 0 {
            result.swiftUI.underlineStyle = .single
        }
        if let style = attributes[.strikethroughStyle] as? Int, style != 0 {
            result.swiftUI.strikethroughStyle = .single
        }

        return result
    }

    /// 無彩色・透明な背景色はドキュメントの既定値とみなして捨てる
    private static func meaningfulBackground(_ color: NSColor?) -> NSColor? {
        guard let srgb = color?.usingColorSpace(.sRGB) else { return nil }
        let isMeaningful = RichTextStyle.isMeaningfulColor(
            red: Double(srgb.redComponent),
            green: Double(srgb.greenComponent),
            blue: Double(srgb.blueComponent),
            alpha: Double(srgb.alphaComponent)
        )
        return isMeaningful ? srgb : nil
    }

    /// 前景色は、無彩色ならドキュメントの既定色とみなして捨てる。
    /// Excel の既定文字色は黒で、そのまま出すとダークモードのカードで読めなくなる。
    /// ただし塗りつぶし背景がある run では無彩色も意味を持つため保持する（判定は
    /// `RichTextStyle.keepsForegroundColor`）
    private static func keptForeground(
        _ color: NSColor?,
        hasBackgroundColor: Bool
    ) -> NSColor? {
        guard let srgb = color?.usingColorSpace(.sRGB) else { return nil }
        let keeps = RichTextStyle.keepsForegroundColor(
            red: Double(srgb.redComponent),
            green: Double(srgb.greenComponent),
            blue: Double(srgb.blueComponent),
            alpha: Double(srgb.alphaComponent),
            hasBackgroundColor: hasBackgroundColor
        )
        return keeps ? srgb : nil
    }
}
