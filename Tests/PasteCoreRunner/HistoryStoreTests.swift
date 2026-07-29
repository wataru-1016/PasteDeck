import Foundation
import PasteCore

private func makeTempPersistence() throws -> Persistence {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("PasteDeckTests-\(UUID().uuidString)", isDirectory: true)
    return try Persistence(rootURL: root)
}

private func textContent(_ text: String, app: String? = "TestApp") -> CapturedContent {
    CapturedContent(
        flavors: [CaptureRules.plainTextType: Data(text.utf8)],
        sourceAppName: app,
        sourceAppBundleID: "com.example.test"
    )
}

func runHistoryStoreTests(_ t: TestHarness) {
    print("HistoryStore:")

    t.run("取り込んだアイテムは先頭に追加される") { t in
        let store = HistoryStore(persistence: try makeTempPersistence())
        store.ingest(textContent("hello"))
        store.ingest(textContent("world"))
        t.expect(store.items.count == 2, "2 件登録される")
        t.expect(store.items[0].preview == "world", "新しい方が先頭")
        t.expect(store.items[0].kind == .text, "kind は text")
        t.expect(store.items[0].charCount == 5, "文字数が記録される")
    }

    t.run("同一内容の再コピーは先頭へ移動し ID とピンを保持する") { t in
        let store = HistoryStore(persistence: try makeTempPersistence())
        store.ingest(textContent("first"))
        store.ingest(textContent("second"))
        let original = store.items[1]
        store.togglePin(original.id)

        store.ingest(textContent("first"))
        t.expect(store.items.count == 2, "重複は増えない")
        t.expect(store.items[0].id == original.id, "既存アイテムの ID を保持")
        t.expect(store.items[0].isPinned, "ピン状態を保持")
    }

    t.run("上限超過時はピン留め以外の最古アイテムから削除される") { t in
        let store = HistoryStore(
            persistence: try makeTempPersistence(),
            policy: RetentionPolicy(maxItems: 3, maxAge: nil)
        )
        store.ingest(textContent("one"))
        store.togglePin(store.items[0].id)
        store.ingest(textContent("two"))
        store.ingest(textContent("three"))
        store.ingest(textContent("four"))

        t.expect(store.items.count == 3, "上限でトリムされる")
        let previews = store.items.map(\.preview)
        t.expect(previews.contains("one"), "ピン留めは残る")
        t.expect(!previews.contains("two"), "最古の未ピンが消える")
        t.expect(previews.contains("three") && previews.contains("four"), "新しいものは残る")
    }

    t.run("削除でアイテムと実データが消える") { t in
        let store = HistoryStore(persistence: try makeTempPersistence())
        store.ingest(textContent("to delete"))
        let id = try t.require(store.items.first?.id, "アイテムが存在する")
        t.expect(store.flavors(for: id) != nil, "実データが保存されている")

        store.delete(id)
        t.expect(store.items.isEmpty, "アイテムが消える")
        t.expect(store.flavors(for: id) == nil, "実データも消える")
    }

    t.run("未ピン消去はピン留めを残す") { t in
        let store = HistoryStore(persistence: try makeTempPersistence())
        store.ingest(textContent("keep"))
        store.togglePin(try t.require(store.items.first?.id, "keep が存在"))
        store.ingest(textContent("discard"))

        store.clearUnpinned()
        t.expect(store.items.map(\.preview) == ["keep"], "ピン留めのみ残る")
    }

    t.run("履歴はストアを作り直しても復元される") { t in
        let persistence = try makeTempPersistence()
        let store1 = HistoryStore(persistence: persistence)
        store1.ingest(textContent("persisted"))
        store1.togglePin(try t.require(store1.items.first?.id, "アイテムが存在"))

        let store2 = HistoryStore(persistence: persistence)
        t.expect(store2.items == store1.items, "インデックスが一致する")
        let id = try t.require(store2.items.first?.id, "復元後のアイテム")
        t.expect(store2.flavors(for: id) != nil, "実データも読める")
    }

    t.run("リンクと画像の取り込み") { t in
        let store = HistoryStore(persistence: try makeTempPersistence())
        store.ingest(textContent("https://example.com"))
        t.expect(store.items[0].kind == .link, "URL は link")

        let imageContent = CapturedContent(
            flavors: ["public.png": Data([0x89, 0x50, 0x4E, 0x47])],
            imageSizeLabel: "10 × 10"
        )
        store.ingest(imageContent)
        t.expect(store.items[0].kind == .image, "画像は image")
        t.expect(store.items[0].preview == "画像 10 × 10", "サイズラベル付きプレビュー")
    }

    t.run("moveToFront で並び替えられる") { t in
        let store = HistoryStore(persistence: try makeTempPersistence())
        store.ingest(textContent("a"))
        store.ingest(textContent("b"))
        let last = try t.require(store.items.last, "末尾アイテム")

        store.moveToFront(last.id)
        t.expect(store.items[0].id == last.id, "先頭へ移動する")
    }

    t.run("保持期間を過ぎた未ピンアイテムは削除される") { t in
        let store = HistoryStore(persistence: try makeTempPersistence())
        let oldDate = Date(timeIntervalSinceNow: -3600)
        store.ingest(textContent("expired"), at: oldDate)
        store.ingest(textContent("old but pinned"), at: oldDate)
        store.togglePin(try t.require(store.items.first?.id, "ピン対象が存在"))
        store.ingest(textContent("fresh"))
        let expiredID = try t.require(store.items.last?.id, "期限切れ対象が存在")

        store.updatePolicy(RetentionPolicy(maxItems: nil, maxAge: 1800))
        let previews = store.items.map(\.preview)
        t.expect(!previews.contains("expired"), "期限切れの未ピンは消える")
        t.expect(previews.contains("old but pinned"), "期限切れでもピン留めは残る")
        t.expect(previews.contains("fresh"), "期限内は残る")
        t.expect(store.flavors(for: expiredID) == nil, "期限切れの実データも消える")
    }

    t.run("件数無制限にすると上限トリムされない") { t in
        let store = HistoryStore(
            persistence: try makeTempPersistence(),
            policy: RetentionPolicy(maxItems: 2, maxAge: nil)
        )
        store.ingest(textContent("one"))
        store.ingest(textContent("two"))
        store.ingest(textContent("three"))
        t.expect(store.items.count == 2, "上限 2 でトリムされる")

        store.updatePolicy(RetentionPolicy(maxItems: nil, maxAge: nil))
        store.ingest(textContent("four"))
        store.ingest(textContent("five"))
        t.expect(store.items.count == 4, "無制限なら増え続ける")
    }

    t.run("起動時にも保持ポリシーが適用される") { t in
        let persistence = try makeTempPersistence()
        let store1 = HistoryStore(persistence: persistence)
        store1.ingest(textContent("stale"), at: Date(timeIntervalSinceNow: -3600))
        store1.ingest(textContent("recent"))

        let store2 = HistoryStore(
            persistence: persistence,
            policy: RetentionPolicy(maxItems: nil, maxAge: 1800)
        )
        t.expect(store2.items.map(\.preview) == ["recent"], "期限切れは起動時に整理される")
    }
}
