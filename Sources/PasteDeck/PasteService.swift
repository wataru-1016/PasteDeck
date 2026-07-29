import AppKit
import ApplicationServices
import PasteCore

/// 選択されたアイテムをクリップボードへ書き戻し、前面アプリに ⌘V を送出して貼り付ける。
/// キーストローク送出にはアクセシビリティ権限が必要。
final class PasteService {
    private static let keystrokeDelay: TimeInterval = 0.12
    private static let vKeyCode: CGKeyCode = 9  // kVK_ANSI_V

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

    private func writeToPasteboard(_ item: ClipboardItem, plainTextOnly: Bool) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        if item.kind == .fileList,
           let urls = item.fileURLs?.compactMap({ URL(string: $0) }),
           !urls.isEmpty {
            pasteboard.writeObjects(urls as [NSURL])
            return
        }

        guard let flavors = store.flavors(for: item.id), !flavors.isEmpty else {
            pasteboard.setString(item.preview, forType: .string)
            return
        }

        if plainTextOnly {
            if let data = flavors[CaptureRules.plainTextType],
               let text = String(data: data, encoding: .utf8) {
                pasteboard.setString(text, forType: .string)
            }
        } else {
            for (type, data) in flavors {
                pasteboard.setData(data, forType: NSPasteboard.PasteboardType(type))
            }
        }
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

    private static func postCommandV() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cgSessionEventTap)
        keyUp?.post(tap: .cgSessionEventTap)
    }
}
