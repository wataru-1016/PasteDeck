import Foundation
import PasteCore

func runHotkeyShortcutTests(_ t: TestHarness) {
    print("HotkeyShortcut:")

    t.run("デフォルトは ⇧⌘V") { t in
        t.expect(HotkeyShortcut.default.keyCode == 9, "V のキーコード")
        t.expect(HotkeyShortcut.default.modifiers == [.command, .shift], "⇧⌘")
        t.expect(HotkeyShortcut.default.displayString == "⇧⌘V", "表示は ⇧⌘V")
    }

    t.run("修飾キーは ⌃⌥⇧⌘ の順に並ぶ") { t in
        let shortcut = HotkeyShortcut(
            keyCode: 9,
            modifiers: [.command, .shift, .option, .control]
        )
        t.expect(shortcut.displayString == "⌃⌥⇧⌘V", "実際: \(shortcut.displayString)")
    }

    t.run("特殊キーは記号または名前で表示する") { t in
        let cases: [(UInt16, String)] = [
            (49, "⌃⌘Space"),  // Space
            (36, "⌃⌘↩"),  // Return
            (48, "⌃⌘⇥"),  // Tab
            (51, "⌃⌘⌫"),  // Delete
            (53, "⌃⌘⎋"),  // Escape
            (123, "⌃⌘←"),
            (126, "⌃⌘↑"),
            (122, "⌃⌘F1"),
            (111, "⌃⌘F12"),
        ]
        for (keyCode, expected) in cases {
            let shortcut = HotkeyShortcut(keyCode: keyCode, modifiers: [.control, .command])
            t.expect(shortcut.displayString == expected, "\(keyCode): \(shortcut.displayString)")
        }
    }

    t.run("名前を知らないキーコードでも表示は空にならない") { t in
        let shortcut = HotkeyShortcut(keyCode: 999, modifiers: .command)
        t.expect(shortcut.displayString.hasPrefix("⌘"), "修飾キーは表示する")
        t.expect(shortcut.displayString.count > 1, "キー側も何か表示する")
    }

    t.run("⌘ ⌃ ⌥ のいずれかを含む組み合わせは登録できる") { t in
        let valid: [HotkeyShortcut.Modifiers] = [
            .command, .control, .option,
            [.command, .shift], [.control, .option], [.command, .option, .shift],
        ]
        for modifiers in valid {
            t.expect(
                HotkeyShortcut(keyCode: 9, modifiers: modifiers).isValid,
                "rawValue \(modifiers.rawValue) は有効なはず"
            )
        }
    }

    t.run("修飾キーなしと ⇧ のみは登録できない") { t in
        // 通常の文字入力やアプリ内のショートカットを全体で奪ってしまうため
        t.expect(!HotkeyShortcut(keyCode: 9, modifiers: []).isValid, "修飾キーなし")
        t.expect(!HotkeyShortcut(keyCode: 9, modifiers: .shift).isValid, "⇧ のみ")
    }

    t.run("修飾キー自体はキーとして登録できない") { t in
        // ⌘ を押している最中の flagsChanged を組み合わせとして拾わないため
        for keyCode: UInt16 in [54, 55, 56, 57, 58, 59, 60, 61, 62, 63] {
            t.expect(
                !HotkeyShortcut(keyCode: keyCode, modifiers: .command).isValid,
                "キーコード \(keyCode) は無効なはず"
            )
        }
    }

    t.run("英数キーはメニューのキー equivalent に変換できる") { t in
        t.expect(HotkeyShortcut(keyCode: 9, modifiers: .command).menuKeyEquivalent == "v", "V → v")
        t.expect(HotkeyShortcut(keyCode: 18, modifiers: .command).menuKeyEquivalent == "1", "1 → 1")
    }

    t.run("メニューに載せられないキーは nil を返す") { t in
        // NSMenuItem の keyEquivalent は特殊キーごとに固有の文字が要るため、
        // 表示できない組み合わせはメニュー側で何も出さない
        t.expect(HotkeyShortcut(keyCode: 122, modifiers: .command).menuKeyEquivalent == nil, "F1")
        t.expect(HotkeyShortcut(keyCode: 123, modifiers: .command).menuKeyEquivalent == nil, "←")
        t.expect(HotkeyShortcut(keyCode: 999, modifiers: .command).menuKeyEquivalent == nil, "未知のキー")
    }

    t.run("同じ組み合わせは等しい") { t in
        let a = HotkeyShortcut(keyCode: 9, modifiers: [.command, .shift])
        let b = HotkeyShortcut(keyCode: 9, modifiers: [.shift, .command])
        let c = HotkeyShortcut(keyCode: 9, modifiers: .command)
        t.expect(a == b, "修飾キーの指定順は影響しない")
        t.expect(a != c, "修飾キーが違えば別のショートカット")
    }
}
