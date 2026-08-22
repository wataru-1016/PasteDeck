import Foundation
import PasteCore

func runHotkeyActionTests(_ t: TestHarness) {
    print("HotkeyAction:")

    t.run("carbonID は一意で 0 を使わない") { t in
        // 同じ ID を 2 つの action に振ると、押されたキーを取り違えて
        // ⇧⌘7 で履歴パネルが開く。0 は未設定と紛らわしいので避ける
        let ids = HotkeyAction.allCases.map(\.carbonID)
        t.expect(Set(ids).count == ids.count, "重複が無い: \(ids)")
        t.expect(!ids.contains(0), "0 を含まない: \(ids)")
    }

    t.run("押されたキーの carbonID から action を逆引きできる") { t in
        t.expect(HotkeyAction.action(forCarbonID: 1) == .panel, "1 は履歴パネル")
        t.expect(HotkeyAction.action(forCarbonID: 2) == .ocr, "2 は画面読み取り")
    }

    t.run("知らない carbonID は nil にする") { t in
        // 他アプリのホットキーを取り違えて処理しないため
        t.expect(HotkeyAction.action(forCarbonID: 0) == nil, "0")
        t.expect(HotkeyAction.action(forCarbonID: 99) == nil, "99")
    }

    t.run("既定のキーは統合前の 2 アプリと同じ組み合わせ") { t in
        // 既定値が変わると、統合しただけで指が覚えたキーが効かなくなる
        t.expect(HotkeyAction.panel.defaultShortcut == .default, "履歴パネルは ⇧⌘V")
        t.expect(HotkeyAction.panel.defaultShortcut.displayString == "⇧⌘V", "⇧⌘V の表示")
        t.expect(HotkeyAction.ocr.defaultShortcut.displayString == "⇧⌘7", "⇧⌘7 の表示")
    }

    t.run("既定のキーはグローバルホットキーとして登録できる") { t in
        // isValid でない組み合わせを既定にすると、初回起動でホットキーが 1 つも効かない
        for action in HotkeyAction.allCases {
            t.expect(action.defaultShortcut.isValid, "\(action.rawValue) の既定キーが有効")
        }
    }

    t.run("既定のキーは互いに衝突しない") { t in
        // 同じ組み合わせを既定にすると、初回起動で片方の登録が必ず失敗する
        let shortcuts = HotkeyAction.allCases.map(\.defaultShortcut)
        for (index, shortcut) in shortcuts.enumerated() {
            for other in shortcuts[(index + 1)...] {
                t.expect(shortcut != other, "\(shortcut.displayString) が重複していない")
            }
        }
    }

    t.run("rawValue が変わると保存済みのキー設定が読めなくなる") { t in
        // UserDefaults のキーを "hotkey.<rawValue>.keyCode" で作るため
        t.expect(HotkeyAction.panel.rawValue == "panel", "panel")
        t.expect(HotkeyAction.ocr.rawValue == "ocr", "ocr")
    }

    t.run("表示名は設定画面の行見出しと重複エラーの文面に使う") { t in
        for action in HotkeyAction.allCases {
            t.expect(!action.displayName.isEmpty, "\(action.rawValue) に名前がある")
        }
        t.expect(HotkeyAction.panel.displayName == "履歴パネル", "履歴パネル")
        t.expect(HotkeyAction.ocr.displayName == "画面読み取り", "画面読み取り")
    }
}
