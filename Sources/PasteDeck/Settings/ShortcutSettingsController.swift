import AppKit
import PasteCore
import SwiftUI

/// ショートカット設定ウィンドウ。行を選んでいる間だけ、押されたキーをそのまま記録する。
///
/// 記録中はすべてのホットキーを一時的に外す。Carbon のグローバルホットキーはどのアプリより
/// 先にキーを取るため、外さないと現在の組み合わせを押した瞬間にその動作が走ってしまう
final class ShortcutSettingsController: NSObject, NSWindowDelegate {
    /// 記録の判定に使う修飾キー。`.deviceIndependentFlagsMask` には capsLock や
    /// numericPad も含まれるため、押されていても影響しないこの 4 つだけを見る
    private static let significantModifiers: NSEvent.ModifierFlags = [.command, .shift, .option, .control]

    private let hotkeyManager: HotkeyManager
    private let model: ShortcutSettingsModel
    private var window: NSWindow?
    private var keyMonitor: Any?

    init(hotkeyManager: HotkeyManager) {
        self.hotkeyManager = hotkeyManager
        self.model = ShortcutSettingsModel(shortcuts: hotkeyManager.shortcuts)
        super.init()
    }

    deinit {
        removeKeyMonitor()
    }

    /// 現在登録されている組み合わせ。メニューの表示に使う
    func shortcut(for action: HotkeyAction) -> HotkeyShortcut {
        hotkeyManager.shortcut(for: action)
    }

    /// 実際に登録できているか。メニューにキー表記を出すかの判定に使う
    func isRegistered(_ action: HotkeyAction) -> Bool {
        hotkeyManager.isRegistered(action)
    }

    func show() {
        model.shortcuts = hotkeyManager.shortcuts
        model.errorMessage = nil
        // 開いた瞬間に記録を始めると、どの行が変わるのか分からないまま
        // 最初に押したキーが登録されてしまう
        model.recordingAction = nil

        let window = self.window ?? makeWindow()
        self.window = window

        // メニューバーアプリ（.accessory）はアクティブ化しないとウィンドウが前面に出ない
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        stopRecording()
    }

    // MARK: - ウィンドウ

    private func makeWindow() -> NSWindow {
        let view = ShortcutSettingsView(
            model: model,
            onStartRecording: { [weak self] action in self?.startRecording(action) },
            onReset: { [weak self] action in self?.apply(action.defaultShortcut, for: action) },
            onClose: { [weak self] in self?.window?.close() }
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 330),
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

    private func startRecording(_ action: HotkeyAction) {
        model.recordingAction = action
        model.errorMessage = nil
        guard keyMonitor == nil else { return }
        hotkeyManager.suspend()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window?.isKeyWindow == true else { return event }
            return self.handleKey(event)
        }
    }

    private func stopRecording() {
        removeKeyMonitor()
        model.recordingAction = nil
        hotkeyManager.resume()
    }

    private func removeKeyMonitor() {
        guard let keyMonitor else { return }
        NSEvent.removeMonitor(keyMonitor)
        self.keyMonitor = nil
    }

    /// 記録したら nil、ウィンドウの通常操作へ流すならイベントを返す
    private func handleKey(_ event: NSEvent) -> NSEvent? {
        // 行を選んでいない間は、ウィンドウの通常のキー操作を邪魔しない
        guard let action = model.recordingAction else { return event }

        let modifiers = event.modifierFlags.intersection(Self.significantModifiers)

        // 修飾キーなしの esc は記録を中止し、↩ は完了ボタンへ渡す。
        // どちらも修飾キーなしでは `isValid` にならないため、記録の妨げにはならない
        if modifiers.isEmpty, event.keyCode == 53 {
            stopRecording()
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
        apply(candidate, for: action)
        return nil
    }

    /// 登録して保存する。失敗したら理由を出したまま次の入力を待つ
    private func apply(_ shortcut: HotkeyShortcut, for action: HotkeyAction) {
        do {
            try hotkeyManager.update(action, to: shortcut)
            HotkeyPreferences.save(shortcut, for: action)
            model.shortcuts[action] = shortcut
            model.errorMessage = nil
            stopRecording()
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
