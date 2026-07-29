import Foundation
import PasteCore

func runCaptureRulesTests(_ t: TestHarness) {
    print("CaptureRules:")

    t.run("秘匿マーカー付きのコピーはスキップされる") { t in
        t.expect(
            CaptureRules.shouldSkip(types: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"]),
            "ConcealedType はスキップ対象"
        )
        t.expect(
            CaptureRules.shouldSkip(types: ["org.nspasteboard.TransientType"]),
            "TransientType はスキップ対象"
        )
        t.expect(
            !CaptureRules.shouldSkip(types: ["public.utf8-plain-text", "public.rtf"]),
            "通常のコピーはスキップされない"
        )
    }

    t.run("ファイルコピーは fileList として判定される") { t in
        let kind = CaptureRules.detectKind(text: "/tmp/a.txt", hasImage: false, fileURLCount: 2)
        t.expect(kind == .fileList, "fileURL があれば fileList 優先")
    }

    t.run("単一 URL は link として判定される") { t in
        t.expect(
            CaptureRules.detectKind(text: "https://example.com/path", hasImage: false, fileURLCount: 0) == .link,
            "https URL は link"
        )
        t.expect(
            CaptureRules.detectKind(text: "https://example.com とサイト", hasImage: false, fileURLCount: 0) == .text,
            "文章中の URL は text"
        )
        t.expect(
            CaptureRules.detectKind(text: "example.com", hasImage: false, fileURLCount: 0) == .text,
            "スキームなしは text"
        )
    }

    t.run("画像のみ・空コンテンツの判定") { t in
        t.expect(
            CaptureRules.detectKind(text: nil, hasImage: true, fileURLCount: 0) == .image,
            "画像のみは image"
        )
        t.expect(
            CaptureRules.detectKind(text: "  \n ", hasImage: false, fileURLCount: 0) == nil,
            "空白のみは取り込まない"
        )
    }

    t.run("プレビューはトリムして上限で切り詰める") { t in
        t.expect(CaptureRules.makePreview("  hello  \n") == "hello", "前後の空白を除去")
        let long = String(repeating: "あ", count: 500)
        let preview = CaptureRules.makePreview(long)
        t.expect(preview.count == CaptureRules.previewMaxLength + 1, "上限 + 省略記号の長さ")
        t.expect(preview.hasSuffix("…"), "末尾に省略記号")
    }

    t.run("contentHash は安定していて内容で変わる") { t in
        let flavorsA = ["public.utf8-plain-text": Data("hello".utf8)]
        let flavorsB = ["public.utf8-plain-text": Data("world".utf8)]
        t.expect(
            CaptureRules.contentHash(flavors: flavorsA, fileURLs: []) ==
            CaptureRules.contentHash(flavors: flavorsA, fileURLs: []),
            "同一内容なら同一ハッシュ"
        )
        t.expect(
            CaptureRules.contentHash(flavors: flavorsA, fileURLs: []) !=
            CaptureRules.contentHash(flavors: flavorsB, fileURLs: []),
            "内容が違えばハッシュも違う"
        )
        t.expect(
            CaptureRules.contentHash(flavors: [:], fileURLs: ["file:///a"]) !=
            CaptureRules.contentHash(flavors: [:], fileURLs: ["file:///b"]),
            "fileURL の違いも反映される"
        )
    }
}
