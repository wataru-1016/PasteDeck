import Foundation

/// グローバルホットキーのキー組み合わせ（純粋な値・テスト対象）。
///
/// Carbon と AppKit は修飾キーを別々のビット列で表すため、どちらの定数にも寄せずに
/// 独自の `Modifiers` で保持する。相互変換は使う側（`HotkeyManager` と記録画面）が担う
public struct HotkeyShortcut: Equatable {
    public struct Modifiers: OptionSet, Equatable, Sendable {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        public static let command = Modifiers(rawValue: 1 << 0)
        public static let shift = Modifiers(rawValue: 1 << 1)
        public static let option = Modifiers(rawValue: 1 << 2)
        public static let control = Modifiers(rawValue: 1 << 3)
    }

    /// 仮想キーコード（`kVK_ANSI_V` などの値）
    public let keyCode: UInt16
    public let modifiers: Modifiers

    public static let `default` = HotkeyShortcut(keyCode: 9, modifiers: [.command, .shift])

    public init(keyCode: UInt16, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// `⇧⌘V` のような表示文字列。修飾キーは macOS の慣例に合わせて ⌃⌥⇧⌘ の順に並べる
    public var displayString: String {
        var result = ""
        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option) { result += "⌥" }
        if modifiers.contains(.shift) { result += "⇧" }
        if modifiers.contains(.command) { result += "⌘" }
        return result + Self.keyLabel(for: keyCode)
    }

    /// グローバルホットキーとして登録してよい組み合わせか。
    ///
    /// 修飾キーなしと ⇧ のみを弾くのは、グローバルホットキーがすべてのアプリより先に
    /// キーを奪うため。`V` や `⇧V` を登録すると、どのアプリでも文字が打てなくなる
    public var isValid: Bool {
        guard !Self.modifierKeyCodes.contains(keyCode) else { return false }
        return !modifiers.intersection([.command, .control, .option]).isEmpty
    }

    /// メニュー項目に表示するためのキー文字。
    /// 特殊キーは `NSMenuItem` 側で固有の文字が要るため、英数記号キー以外は nil を返し、
    /// メニューにはショートカットを載せない（実際の発火は Carbon 側が担うため実害はない）
    public var menuKeyEquivalent: String? {
        Self.ansiKeys[keyCode]?.lowercased()
    }

    // MARK: - キーコードの表示名

    /// 修飾キー自身のキーコード（⇧ ⌃ ⌥ ⌘ の左右と Caps Lock・fn）
    private static let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]

    /// 刻印ではなく記号や名前で表したいキー
    private static let namedKeys: [UInt16: String] = [
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋",
        76: "⌤",  // テンキーの Enter
        114: "Help", 115: "↖", 116: "⇞", 117: "⌦", 119: "↘", 121: "⇟",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17",
        79: "F18", 80: "F19", 90: "F20",
    ]

    /// ANSI 配列でのキーコードと刻印の対応。JIS などで刻印が違っても登録自体は成立するため、
    /// 記録画面は実際に押されたキーの文字を優先し、この表は保存済みの設定を表示する際の近似に使う
    private static let ansiKeys: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 31: "O", 32: "U",
        34: "I", 35: "P", 37: "L", 38: "J", 40: "K", 45: "N", 46: "M",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 25: "9", 26: "7", 28: "8", 29: "0",
        24: "=", 27: "-", 30: "]", 33: "[", 39: "'", 41: ";", 42: "\\", 43: ",", 44: "/",
        47: ".", 50: "`",
    ]

    private static func keyLabel(for keyCode: UInt16) -> String {
        namedKeys[keyCode] ?? ansiKeys[keyCode] ?? "Key \(keyCode)"
    }
}
