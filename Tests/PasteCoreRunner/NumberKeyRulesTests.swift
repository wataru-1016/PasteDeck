import Foundation
import PasteCore

func runNumberKeyRulesTests(_ t: TestHarness) {
    print("NumberKeyRules:")

    t.run("数字キーを刻印の順に読む") { t in
        t.expect(NumberKeyRules.index(forKeyCode: 18) == 0, "1 は先頭")
        t.expect(NumberKeyRules.index(forKeyCode: 19) == 1, "2")
        t.expect(NumberKeyRules.index(forKeyCode: 20) == 2, "3")
        t.expect(NumberKeyRules.index(forKeyCode: 21) == 3, "4")
        t.expect(NumberKeyRules.index(forKeyCode: 26) == 6, "7")
        t.expect(NumberKeyRules.index(forKeyCode: 28) == 7, "8")
        t.expect(NumberKeyRules.index(forKeyCode: 25) == 8, "9 は最後")
    }

    t.run("5 と 6 のキーコードの逆転に引きずられない") { t in
        // キーコードは 22 が 6、23 が 5 で並びが入れ替わっている。
        // 昇順に並べた表を作ると 5 と 6 だけ入れ替わり、⌘5 で 6 番目が貼られる
        t.expect(NumberKeyRules.index(forKeyCode: 23) == 4, "23 は 5")
        t.expect(NumberKeyRules.index(forKeyCode: 22) == 5, "22 は 6")
    }

    t.run("数字以外のキーは割り当てない") { t in
        // ここで nil を返さないと、↩ や esc がカードの直接貼り付けに化ける
        t.expect(NumberKeyRules.index(forKeyCode: 36) == nil, "↩")
        t.expect(NumberKeyRules.index(forKeyCode: 53) == nil, "esc")
        t.expect(NumberKeyRules.index(forKeyCode: 29) == nil, "0 は割り当てない")
        t.expect(NumberKeyRules.index(forKeyCode: 0) == nil, "A")
    }

    t.run("キー表記は 1 から数え、割り当ての無い位置では出さない") { t in
        t.expect(NumberKeyRules.quickPasteLabel(forIndex: 0) == "⌘1", "先頭は ⌘1（⌘0 ではない）")
        t.expect(NumberKeyRules.quickPasteLabel(forIndex: 8) == "⌘9", "9 件目は ⌘9")
        // 10 件目以降にも表記を出すと、押しても何も起きないキーを案内することになる
        t.expect(NumberKeyRules.quickPasteLabel(forIndex: 9) == nil, "10 件目には出さない")
        t.expect(NumberKeyRules.quickPasteLabel(forIndex: -1) == nil, "負の位置には出さない")
    }

    t.run("キー表記の範囲と割り当て件数が食い違わない") { t in
        // 件数だけ増やして表記の範囲を直し忘れると、キーはあるのに表記が出ない
        // （またはその逆の）カードができる
        let keyCodes: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
        t.expect(keyCodes.count == NumberKeyRules.quickPasteSlotCount, "件数の分だけキーがある")

        for index in 0..<NumberKeyRules.quickPasteSlotCount {
            t.expect(NumberKeyRules.quickPasteLabel(forIndex: index) != nil, "\(index) 番目に表記がある")
            t.expect(NumberKeyRules.index(forKeyCode: keyCodes[index]) == index, "\(index) 番目にキーがある")
        }
        t.expect(
            NumberKeyRules.quickPasteLabel(forIndex: NumberKeyRules.quickPasteSlotCount) == nil,
            "件数を超えたら表記が無い"
        )
    }
}
