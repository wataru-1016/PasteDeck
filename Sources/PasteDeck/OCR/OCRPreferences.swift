import Foundation
import PasteCore

/// OCR の出力形式と AI 校正の UserDefaults 永続化。
/// 旧 RangeOCR とはドメインが違うため設定は引き継がない（初回は既定値から）
enum OCRPreferences {
    private static let outputFormatKey = "ocr.outputFormat"
    private static let aiPolishKey = "ocr.aiPolishEnabled"

    static func loadOutputFormat() -> OutputFormat {
        guard let raw = UserDefaults.standard.string(forKey: outputFormatKey),
              let format = OutputFormat(rawValue: raw)
        else { return .text }
        return format
    }

    static func save(outputFormat: OutputFormat) {
        UserDefaults.standard.set(outputFormat.rawValue, forKey: outputFormatKey)
    }

    /// 既定は有効。使えない環境ではメニュー側で無効表示にする。
    /// `bool(forKey:)` は未設定でも false を返すため、未設定かどうかを object で見る
    static func loadAIPolishEnabled() -> Bool {
        UserDefaults.standard.object(forKey: aiPolishKey) as? Bool ?? true
    }

    static func save(aiPolishEnabled: Bool) {
        UserDefaults.standard.set(aiPolishEnabled, forKey: aiPolishKey)
    }
}
