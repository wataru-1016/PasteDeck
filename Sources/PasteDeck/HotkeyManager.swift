import Carbon.HIToolbox
import Foundation
import PasteCore

/// グローバルホットキーの登録。
/// アプリが非アクティブでも発火させるため Carbon の RegisterEventHotKey を使う。
///
/// 複数の action を同時に押さえるため、押されたキーは `EventHotKeyID.id` から
/// 逆引きする。ID を見ずに発火させると、どのキーを押しても同じ動作になる
final class HotkeyManager {
    enum RegistrationError: Error {
        /// 同じ組み合わせが既に押さえられている
        case alreadyInUse
        /// PasteDeck 自身の別の action に割り当て済み
        case conflictsWith(HotkeyAction)
        case failed(OSStatus)

        var message: String {
            switch self {
            case .alreadyInUse:
                return "他のアプリまたはシステムがこの組み合わせを使用中です。別のキーを試してください。"
            case .conflictsWith(let action):
                return "「\(action.displayName)」に割り当て済みです。"
            case .failed(let status):
                return "ショートカットを登録できませんでした（コード: \(status)）。"
            }
        }
    }

    private static let signature: OSType = 0x5044_434B  // 'PDCK'

    private var hotKeyRefs: [HotkeyAction: EventHotKeyRef] = [:]
    private var eventHandlerRef: EventHandlerRef?
    private let onHotkey: (HotkeyAction) -> Void
    private(set) var shortcuts: [HotkeyAction: HotkeyShortcut]

    init(shortcuts: [HotkeyAction: HotkeyShortcut], onHotkey: @escaping (HotkeyAction) -> Void) {
        self.shortcuts = shortcuts
        self.onHotkey = onHotkey
    }

    deinit {
        unregisterAll()
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    func shortcut(for action: HotkeyAction) -> HotkeyShortcut {
        shortcuts[action] ?? action.defaultShortcut
    }

    /// 実際に登録できているか。メニューにキー表記を出すかの判定に使う。
    /// 他アプリに取られているキーの表記を出すと、押しても効かないキーを案内することになる
    func isRegistered(_ action: HotkeyAction) -> Bool {
        hotKeyRefs[action] != nil
    }

    /// イベントハンドラを取り付け、現在のショートカットをすべて登録する。
    /// 1 つが失敗しても残りは登録する（片方が他アプリに取られていても、もう片方は使えるため）
    func start() {
        installEventHandler()
        for action in HotkeyAction.allCases {
            do {
                try registerHotKey(shortcut(for: action), for: action)
            } catch {
                Log.error("「\(action.displayName)」のショートカットを登録できませんでした: \(error)")
            }
        }
    }

    /// 新しい組み合わせへ差し替える。登録に失敗したら元の組み合わせへ戻す
    func update(_ action: HotkeyAction, to newShortcut: HotkeyShortcut) throws {
        let previous = shortcut(for: action)
        guard newShortcut != previous else { return }
        // Carbon は自分自身の登録との衝突を eventHotKeyExistsErr で返さないことがあるため、
        // 「他のアプリが使用中です」と誤って案内しないよう先に自前で見る
        if let conflict = shortcuts.first(where: { $0.key != action && $0.value == newShortcut })?.key {
            throw RegistrationError.conflictsWith(conflict)
        }
        unregisterHotKey(for: action)
        do {
            try registerHotKey(newShortcut, for: action)
            shortcuts[action] = newShortcut
        } catch {
            try? registerHotKey(previous, for: action)
            throw error
        }
    }

    /// 一時的にすべての登録を外す。
    /// キー記録中にホットキーが発火してパネルが開くのを防ぐために使う
    func suspend() {
        unregisterAll()
    }

    func resume() {
        for action in HotkeyAction.allCases where hotKeyRefs[action] == nil {
            do {
                try registerHotKey(shortcut(for: action), for: action)
            } catch {
                Log.error("「\(action.displayName)」のショートカットを再登録できませんでした: \(error)")
            }
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
            // C 関数ポインタなので self はキャプチャできない。
            // インスタンスは userData から復元し、型の static メンバーは名前で参照する
            { _, event, userData -> OSStatus in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var pressedID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &pressedID
                )
                guard status == noErr,
                      pressedID.signature == HotkeyManager.signature,
                      let action = HotkeyAction.action(forCarbonID: pressedID.id)
                else { return OSStatus(eventNotHandledErr) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { manager.onHotkey(action) }
                return noErr
            },
            1,
            &eventType,
            selfPointer,
            &eventHandlerRef
        )
    }

    private func registerHotKey(_ shortcut: HotkeyShortcut, for action: HotkeyAction) throws {
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: action.carbonID)
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
        hotKeyRefs[action] = newRef
    }

    private func unregisterHotKey(for action: HotkeyAction) {
        guard let ref = hotKeyRefs[action] else { return }
        UnregisterEventHotKey(ref)
        hotKeyRefs[action] = nil
    }

    private func unregisterAll() {
        for action in hotKeyRefs.keys {
            unregisterHotKey(for: action)
        }
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
