import AppKit
import PasteCore
import SwiftUI

/// ショートカット設定ウィンドウ。開いている間は押されたキーをそのまま記録する。
///
/// 記録中は現在のホットキーを一時的に外す。Carbon のグローバルホットキーはどのアプリより
/// 先にキーを取るため、外さないと現在の組み合わせを押した瞬間に履歴パネルが開いてしまう
final class ShortcutSettingsController: NSObject, NSWindowDelegate {
    /// 記録の判定に使う修飾キー。`.deviceIndependentFlagsMask` には capsLock や
    /// numericPad も含まれるため、押されていても影響しないこの 4 つだけを見る
    private static let significantModifiers: NSEvent.ModifierFlags = [.command, .shift, .option, .control]

    private let hotkeyManager: HotkeyManager
    private let model: ShortcutSettingsModel
    private var window: NSWindow?
    private var keyMonitor: Any?

    /// 現在登録されている組み合わせ。メニューの表示に使う
    var shortcut: HotkeyShortcut { hotkeyManager.shortcut }

    init(hotkeyManager: HotkeyManager) {
        self.hotkeyManager = hotkeyManager
        self.model = ShortcutSettingsModel(shortcut: hotkeyManager.shortcut)
        super.init()
    }

    deinit {
        removeKeyMonitor()
    }

    func show() {
        model.shortcut = hotkeyManager.shortcut
        model.errorMessage = nil

        let window = self.window ?? makeWindow()
        self.window = window

        // メニューバーアプリ（.accessory）はアクティブ化しないとウィンドウが前面に出ない
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
        startRecording()
    }

    func windowWillClose(_ notification: Notification) {
        stopRecording()
    }

    // MARK: - ウィンドウ

    private func makeWindow() -> NSWindow {
        let view = ShortcutSettingsView(
            model: model,
            onReset: { [weak self] in self?.apply(.default) },
            onClose: { [weak self] in self?.window?.close() }
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 250),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "ショートカット設定"
        window.contentView = NSHostingView(rootView: view)
        window.isReleasedWhenClosed = false
        window.delegate = self
        return window
    }

    // MARK: - キーの記録

    private func startRecording() {
        model.isRecording = true
        guard keyMonitor == nil else { return }
        hotkeyManager.suspend()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window?.isKeyWindow == true else { return event }
            return self.handleKey(event)
        }
    }

    private func stopRecording() {
        removeKeyMonitor()
        model.isRecording = false
        hotkeyManager.resume()
    }

    private func removeKeyMonitor() {
        guard let keyMonitor else { return }
        NSEvent.removeMonitor(keyMonitor)
        self.keyMonitor = nil
    }

    /// 記録したら nil、ウィンドウの通常操作へ流すならイベントを返す
    private func handleKey(_ event: NSEvent) -> NSEvent? {
        let modifiers = event.modifierFlags.intersection(Self.significantModifiers)

        // 修飾キーなしの esc と ↩ は記録せず、ウィンドウを閉じる／完了ボタンへ渡す。
        // どちらも修飾キーなしでは `isValid` にならないため、記録の妨げにはならない
        if modifiers.isEmpty, event.keyCode == 53 {
            window?.close()
            return nil
        }
        if modifiers.isEmpty, event.keyCode == 36 || event.keyCode == 76 {
            return event
        }

        let candidate = HotkeyShortcut(
            keyCode: event.keyCode,
            modifiers: Self.shortcutModifiers(modifiers)
        )
        guard candidate.isValid else {
            model.errorMessage = "⌘ ⌃ ⌥ のいずれかを含む組み合わせにしてください。"
            return nil
        }
        apply(candidate)
        return nil
    }

    /// 登録して保存する。失敗したら理由を出したまま次の入力を待つ
    private func apply(_ shortcut: HotkeyShortcut) {
        do {
            try hotkeyManager.update(to: shortcut)
            HotkeyPreferences.save(shortcut)
            model.shortcut = shortcut
            model.errorMessage = nil
        } catch let error as HotkeyManager.RegistrationError {
            model.errorMessage = error.message
        } catch {
            model.errorMessage = "ショートカットを登録できませんでした。"
        }
    }

    private static func shortcutModifiers(_ flags: NSEvent.ModifierFlags) -> HotkeyShortcut.Modifiers {
        var modifiers: HotkeyShortcut.Modifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        return modifiers
    }
}
