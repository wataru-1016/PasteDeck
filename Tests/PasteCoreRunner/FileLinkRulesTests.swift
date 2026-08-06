import Foundation
import PasteCore

func runFileLinkRulesTests(_ t: TestHarness) {
    print("FileLinkRules:")

    t.run("いくつ見つからないかで状態が決まる") { t in
        t.expect(FileLinkRules.status(total: 3, missing: 0) == .available, "全部そろっている")
        t.expect(
            FileLinkRules.status(total: 3, missing: 1) == .partiallyMissing(missing: 1),
            "一部だけ見つからない"
        )
        t.expect(FileLinkRules.status(total: 3, missing: 3) == .missing, "全部見つからない")
        t.expect(FileLinkRules.status(total: 1, missing: 1) == .missing, "1 件だけの履歴でも同じ")
        // ファイルを持たない履歴にまで警告を出すと、ただの誤報になる
        t.expect(FileLinkRules.status(total: 0, missing: 0) == .available, "ファイルが無い履歴は警告しない")
    }

    t.run("実際のファイルの有無を見て判定する") { t in
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PasteDeckTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        // Finder からコピーしたファイル名には空白も日本語も入る。履歴には
        // percent エンコードされた URL 文字列で入っているため、そこから
        // 復元したパスで正しく見つけられること
        let spaced = root.appendingPathComponent("Report Final.pdf")
        let japanese = root.appendingPathComponent("議事録 2026.txt")
        try Data("a".utf8).write(to: spaced)
        try Data("b".utf8).write(to: japanese)
        let gone = root.appendingPathComponent("deleted.txt")

        let restored = [spaced, japanese, gone]
            .compactMap { URL(string: $0.absoluteString) }
        t.expect(restored.count == 3, "URL 文字列から復元できる")

        t.expect(FileLinkRules.existing(restored) == [spaced, japanese], "在るものだけ残る")
        t.expect(
            FileLinkRules.status(of: restored) == .partiallyMissing(missing: 1),
            "消えた 1 件を数える"
        )
        t.expect(FileLinkRules.status(of: [gone]) == .missing, "全部消えていれば missing")
        t.expect(FileLinkRules.status(of: [spaced, japanese]) == .available, "そろっていれば available")

        try? FileManager.default.removeItem(at: root)
    }

    t.run("注意書きは問題があるときだけ出す") { t in
        t.expect(FileLinkRules.warning(for: .available) == nil, "問題なければ何も出さない")
        t.expect(
            FileLinkRules.warning(for: .missing) == "元ファイルが見つかりません",
            "全部消えていることが分かる文言"
        )
        // 残っている分は貼れるため、全滅と同じ言い方にはしない
        t.expect(
            FileLinkRules.warning(for: .partiallyMissing(missing: 2)) == "2 件の元ファイルが見つかりません",
            "何件消えたかを出す"
        )
    }
}
