import Foundation
import FoundationModels
import PasteCore

/// Apple Intelligence のオンデバイスモデルで OCR 結果の誤認識だけを直す
enum AIPolisher {
    /// オンデバイスモデルが扱える分量の上限。超えたら校正をスキップする
    static let maxInputLength = 3000
    /// 応答待ちでアプリが固まらないための打ち切り
    static let timeout: TimeInterval = 25

    /// 使える状態か。メニュー項目の有効/無効に使う
    static var isAvailable: Bool {
        guard #available(macOS 26.0, *) else { return false }
        return SystemLanguageModel.default.isAvailable
    }

    /// 使えない理由（対処法つき）。使えるときは nil
    static var unavailableReason: String? {
        guard #available(macOS 26.0, *) else {
            return "AI 校正には macOS 26 以降が必要です。"
        }
        return unavailableReason(SystemLanguageModel.default.availability)
    }

    /// 校正できなければ nil（呼び出し側は元テキストを使う）
    static func polish(_ text: String, format: OutputFormat) async -> String? {
        guard #available(macOS 26.0, *) else { return nil }
        // オンデバイスモデルは扱える文章量に上限があるため、長すぎる場合はスキップ
        guard text.count <= maxInputLength else { return nil }
        guard SystemLanguageModel.default.isAvailable else { return nil }
        return await respond(to: text, instructions: instructions(for: format))
    }

    // MARK: - モデルとのやり取り

    @available(macOS 26.0, *)
    private static func respond(to text: String, instructions: String) async -> String? {
        do {
            // 応答が返らないまま待ち続けるとアイコンが処理中のまま固まるため、
            // 時間切れのタスクと競争させて先着を採る
            return try await withThrowingTaskGroup(of: String?.self) { group -> String? in
                group.addTask {
                    let session = LanguageModelSession(instructions: instructions)
                    let response = try await session.respond(to: text)
                    return response.content
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    return nil
                }
                let first = try await group.next() ?? nil
                group.cancelAll()

                guard var result = first else { return nil }
                result = result.trimmingCharacters(in: .whitespacesAndNewlines)

                // 安全弁: AI が説明を付けたり大幅に書き換えた場合は採用しない
                // （元の半分未満 or 2 倍超の長さになっていたら怪しいとみなす）
                guard !result.isEmpty,
                      result.count * 2 > text.count,
                      result.count < text.count * 2
                else { return nil }

                return result
            }
        } catch {
            Log.error("AI 校正に失敗しました: \(error)")
            return nil
        }
    }

    /// 校正の指示。文面を変えると出力の傾向が変わるため、移植元のまま保つ
    private static func instructions(for format: OutputFormat) -> String {
        let formatRule: String
        switch format {
        case .text:
            formatRule = """
            - 出力はプレーンテキスト。Markdown記号（#、*、```など）は新たに付けない
            """
        case .markdown:
            formatRule = """
            - 出力はMarkdown形式。元の内容に見出し・箇条書き・表の構造が読み取れる場合は、対応するMarkdown記法（#、-、| 区切り）で表現してよい
            - 既に```jsonコードブロックで囲まれた部分は、囲みを保ったまま中身の誤字だけ修正する
            - Markdown記法の追加以外で内容を変えない
            """
        }

        return """
        あなたはOCR（画像からの文字読み取り）結果を校正する専用アシスタントです。
        与えられたテキストのOCR誤認識だけを修正してください。

        ルール:
        - 修正してよいのは: 誤認識された文字（例: 全角/半角の混同、O/0やl/1の混同、引用符や括弧の化け）、不自然な位置の改行や空白、日本語として明らかに不自然な誤字
        - 内容の追加・削除・要約・翻訳・言い換えは絶対にしない
        - 既にある改行やインデントの構造はできるだけ保つ
        - JSONが含まれる場合は構造とキー名を保ち、明らかな誤字のみ修正する
        \(formatRule)
        - 修正後のテキストだけを出力する。説明や前置きは一切付けない
        """
    }

    /// Apple Intelligence が使えない理由を、対処法つきの分かりやすい文章にする
    @available(macOS 26.0, *)
    private static func unavailableReason(
        _ availability: SystemLanguageModel.Availability
    ) -> String? {
        switch availability {
        case .available:
            return nil
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Mac の Apple Intelligence が OFF になっています。"
                + "システム設定 > Apple Intelligence と Siri で ON にしてください。"
        case .unavailable(.deviceNotEligible):
            return "この Mac は Apple Intelligence に対応していません。"
        case .unavailable(.modelNotReady):
            return "AI モデルを準備中（ダウンロード中）です。"
        default:
            return "Apple Intelligence が現在利用できません。"
        }
    }
}
