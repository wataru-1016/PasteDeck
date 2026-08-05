import Carbon.HIToolbox
import Foundation
import PasteCore

/// パネルを開くグローバルホットキーの登録。
/// アプリが非アクティブでも発火させるため Carbon の RegisterEventHotKey を使う。
final class HotkeyManager {
    enum RegistrationError: Error {
        /// 同じ組み合わせが既に押さえられている
        case alreadyInUse
        case failed(OSStatus)

        var message: String {
            switch self {
            case .alreadyInUse:
                return "他のアプリまたはシステムがこの組み合わせを使用中です。別のキーを試してください。"
            case .failed(let status):
                return "ショートカットを登録できませんでした（コード: \(status)）。"
            }
        }
    }

    private static let signature: OSType = 0x5044_434B  // 'PDCK'

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let onHotkey: () -> Void
    private(set) var shortcut: HotkeyShortcut

    init(shortcut: HotkeyShortcut, onHotkey: @escaping () -> Void) {
        self.shortcut = shortcut
        self.onHotkey = onHotkey
    }

    deinit {
        unregisterHotKey()
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    /// イベントハンドラを取り付け、現在のショートカットを登録する
    func start() throws {
        installEventHandler()
        try registerHotKey(shortcut)
    }

    /// 新しい組み合わせへ差し替える。登録に失敗したら元の組み合わせへ戻す
    func update(to newShortcut: HotkeyShortcut) throws {
        guard newShortcut != shortcut else { return }
        let previous = shortcut
        unregisterHotKey()
        do {
            try registerHotKey(newShortcut)
            shortcut = newShortcut
        } catch {
            try? registerHotKey(previous)
            throw error
        }
    }

    /// 一時的に登録を外す。
    /// キー記録中に現在のホットキーが発火してパネルが開くのを防ぐために使う
    func suspend() {
        unregisterHotKey()
    }

    func resume() {
        guard hotKeyRef == nil else { return }
        do {
            try registerHotKey(shortcut)
        } catch {
            Log.error("ショートカットを再登録できませんでした: \(error)")
        }
    }

    // MARK: - Carbon

    private func installEventHandler() {
        guard eventHandlerRef == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, _, userData -> OSStatus in
                guard let userData else { return noErr }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { manager.onHotkey() }
                return noErr
            },
            1,
            &eventType,
            selfPointer,
            &eventHandlerRef
        )
    }

    private func registerHotKey(_ shortcut: HotkeyShortcut) throws {
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: 1)
        var newRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            Self.carbonModifiers(shortcut.modifiers),
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &newRef
        )
        guard status == noErr, let newRef else {
            Log.error("ホットキーの登録に失敗しました (status: \(status))")
            throw status == eventHotKeyExistsErr
                ? RegistrationError.alreadyInUse
                : RegistrationError.failed(status)
        }
        hotKeyRef = newRef
    }

    private func unregisterHotKey() {
        guard let hotKeyRef else { return }
        UnregisterEventHotKey(hotKeyRef)
        self.hotKeyRef = nil
    }

    private static func carbonModifiers(_ modifiers: HotkeyShortcut.Modifiers) -> UInt32 {
        var flags = 0
        if modifiers.contains(.command) { flags |= cmdKey }
        if modifiers.contains(.shift) { flags |= shiftKey }
        if modifiers.contains(.option) { flags |= optionKey }
        if modifiers.contains(.control) { flags |= controlKey }
        return UInt32(flags)
    }
}
