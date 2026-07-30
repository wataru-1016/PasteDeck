import Foundation
import PasteCore

private func makeTempPersistence() throws -> Persistence {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("PasteDeckTests-\(UUID().uuidString)", isDirectory: true)
    return try Persistence(rootURL: root)
}

/// Excel からのコピー相当。プレーンと装飾（RTF）の両方を持つ
private func decoratedContent(_ text: String) -> CapturedContent {
    CapturedContent(
        flavors: [
            CaptureRules.plainTextType: Data(text.utf8),
            "public.rtf": Data("{\\rtf1 dummy}".utf8),
        ],
        sourceAppName: "Microsoft Excel",
        sourceAppBundleID: "com.microsoft.Excel"
    )
}

private func plainContent(_ text: String) -> CapturedContent {
    CapturedContent(
        flavors: [CaptureRules.plainTextType: Data(text.utf8)],
        sourceAppName: "TestApp"
    )
}

func runTextEditTests(_ t: TestHarness) {
    print("TextEditRules:")

    t.run("編集できるのはテキストとリンクだけ") { t in
        t.expect(TextEditRules.canEdit(kind: .text, byteSize: 100), "テキストは編集できる")
        t.expect(TextEditRules.canEdit(kind: .link, byteSize: 100), "リンクも編集できる")
        t.expect(!TextEditRules.canEdit(kind: .image, byteSize: 100), "画像は対象外")
        t.expect(!TextEditRules.canEdit(kind: .fileList, byteSize: 100), "ファイルは対象外")
    }

    t.run("巨大なテキストは編集画面に載せない") { t in
        t.expect(
            TextEditRules.canEdit(kind: .text, byteSize: TextEditRules.maxEditableBytes),
            "上限ちょうどは編集できる"
        )
        t.expect(
            !TextEditRules.canEdit(kind: .text, byteSize: TextEditRules.maxEditableBytes + 1),
            "上限超過は編集できない"
        )
    }

    t.run("空・空白のみ・変更なしは保存しない") { t in
        t.expect(TextEditRules.shouldSave("あたらしい", original: "もとの"), "変更があれば保存する")
        t.expect(!TextEditRules.shouldSave("同じ", original: "同じ"), "変更なしは保存しない")
        t.expect(!TextEditRules.shouldSave("", original: "もとの"), "空は保存しない")
        t.expect(!TextEditRules.shouldSave(" \n\t ", original: "もとの"), "空白のみは保存しない")
    }

    t.run("装飾 flavor の有無を判定する") { t in
        let plain = [CaptureRules.plainTextType: Data("a".utf8)]
        t.expect(!TextEditRules.discardsDecoration(plain), "プレーンのみなら破棄対象なし")
        t.expect(
            TextEditRules.discardsDecoration(plain.merging(["public.rtf": Data()]) { a, _ in a }),
            "RTF は破棄対象"
        )
        t.expect(
            TextEditRules.discardsDecoration(plain.merging(["public.png": Data()]) { a, _ in a }),
            "画像も破棄対象"
        )
    }

    t.run("編集後の flavor はプレーンのみ") { t in
        let flavors = TextEditRules.flavors(forEditedText: "こんにちは")
        t.expect(flavors.count == 1, "flavor は 1 つだけ")
        let data = try t.require(flavors[CaptureRules.plainTextType], "プレーンが入っている")
        t.expect(String(data: data, encoding: .utf8) == "こんにちは", "内容が一致する")
    }

    print("HistoryStore.replaceText:")

    t.run("編集すると派生値がすべて引き直される") { t in
        let store = HistoryStore(persistence: try makeTempPersistence())
        store.ingest(decoratedContent("もとのテキスト"))
        let original = try t.require(store.items.first, "取り込まれる")

        store.replaceText("あたらしいテキスト", for: original.id)
        let edited = try t.require(store.items.first, "アイテムが残る")

        t.expect(store.items.count == 1, "件数は増えない")
        t.expect(edited.id == original.id, "同じアイテムを書き換える")
        t.expect(edited.preview == "あたらしいテキスト", "preview が更新される")
        t.expect(edited.charCount == 9, "文字数が更新される")
        t.expect(edited.contentHash != original.contentHash, "ハッシュが引き直される")
        t.expect(
            edited.byteSize == Data("あたらしいテキスト".utf8).count,
            "バイト数が編集後のプレーンだけになる"
        )
        t.expect(edited.sourceAppName == "Microsoft Excel", "コピー元アプリは保持する")
    }

    t.run("編集すると装飾の flavor が破棄される") { t in
        let store = HistoryStore(persistence: try makeTempPersistence())
        store.ingest(decoratedContent("もとのテキスト"))
        let id = try t.require(store.items.first?.id, "取り込まれる")
        t.expect(store.flavors(for: id)?["public.rtf"] != nil, "編集前は RTF を持つ")

        store.replaceText("あたらしいテキスト", for: id)
        let flavors = try t.require(store.flavors(for: id), "flavor が読める")

        t.expect(flavors.count == 1, "プレーンのみになる")
        t.expect(flavors["public.rtf"] == nil, "RTF は破棄される")
        let saved = try t.require(flavors[CaptureRules.plainTextType], "プレーンがある")
        t.expect(
            String(data: saved, encoding: .utf8) == "あたらしいテキスト",
            "保存された本文が編集後のもの"
        )
    }

    t.run("URL を編集して URL でなくなると種別が変わる") { t in
        let store = HistoryStore(persistence: try makeTempPersistence())
        store.ingest(plainContent("https://example.com"))
        let id = try t.require(store.items.first?.id, "取り込まれる")
        t.expect(store.items[0].kind == .link, "取り込み時は link")

        store.replaceText("ただのテキストになった", for: id)
        t.expect(store.items[0].kind == .text, "編集後は text")
    }

    t.run("ピン留めと並び順は編集後も変わらない") { t in
        let store = HistoryStore(persistence: try makeTempPersistence())
        store.ingest(plainContent("ふるい"))
        store.ingest(plainContent("あたらしい"))
        let target = store.items[1]
        store.togglePin(target.id)

        store.replaceText("編集した", for: target.id)

        t.expect(store.items[1].id == target.id, "並び順は変わらない")
        t.expect(store.items[1].isPinned, "ピン状態を保持する")
        t.expect(store.items[1].preview == "編集した", "内容は更新される")
        t.expect(store.items[1].createdAt == target.createdAt, "コピー時刻は変えない")
    }

    t.run("画像アイテムは編集しても変化しない") { t in
        let store = HistoryStore(persistence: try makeTempPersistence())
        store.ingest(CapturedContent(
            flavors: ["public.png": Data([0x89, 0x50, 0x4E, 0x47])],
            imageSizeLabel: "10 × 10"
        ))
        let original = try t.require(store.items.first, "取り込まれる")
        t.expect(original.kind == .image, "kind は image")

        store.replaceText("テキストに置き換えたい", for: original.id)

        t.expect(store.items[0] == original, "アイテムは変化しない")
        t.expect(store.flavors(for: original.id)?["public.png"] != nil, "画像データが残る")
    }

    t.run("存在しない ID の編集は何もしない") { t in
        let store = HistoryStore(persistence: try makeTempPersistence())
        store.ingest(plainContent("もとの"))
        store.replaceText("あたらしい", for: UUID())
        t.expect(store.items.count == 1, "件数は変わらない")
        t.expect(store.items[0].preview == "もとの", "内容も変わらない")
    }
}
