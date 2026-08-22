import AppKit
import CoreGraphics
import Foundation
import ImageIO
import PasteCore

/// 画面の読み取りの司会。キャプチャ → 認識 → AI 校正 → クリップボード + 履歴。
///
/// `HistoryStore` と同じくメインスレッドからの利用を前提とする。
/// 認識と AI 校正は時間がかかるため別スレッドへ逃がし、結果だけをメインへ戻す
final class OCRController {
    /// 読み取り結果の履歴に付けるコピー元アプリ名。検索でこの語で絞り込める
    static let sourceAppName = "画面読み取り"

    private let store: HistoryStore
    private let monitor: ClipboardMonitor
    private let panelController: PanelController

    /// アイコン状態の通知先。StatusBarController が後から刺す
    var onStatusChange: ((StatusIconState) -> Void)?

    /// 「もう一度コピー」用。メニューの有効/無効の判定にも使う
    private(set) var lastText: String?
    /// 読み取り中の多重起動を、⇧⌘7 と ⌘R の両方の経路でまとめて防ぐ。
    /// メニュー項目を押させないための判定にも使う
    private(set) var isWorking = false

    init(store: HistoryStore, monitor: ClipboardMonitor, panelController: PanelController) {
        self.store = store
        self.monitor = monitor
        self.panelController = panelController
    }

    /// ⇧⌘7 とメニューから。範囲を選ばせて読み取る
    func capture() {
        guard !isWorking else { NSSound.beep(); return }
        isWorking = true
        onStatusChange?(.working)

        // パネルが写り込まないよう、閉じ終わってからキャプチャを始める。
        // 非表示のときは completion が同期で呼ばれるので、どちらの場合も正しく動く
        panelController.hide { [weak self] in
            ScreenCaptureService.selectRegion { outcome in
                // terminationHandler はバックグラウンドで呼ばれる
                DispatchQueue.main.async { self?.handle(outcome) }
            }
        }
    }

    /// 履歴の画像カードから（⌘R）。画面収録の許可も screencapture も要らない
    func recognize(_ item: ClipboardItem) {
        guard !isWorking else { NSSound.beep(); return }
        guard item.kind == .image else { return }
        isWorking = true
        onStatusChange?(.working)

        // 数 MB の PNG を展開する間パネルが固まらないよう、読み込みだけ別スレッドで行う。
        // persistence は値型なので他スレッドへ渡してよい（store 本体は渡さない）
        let persistence = store.persistence
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let image = persistence.loadFlavors(id: item.id)
                .flatMap { flavors in CaptureRules.imageTypes.compactMap { flavors[$0] }.first }
                .flatMap { Self.cgImage(from: $0) }
            DispatchQueue.main.async {
                guard let self else { return }
                guard let image else {
                    Log.error("履歴の画像を読み込めませんでした: \(item.id)")
                    self.finish(.failed)
                    return
                }
                self.recognizeAndDeliver(image)
            }
        }
    }

    /// 直前の読み取り結果をもう一度クリップボードへ置く
    func recopyLast() {
        // 読み取り中は受け付けない。deliver が finish まで進んで isWorking を下ろすため、
        // ここを通すと進行中の読み取りの排他が解け、後続の読み取りと結果を奪い合う
        guard !isWorking, let lastText else { NSSound.beep(); return }
        deliver(lastText)
    }

    // MARK: - 読み取りの流れ

    private func handle(_ outcome: ScreenCaptureService.Outcome) {
        switch outcome {
        case .captured(let image):
            recognizeAndDeliver(image)
        case .cancelled:
            // esc で閉じただけ。音も表示も出さずに戻る
            finish(nil)
        case .failed:
            finish(.failed)
        }
    }

    /// 認識と AI 校正を別スレッドで進め、結果をメインスレッドで届ける
    private func recognizeAndDeliver(_ image: CGImage) {
        // 設定はメインスレッドで読んでから渡す
        let format = OCRPreferences.loadOutputFormat()
        let shouldPolish = OCRPreferences.loadAIPolishEnabled()

        Self.recognizeInBackground(image, format: format, shouldPolish: shouldPolish) { [weak self] text in
            guard let self else { return }
            guard let text else {
                self.finish(.failed)
                return
            }
            self.deliver(text)
        }
    }

    /// 認識を待つ間 UI を止めないよう、非同期処理はここへ閉じ込める。
    /// `completion` はメインスレッドで呼ばれる
    private static func recognizeInBackground(
        _ image: CGImage,
        format: OutputFormat,
        shouldPolish: Bool,
        completion: @escaping (String?) -> Void
    ) {
        Task {
            let text = await recognizedText(image, format: format, shouldPolish: shouldPolish)
            DispatchQueue.main.async { completion(text) }
        }
    }

    private static func recognizedText(
        _ image: CGImage,
        format: OutputFormat,
        shouldPolish: Bool
    ) async -> String? {
        guard let output = await TextRecognizer.recognize(image, format: format) else { return nil }
        switch output {
        case .table(let text):
            // 表は列の構造が命なので、AI 校正で崩されないようそのまま返す
            return text
        case .text(let text):
            guard shouldPolish, AIPolisher.isAvailable else { return text }
            // 校正の間もアイコンは処理中のままにする
            return await AIPolisher.polish(text, format: format) ?? text
        }
    }

    /// クリップボードへ書き、そのうえで履歴に 1 件だけ残す
    private func deliver(_ text: String) {
        guard !text.isEmpty else {
            finish(.failed)
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        // 書き込み → ignoreNextChange → ingest の順。逆にすると監視が
        // 自分の書き込みを拾い直して履歴が 2 件になる
        monitor.ignoreNextChange()
        store.ingest(CapturedContent(
            flavors: [CaptureRules.plainTextType: Data(text.utf8)],
            sourceAppName: Self.sourceAppName
        ))
        lastText = text
        finish(.succeeded)
    }

    /// 後始末。`nil` はキャンセルで、音も表示も出さずに待機へ戻す
    private func finish(_ state: StatusIconState?) {
        isWorking = false
        if state == .failed { NSSound.beep() }
        onStatusChange?(state ?? .idle)
    }

    /// 履歴に保存された画像データをピクセルのまま読む。
    /// NSImage 経由だと解像度を加味した論理サイズになり、Retina の画像が半分の大きさになる
    private static func cgImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
