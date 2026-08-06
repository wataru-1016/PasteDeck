import Foundation

/// 数字キー（1〜9）の割り当て（純粋関数のみ・テスト対象）
public enum NumberKeyRules {
    /// ⌘1〜⌘9 で直接貼り付けられる件数。
    ///
    /// ⌘0 を足して 10 件にはしない。カードに「⌘0」と出ていても、それが
    /// 「0 番目」なのか「10 番目」なのかは表記だけでは決まらない
    public static let quickPasteSlotCount = 9

    /// 数字キー 1〜9 のキーコードを、数字の並び順で持ったもの。
    /// 5 と 6 だけキーコードが逆転している（5 が 23、6 が 22）
    private static let keyCodes: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]

    /// 押された数字キーが指す位置（0 始まり）。数字キーでなければ nil。
    /// 画像編集の道具切り替え（1〜8）とパネルの直接貼り付け（⌘1〜⌘9）で共有する
    public static func index(forKeyCode keyCode: UInt16) -> Int? {
        keyCodes.firstIndex(of: keyCode)
    }

    /// カードに出すキー表記。割り当ての無い位置では nil。
    /// どのカードがどのキーに対応するかを、押す前に見て分かるようにするためのもの
    public static func quickPasteLabel(forIndex index: Int) -> String? {
        guard index >= 0, index < quickPasteSlotCount else { return nil }
        return "⌘\(index + 1)"
    }
}
