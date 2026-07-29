import Foundation
import PasteCore

private func makeTempRoot() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("PasteDeckTests-\(UUID().uuidString)", isDirectory: true)
}

private func makeItem(
    preview: String,
    kind: ItemKind = .text,
    app: String? = "TestApp",
    fileURLs: [String]? = nil,
    isPinned: Bool = false
) -> ClipboardItem {
    ClipboardItem(
        id: UUID(),
        kind: kind,
        preview: preview,
        charCount: preview.count,
        fileURLs: fileURLs,
        sourceAppName: app,
        sourceAppBundleID: "com.example.test",
        createdAt: Date(timeIntervalSince1970: 1_000_000),
        isPinned: isPinned,
        byteSize: preview.utf8.count,
        contentHash: preview
    )
}

func runPersistenceTests(_ t: TestHarness) {
    print("Persistence:")

    t.run("インデックスの保存と復元") { t in
        let persistence = try Persistence(rootURL: makeTempRoot())
        let items = [makeItem(preview: "alpha"), makeItem(preview: "beta", isPinned: true)]
        try persistence.saveIndex(items)
        t.expect(persistence.loadIndex() == items, "ラウンドトリップで一致する")
    }

    t.run("壊れたインデックスは退避して空で返す") { t in
        let root = makeTempRoot()
        let persistence = try Persistence(rootURL: root)
        try Data("not json".utf8).write(to: root.appendingPathComponent("items.json"))

        t.expect(persistence.loadIndex() == [], "空配列を返す")
        t.expect(
            FileManager.default.fileExists(atPath: root.appendingPathComponent("items.corrupt.json").path),
            "破損ファイルが退避される"
        )
    }

    t.run("実データ（flavors）の保存と復元") { t in
        let persistence = try Persistence(rootURL: makeTempRoot())
        let id = UUID()
        let flavors = [
            "public.utf8-plain-text": Data("text".utf8),
            "public.rtf": Data([0x01, 0x02]),
        ]
        try persistence.saveFlavors(flavors, id: id)
        t.expect(persistence.loadFlavors(id: id) == flavors, "ラウンドトリップで一致する")

        persistence.deleteFlavors(id: id)
        t.expect(persistence.loadFlavors(id: id) == nil, "削除後は読めない")
    }

    t.run("孤児データの掃除") { t in
        let persistence = try Persistence(rootURL: makeTempRoot())
        let keep = UUID()
        let orphan = UUID()
        try persistence.saveFlavors(["public.utf8-plain-text": Data("a".utf8)], id: keep)
        try persistence.saveFlavors(["public.utf8-plain-text": Data("b".utf8)], id: orphan)

        persistence.pruneFlavors(keeping: [keep])
        t.expect(persistence.loadFlavors(id: keep) != nil, "残すべきものは残る")
        t.expect(persistence.loadFlavors(id: orphan) == nil, "孤児は消える")
    }
}

func runSearchFilterTests(_ t: TestHarness) {
    print("SearchFilter:")

    t.run("全トークン一致・大文字小文字無視") { t in
        let items = [
            makeItem(preview: "Meeting notes for Q3 planning"),
            makeItem(preview: "grocery list", app: "Notes"),
            makeItem(preview: "設計メモ", app: "CotEditor"),
        ]
        t.expect(SearchFilter.apply(items, query: "meeting q3", pinnedOnly: false).count == 1, "AND 検索")
        t.expect(SearchFilter.apply(items, query: "notes", pinnedOnly: false).count == 2, "アプリ名にも一致")
        t.expect(SearchFilter.apply(items, query: "設計", pinnedOnly: false).count == 1, "日本語にも一致")
        t.expect(SearchFilter.apply(items, query: "", pinnedOnly: false).count == 3, "空クエリは全件")
        t.expect(SearchFilter.apply(items, query: "missing", pinnedOnly: false).isEmpty, "不一致は 0 件")
    }

    t.run("ファイル名検索とピン留めフィルター") { t in
        let fileItem = makeItem(
            preview: "report.pdf",
            kind: .fileList,
            fileURLs: ["file:///Users/test/Documents/Report%20Final.pdf"]
        )
        let pinned = makeItem(preview: "pinned note", isPinned: true)
        let items = [fileItem, pinned]

        t.expect(SearchFilter.apply(items, query: "final", pinnedOnly: false).count == 1, "デコード済みファイル名に一致")
        t.expect(SearchFilter.apply(items, query: "", pinnedOnly: true) == [pinned], "ピン留めのみ")
    }
}
