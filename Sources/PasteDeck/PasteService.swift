import AppKit
import ApplicationServices
import PasteCore

/// 選択されたアイテムをクリップボードへ書き戻し、前面アプリに ⌘V を送出して貼り付ける。
/// キーストローク送出にはアクセシビリティ権限が必要。
final class PasteService {
    private static let keystrokeDelay: TimeInterval = 0.12
    private static let vKeyCode: CGKeyCode = 9  // kVK_ANSI_V
    /// 押されたままの修飾キーが離れるのを待つ上限。超えたら諦めて送出する
    private static let modifierReleaseTimeout: TimeInterval = 0.4
    private static let modifierPollInterval: TimeInterval = 0.02
    /// 合成 ⌘V に混ざると困る修飾キー。⌘ 自身は送出したいので含めない
    private static let conflictingModifiers: NSEvent.ModifierFlags = [.shift, .option, .control]

    private let store: HistoryStore
    private let monitor: ClipboardMonitor
    private var didShowAccessibilityHint = false

    init(store: HistoryStore, monitor: ClipboardMonitor) {
        self.store = store
        self.monitor = monitor
    }

    func paste(_ item: ClipboardItem, plainTextOnly: Bool) {
        writeToPasteboard(item, plainTextOnly: plainTextOnly)
        monitor.ignoreNextChange()
        store.moveToFront(item.id)

        guard ensureAccessibilityPermission() else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.keystrokeDelay) {
            Self.postCommandV()
        }
    }

    /// 書き込む内容を確定してから clearContents する。
    /// 「消去したのに何も書き込まない」状態を作らないため、全分岐が必ず書き込みで終わる
    private func writeToPasteboard(_ item: ClipboardItem, plainTextOnly: Bool) {
        let pasteboard = NSPasteboard.general

        if item.kind == .fileList,
           let urls = item.fileURLs?.compactMap({ URL(string: $0) }),
           !urls.isEmpty {
            pasteboard.clearContents()
            pasteboard.writeObjects(urls as [NSURL])
            return
        }

        let flavors = store.flavors(for: item.id) ?? [:]

        // ⇧Enter はプレーンテキスト flavor がある場合のみプレーン化し、
        // ない種別（画像など）は通常貼り付けへフォールバックする
        if plainTextOnly,
           let data = flavors[CaptureRules.plainTextType],
           let text = String(data: data, encoding: .utf8) {
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            return
        }

        if !flavors.isEmpty {
            pasteboard.clearContents()
            for (type, data) in flavors {
                pasteboard.setData(data, forType: NSPasteboard.PasteboardType(type))
            }
            return
        }

        pasteboard.clearContents()
        pasteboard.setString(item.preview, forType: .string)
    }

    private func ensureAccessibilityPermission() -> Bool {
        if AXIsProcessTrusted() { return true }

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)

        if !didShowAccessibilityHint {
            didShowAccessibilityHint = true
            showAccessibilityHint()
        }
        return false
    }

    private func showAccessibilityHint() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "自動貼り付けにはアクセシビリティ権限が必要です"
        alert.informativeText = """
        選んだ内容はすでにクリップボードにコピーされているため、⌘V で貼り付けられます。
        Enter だけで自動貼り付けするには、システム設定の「プライバシーとセキュリティ > アクセシビリティ」で PasteDeck を許可してください。
        """
        alert.addButton(withTitle: "システム設定を開く")
        alert.addButton(withTitle: "あとで")
        if alert.runModal() == .alertFirstButtonReturn {
            Self.openAccessibilitySettings()
        }
    }

    static func openAccessibilitySettings() {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    /// 前面アプリへ ⌘V を送る。
    ///
    /// 押されたままの物理修飾キーは合成イベントに混ざる。⇧Enter で貼り付けた直後は
    /// ⇧ が残っていることがあり、そのまま送ると前面アプリには ⇧⌘V が届く。
    /// これは PasteDeck 自身のグローバルホットキーでもあるため、貼り付けの代わりに
    /// パネルが開き直ってしまう（⌥ でも「⌥⌘V が届く」同じ問題が起きる）。
    /// 離されるのを短い時間だけ待ち、待ちきれなければそのまま送出する
    private static func postCommandV(waited: TimeInterval = 0) {
        let isBlocked = !NSEvent.modifierFlags.intersection(conflictingModifiers).isEmpty
        if isBlocked, waited < modifierReleaseTimeout {
            DispatchQueue.main.asyncAfter(deadline: .now() + modifierPollInterval) {
                postCommandV(waited: waited + modifierPollInterval)
            }
            return
        }

        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cgSessionEventTap)
        keyUp?.post(tap: .cgSessionEventTap)
    }
}
