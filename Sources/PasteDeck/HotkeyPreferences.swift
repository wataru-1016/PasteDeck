import Foundation
import PasteCore

/// グローバルホットキーの UserDefaults 永続化。
/// 未設定・壊れた値のときは action ごとの既定値へ落とす
enum HotkeyPreferences {
    /// action の区別が無かった頃のキー。履歴パネルの設定として一度だけ引き継ぐ
    private static let legacyKeyCodeKey = "hotkeyKeyCode"
    private static let legacyModifiersKey = "hotkeyModifiers"

    private static func keyCodeKey(_ action: HotkeyAction) -> String {
        "hotkey.\(action.rawValue).keyCode"
    }

    private static func modifiersKey(_ action: HotkeyAction) -> String {
        "hotkey.\(action.rawValue).modifiers"
    }

    static func loadAll() -> [HotkeyAction: HotkeyShortcut] {
        HotkeyAction.allCases.reduce(into: [:]) { result, action in
            result[action] = load(action)
        }
    }

    static func load(_ action: HotkeyAction) -> HotkeyShortcut {
        if let stored = read(keyCodeKey: keyCodeKey(action), modifiersKey: modifiersKey(action)) {
            // 旧バージョンや手書きの defaults から登録できない組み合わせが来ても、
            // ホットキーなしで起動してしまわないようにする
            return stored.isValid ? stored : action.defaultShortcut
        }
        // action ごとのキーへ移行する前に変更してあった組み合わせを、履歴パネルへ引き継ぐ。
        // 画面読み取りにも引き継ぐと、同じ組み合わせが 2 つの action に割り当たってしまう
        if action == .panel,
           let legacy = read(keyCodeKey: legacyKeyCodeKey, modifiersKey: legacyModifiersKey) {
            let migrated = legacy.isValid ? legacy : action.defaultShortcut
            save(migrated, for: action)
            let defaults = UserDefaults.standard
            defaults.removeObject(forKey: legacyKeyCodeKey)
            defaults.removeObject(forKey: legacyModifiersKey)
            return migrated
        }
        return action.defaultShortcut
    }

    static func save(_ shortcut: HotkeyShortcut, for action: HotkeyAction) {
        let defaults = UserDefaults.standard
        defaults.set(Int(shortcut.keyCode), forKey: keyCodeKey(action))
        defaults.set(shortcut.modifiers.rawValue, forKey: modifiersKey(action))
    }

    /// 保存済みの組み合わせを読む。片方でも欠けていれば未設定として nil を返す
    private static func read(keyCodeKey: String, modifiersKey: String) -> HotkeyShortcut? {
        let defaults = UserDefaults.standard
        guard
            let keyCode = defaults.object(forKey: keyCodeKey) as? Int,
            let modifiers = defaults.object(forKey: modifiersKey) as? Int
        else { return nil }
        return HotkeyShortcut(
            keyCode: UInt16(truncatingIfNeeded: keyCode),
            modifiers: HotkeyShortcut.Modifiers(rawValue: modifiers)
        )
    }
}
