import Foundation
import PasteCore

/// パネルを開くグローバルホットキーの UserDefaults 永続化。
/// 未設定・壊れた値のときはデフォルト（⇧⌘V）へ落とす
enum HotkeyPreferences {
    private static let keyCodeKey = "hotkeyKeyCode"
    private static let modifiersKey = "hotkeyModifiers"

    static func load() -> HotkeyShortcut {
        let defaults = UserDefaults.standard
        guard
            let keyCode = defaults.object(forKey: keyCodeKey) as? Int,
            let modifiers = defaults.object(forKey: modifiersKey) as? Int
        else { return .default }

        let stored = HotkeyShortcut(
            keyCode: UInt16(truncatingIfNeeded: keyCode),
            modifiers: HotkeyShortcut.Modifiers(rawValue: modifiers)
        )
        // 旧バージョンや手書きの defaults から登録できない組み合わせが来ても、
        // ホットキーなしで起動してしまわないようにする
        return stored.isValid ? stored : .default
    }

    static func save(_ shortcut: HotkeyShortcut) {
        let defaults = UserDefaults.standard
        defaults.set(Int(shortcut.keyCode), forKey: keyCodeKey)
        defaults.set(shortcut.modifiers.rawValue, forKey: modifiersKey)
    }
}
