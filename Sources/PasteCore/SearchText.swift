import Foundation

/// 検索で突き合わせる前に文字をそろえる（純粋関数のみ・テスト対象）
public enum SearchText {
    /// ひらがな U+3041〜U+3096。対応するカタカナ U+30A1〜U+30F6 と 1 対 1 で並んでいる
    private static let hiraganaRange: ClosedRange<UInt32> = 0x3041...0x3096
    /// 上記 2 つのブロックの差
    private static let kanaOffset: UInt32 = 0x60

    /// 打った文字と履歴の文字が「見た目は同じなのに一致しない」状況をなくす。
    ///
    /// 次の 3 つを同じものとして扱う:
    ///   - 全角と半角（ＡＢＣ / ABC、ｶﾀｶﾅ / カタカナ）… NFKC でそろえる
    ///   - 大文字と小文字（Meeting / meeting）
    ///   - ひらがなとカタカナ（めも / メモ）
    ///
    /// ひらがな ⇄ カタカナは NFKC では変換されないため、コード表の差を足して自前で寄せる。
    /// 日本語入力では同じ語をどちらでも打ててしまい、打ち方の違いで履歴が
    /// 見つからないようでは検索として使い物にならないため
    public static func normalized(_ text: String) -> String {
        let folded = text.precomposedStringWithCompatibilityMapping.lowercased()
        let scalars = folded.unicodeScalars.map { scalar -> Unicode.Scalar in
            guard hiraganaRange.contains(scalar.value),
                  let katakana = Unicode.Scalar(scalar.value + kanaOffset)
            else { return scalar }
            return katakana
        }
        return String(String.UnicodeScalarView(scalars))
    }
}
