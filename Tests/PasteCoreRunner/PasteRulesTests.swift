import Foundation
import PasteCore

func runPasteRulesTests(_ t: TestHarness) {
    print("PasteRules:")

    t.run("⇧↩ の意味は種別で変わる") { t in
        // 画像を「文字だけ」にしても何も残らない。プレーン化はテキストにしか意味がない
        t.expect(PasteRules.alternatePaste(for: .text) == .plainText, "テキストは書式を捨てる")
        t.expect(PasteRules.alternatePaste(for: .link) == .plainText, "リンクも書式を捨てる")
        // 画像はデータのままでは Finder に貼れないため、ファイルに書き出して渡す
        t.expect(PasteRules.alternatePaste(for: .image) == .file, "画像はファイルとして貼る")
        // ファイル履歴は ↩ でも file-url を渡すので、⇧↩ でも同じ結果になる
        t.expect(PasteRules.alternatePaste(for: .fileList) == .file, "ファイルはそのままファイル")
    }

    t.run("書き出す画像の名前はコピーした日時から作る") { t in
        // 端末の暦や言語が変わっても同じ名前でなければならない。
        // 和暦の設定で "PasteDeck R8-08-06…" のような名前が混ざると、
        // 並べたときに時系列が読めなくなる
        var calendar = Calendar(identifier: .gregorian)
        let zone = TimeZone(secondsFromGMT: 9 * 3600)!
        calendar.timeZone = zone
        let date = calendar.date(
            from: DateComponents(year: 2026, month: 8, day: 6, hour: 12, minute: 34, second: 56)
        )!

        let name = PasteRules.imageFileName(createdAt: date, timeZone: zone)
        t.expect(name == "PasteDeck 2026-08-06 12.34.56.png", "実際の名前: \(name)")
        // ":" は Finder では "/" として表示され、パスの区切りと紛らわしくなる
        t.expect(!name.contains(":"), "時刻の区切りに : を使わない")
    }

    t.run("古い書き出しだけを片付ける") { t in
        let now = Date()
        // 貼った直後のファイルを消すと、貼り先が読む前に消えて貼り付けが失敗する
        t.expect(
            !PasteRules.isExpiredExport(modifiedAt: now, now: now),
            "書き出した直後は残す"
        )
        t.expect(
            !PasteRules.isExpiredExport(
                modifiedAt: now.addingTimeInterval(-PasteRules.exportLifetime + 60),
                now: now
            ),
            "保持時間の内側は残す"
        )
        t.expect(
            PasteRules.isExpiredExport(
                modifiedAt: now.addingTimeInterval(-PasteRules.exportLifetime - 60),
                now: now
            ),
            "保持時間を過ぎたら消す"
        )
    }
}
