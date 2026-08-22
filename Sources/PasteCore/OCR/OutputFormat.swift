import Foundation

/// OCR 結果の出力形式（純粋な値・テスト対象）。
///
/// 永続化はここに持たない。UserDefaults を PasteCore へ持ち込まないため、
/// 保存は PasteDeck 側の `OCRPreferences` が担う（`RetentionPolicy` と同じ分け方）
public enum OutputFormat: String, CaseIterable, Equatable, Sendable {
    /// プレーンテキスト。表はタブ区切りで、Excel にそのまま貼れる
    case text
    /// Markdown。表は | 区切り、JSON はコードブロックで囲む
    case markdown

    /// 整形済み JSON を、Markdown のときだけコードブロックで包む
    public func wrapJSON(_ prettyJSON: String) -> String {
        switch self {
        case .text: return prettyJSON
        case .markdown: return "```json\n" + prettyJSON + "\n```"
        }
    }
}
