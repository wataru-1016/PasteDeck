import Foundation
import PasteCore

private func makeSearchItem(
    preview: String,
    searchText: String? = nil,
    app: String? = "TestApp"
) -> ClipboardItem {
    ClipboardItem(
        id: UUID(),
        kind: .text,
        preview: preview,
        searchText: searchText,
        charCount: preview.count,
        fileURLs: nil,
        sourceAppName: app,
        sourceAppBundleID: "com.example.test",
        createdAt: Date(timeIntervalSince1970: 1_000_000),
        isPinned: false,
        byteSize: preview.utf8.count,
        contentHash: preview
    )
}

func runSearchTextTests(_ t: TestHarness) {
    print("SearchText:")

    t.run("全角と半角・大文字と小文字をそろえる") { t in
        t.expect(SearchText.normalized("ＭＥＥＴＩＮＧ") == "meeting", "全角英字は半角の小文字になる")
        t.expect(SearchText.normalized("Ｑ３") == "q3", "全角数字も半角になる")
        t.expect(
            SearchText.normalized("ｶﾞｲﾄﾞ") == SearchText.normalized("ガイド"),
            "半角カナは全角カナと同じ扱い（濁点も 1 文字にまとまる）"
        )
    }

    t.run("ひらがなとカタカナを同じものとして扱う") { t in
        // 日本語入力では同じ語をどちらでも打ててしまう。打ち方の違いで
        // 履歴が見つからないようでは検索として使えない
        t.expect(SearchText.normalized("めも") == SearchText.normalized("メモ"), "清音")
        t.expect(SearchText.normalized("ばぐ") == SearchText.normalized("バグ"), "濁音")
        t.expect(SearchText.normalized("ぱん") == SearchText.normalized("パン"), "半濁音")
        t.expect(SearchText.normalized("きゃ") == SearchText.normalized("キャ"), "小書き")
        t.expect(SearchText.normalized("ゔ") == SearchText.normalized("ヴ"), "ひらがなの端（U+3094）")
        // 動かすのはかなの範囲だけ。巻き添えで別の文字が変わっていないこと
        t.expect(SearchText.normalized("設計") == "設計", "漢字はそのまま")
        t.expect(SearchText.normalized("メモ帳") == "メモ帳", "混在しても壊れない")
    }

    t.run("打ち方が違っても検索に当たる") { t in
        let items = [
            makeSearchItem(preview: "打ち合わせメモ"),
            makeSearchItem(preview: "ＭＥＥＴＩＮＧ ｎｏｔｅ"),
        ]
        t.expect(
            SearchFilter.apply(items, query: "めも", pinnedOnly: false).count == 1,
            "ひらがなで打ってカタカナの履歴に当たる"
        )
        t.expect(
            SearchFilter.apply(items, query: "ﾒﾓ", pinnedOnly: false).count == 1,
            "半角カナで打っても当たる"
        )
        t.expect(
            SearchFilter.apply(items, query: "meeting", pinnedOnly: false).count == 1,
            "半角英字で打って全角の履歴に当たる"
        )
        t.expect(
            SearchFilter.apply(items, query: "ｎｏｔｅ", pinnedOnly: false).count == 1,
            "全角で打っても当たる"
        )
    }

    t.run("検索用の本文は preview で足りないときだけ持つ") { t in
        t.expect(CaptureRules.searchText("短いメモ") == nil, "preview に収まるなら持たない")

        let long = String(repeating: "あ", count: CaptureRules.searchTextMaxLength + 500)
        let searchText = CaptureRules.searchText(long)
        t.expect(searchText?.count == CaptureRules.searchTextMaxLength, "上限で切る")
        // preview と違って画面には出さないため、省略記号を足す意味がない
        t.expect(searchText?.hasSuffix("…") == false, "省略記号は付けない")
    }

    t.run("preview に収まらない本文の後半でも検索できる") { t in
        // preview が切れる位置より後ろに目印を置く
        let marker = "リリースノート"
        let body = String(repeating: "あ", count: CaptureRules.previewMaxLength + 100) + marker
        let item = makeSearchItem(
            preview: CaptureRules.makePreview(body),
            searchText: CaptureRules.searchText(body)
        )

        t.expect(!item.preview.contains(marker), "目印は preview には入っていない")
        t.expect(
            SearchFilter.apply([item], query: marker, pinnedOnly: false).count == 1,
            "それでも検索に当たる"
        )
    }

    t.run("searchText を知らなかった頃の履歴も読める") { t in
        // すでに使っている人の items.json にはこのキーが無い。
        // 読めなくなると履歴が丸ごと消えたように見えるため、欠けたまま読めること
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PasteDeckTests-\(UUID().uuidString)", isDirectory: true)
        let persistence = try Persistence(rootURL: root)
        let legacyIndex = """
        {"version":1,"items":[{"byteSize":6,"charCount":2,"contentHash":"abc",\
        "createdAt":776000000,"id":"11111111-2222-3333-4444-555555555555",\
        "isPinned":false,"kind":"text","preview":"メモ","sourceAppName":"Notes"}]}
        """
        try Data(legacyIndex.utf8).write(to: root.appendingPathComponent("items.json"))

        let items = persistence.loadIndex()
        t.expect(items.count == 1, "1 件読める（破損扱いで捨てられない）")
        t.expect(items.first?.searchText == nil, "キーが無ければ nil になる")
        t.expect(
            SearchFilter.apply(items, query: "めも", pinnedOnly: false).count == 1,
            "古い履歴も新しい検索の対象になる"
        )
    }

    t.run("取り込んだ長文がそのまま検索できる") { t in
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PasteDeckTests-\(UUID().uuidString)", isDirectory: true)
        let store = HistoryStore(persistence: try Persistence(rootURL: root))

        let body = String(repeating: "あ", count: CaptureRules.previewMaxLength + 100) + "リリースノート"
        store.ingest(CapturedContent(flavors: [CaptureRules.plainTextType: Data(body.utf8)]))
        store.ingest(CapturedContent(flavors: [CaptureRules.plainTextType: Data("短いメモ".utf8)]))

        t.expect(store.items.count == 2, "2 件取り込まれている")
        t.expect(store.items[0].searchText == nil, "短い方は preview で足りるので持たない")
        t.expect(store.items[1].searchText != nil, "長い方は検索用の本文を持つ")
        // 後半にある語を、ひらがなで打って探す（2 つの直しが噛み合うか）
        t.expect(
            SearchFilter.apply(store.items, query: "りりーすのーと", pinnedOnly: false).count == 1,
            "preview の外にある語をひらがなで探せる"
        )
    }
}
