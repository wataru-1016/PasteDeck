import CoreGraphics
import Foundation
import PasteCore
import Vision

/// 画像から文字を読み取り、出力形式に沿ったテキストへ組み上げる
enum TextRecognizer {
    enum Output {
        /// 表として組み上げ済み。AI 校正はかけない（列の構造を崩されるため）
        case table(String)
        /// 文章 / JSON。AI 校正の対象
        case text(String)
    }

    /// 読み取れなければ nil
    static func recognize(_ image: CGImage, format: OutputFormat) async -> Output? {
        if #available(macOS 26.0, *) {
            if let output = await recognizeDocument(image, format: format) { return output }
        }
        return await recognizeLines(image, format: format)
    }

    // MARK: - macOS 26 以降: 文書構造ごと認識する

    /// `RecognizeDocumentsRequest` は文字だけでなく「表」などの構造も検出できる。
    /// 表があれば表形式で、JSON らしければ JSON 整形で返す。
    /// 普通の文章は段落の推定に行の座標が要るため、nil を返して行単位の認識へ委ねる
    @available(macOS 26.0, *)
    private static func recognizeDocument(_ image: CGImage, format: OutputFormat) async -> Output? {
        var request = RecognizeDocumentsRequest()
        request.textRecognitionOptions.recognitionLanguages = [
            Locale.Language(identifier: "ja"),
            Locale.Language(identifier: "en"),
        ]

        do {
            let observations = try await request.perform(on: image)
            guard let document = observations.first?.document else { return nil }

            // 1) 表が見つかった場合 → 表形式（タブ区切り or Markdown）
            if !document.tables.isEmpty {
                let text = document.tables.map { table -> String in
                    let rows: [[String]] = table.rows.map { row in
                        row.map { cell in cell.content.text.transcript }
                    }
                    return TableFormatting.format(rows: rows, as: format)
                }.joined(separator: "\n\n")
                if !text.isEmpty { return .table(text) }
            }

            // 2) JSON らしい場合 → インデントを付けて整形
            let transcript = document.text.transcript
            if JSONFormatting.looksLikeJSON(transcript) {
                return .text(format.wrapJSON(JSONFormatting.prettyPrint(transcript)))
            }

            // 3) 普通の文章 → 行単位の認識へ落とす
            return nil
        } catch {
            // 新 API で失敗しても、従来方式で読めることがある
            Log.error("文書構造の認識に失敗しました: \(error)")
            return nil
        }
    }

    // MARK: - 行単位の認識（macOS 14〜25 と、上のフォールバック）

    private static func recognizeLines(_ image: CGImage, format: OutputFormat) async -> Output? {
        let observations = await perform(on: image)
        let lines: [OCRLayout.Line] = observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return OCRLayout.Line(text: candidate.string, box: observation.boundingBox)
        }
        guard !lines.isEmpty else { return nil }

        // JSON らしければ JSON 整形へ（行の並びより構造の復元を優先する）
        let rawJoined = lines
            .map { $0.text.trimmingCharacters(in: .whitespaces) }
            .joined(separator: " ")
        if JSONFormatting.looksLikeJSON(rawJoined) {
            return .text(format.wrapJSON(JSONFormatting.prettyPrint(rawJoined)))
        }

        let layout = OCRLayout.arrange(lines)
        let joined = LineJoining.join(layout.lines, paragraphBreaks: layout.paragraphBreaks)

        // 文章の途中に JSON が埋め込まれていれば、その部分だけブロックとして整形する
        if let mixed = JSONFormatting.formatMixedContent(joined, format: format) {
            return .text(mixed)
        }
        return .text(joined)
    }

    /// `VNImageRequestHandler.perform` は同期で、画像によっては秒単位かかる。
    /// メインスレッドで待つとパネルもメニューも固まるため、別スレッドへ逃がす
    private static func perform(on image: CGImage) async -> [VNRecognizedTextObservation] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate            // 精度優先モード
                request.recognitionLanguages = ["ja-JP", "en-US"]
                request.usesLanguageCorrection = true

                let handler = VNImageRequestHandler(cgImage: image, options: [:])
                do {
                    try handler.perform([request])
                } catch {
                    Log.error("文字の認識に失敗しました: \(error)")
                    continuation.resume(returning: [])
                    return
                }
                // 型付きの VNRecognizeTextRequest では results が既に
                // [VNRecognizedTextObservation]? のため、ダウンキャストは要らない
                continuation.resume(returning: request.results ?? [])
            }
        }
    }
}
