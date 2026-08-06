import AppKit
import PasteCore
import UniformTypeIdentifiers

/// カードを Finder などへドラッグして書き出す。
///
/// SwiftUI の `.onDrag`（`NSItemProvider`）ではなく AppKit のドラッグセッションを使う。
/// `.onDrag` が運べるのは 1 件だけで、複数のファイルをまとめてコピーした履歴では
/// 残りを黙って取りこぼすため。セッションなら、コピーしたときと同じ一式をそのまま渡せる。
///
/// 渡すものの作り方は貼り付け（`PasteService`）と揃える。画像を一度ファイルに書き出すのも
/// ⇧↩ と同じ `ImageFileExporter` の経路で、書き出し先も使い回す
final class CardDragSession: NSObject, NSDraggingSource {
    /// ドラッグ中に指に付いてくるアイコンの大きさ
    private static let iconSize = NSSize(width: 64, height: 64)
    /// 複数のファイルを重ねずに少しずつずらして持つための間隔
    private static let iconOffset: CGFloat = 12

    /// ドラッグが終わったときに呼ぶ。引数はどこかに置かれたかどうか
    private let onEnd: (_ didDrop: Bool) -> Void

    private init(onEnd: @escaping (_ didDrop: Bool) -> Void) {
        self.onEnd = onEnd
    }

    /// ドラッグを開始する。渡せるものが無ければ nil を返す（呼び出し側は何もしない）。
    /// 返したセッションは終わるまで呼び出し側で保持すること
    static func begin(
        item: ClipboardItem,
        store: HistoryStore,
        onEnd: @escaping (_ didDrop: Bool) -> Void
    ) -> CardDragSession? {
        // ドラッグは押したまま動かしている最中にしか始められない。イベントの種類を
        // 確かめるのは、ドラッグが終わったあとに残っている古いイベントで
        // 二度目のセッションを始めてしまわないためでもある
        guard let event = NSApp.currentEvent,
              event.type == .leftMouseDragged || event.type == .leftMouseDown,
              let view = event.window?.contentView
        else { return nil }

        let writers = pasteboardWriters(for: item, store: store)
        guard !writers.isEmpty else { return nil }

        let session = CardDragSession(onEnd: onEnd)
        view.beginDraggingSession(
            with: draggingItems(for: writers, at: view.convert(event.locationInWindow, from: nil)),
            event: event,
            source: session
        )
        return session
    }

    // MARK: - NSDraggingSource

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        // 履歴が持っているのは元ファイルの場所だけなので、移動（move）は許さない。
        // 許すと、履歴から取り出したつもりで元のファイルが動いてしまう
        .copy
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        // 途中で放した（どこにも置かなかった）場合は履歴に触れさせない
        onEnd(!operation.isEmpty)
    }

    // MARK: - 渡すものの組み立て

    /// ドラッグで渡すもの。渡せるものが無ければ空を返す
    private static func pasteboardWriters(
        for item: ClipboardItem,
        store: HistoryStore
    ) -> [NSPasteboardWriting] {
        switch item.kind {
        case .fileList:
            // 元ファイルは PasteDeck の外で移動・削除されうる。無いものを渡しても
            // 置いた先で失敗するだけなので、まだ在るものだけを渡す
            let urls = (item.fileURLs ?? []).compactMap { URL(string: $0) }
            return FileLinkRules.existing(urls).map { $0 as NSURL }

        case .image:
            // 画像はデータのままでは Finder が受け取れない（受け取るのは file-url だけ）。
            // ⇧↩ と同じ経路で一度ファイルにしてから渡す。
            // 書き出しはここで同期に行う。⇧↩ の貼り付けと同じ扱いで、ドラッグを
            // 始めた時点で実体が無いと、置いた先が受け取るものを用意できないため
            guard let png = store.flavors(for: item.id)?[CaptureRules.pngType],
                  let url = ImageFileExporter.write(png: png, item: item)
            else { return [] }
            return [url as NSURL]

        case .link:
            // URL として渡す。Finder では .webloc になり、ブラウザではリンクとして届く
            if let url = URL(string: item.preview), url.scheme != nil {
                return [url as NSURL]
            }
            return textWriters(for: item, store: store)

        case .text:
            return textWriters(for: item, store: store)
        }
    }

    /// 文字として渡す。Finder に置くとテキストクリッピングになる。
    ///
    /// 書式（RTF・HTML）を持っているものはまとめて渡す。↩ の貼り付けと同じ中身にするためで、
    /// ドラッグしたときだけ書式が落ちるのでは、どちらを使ったかで結果が変わってしまう。
    /// flavor が読めなければ、せめてカードに出ている文字を渡す
    private static func textWriters(
        for item: ClipboardItem,
        store: HistoryStore
    ) -> [NSPasteboardWriting] {
        let flavors = (store.flavors(for: item.id) ?? [:]).filter { !$0.value.isEmpty }
        guard !flavors.isEmpty else {
            return item.preview.isEmpty ? [] : [item.preview as NSString]
        }

        let pasteboardItem = NSPasteboardItem()
        for (type, data) in flavors {
            pasteboardItem.setData(data, forType: NSPasteboard.PasteboardType(type))
        }
        return [pasteboardItem]
    }

    private static func draggingItems(
        for writers: [NSPasteboardWriting],
        at origin: NSPoint
    ) -> [NSDraggingItem] {
        writers.enumerated().map { offset, writer in
            let draggingItem = NSDraggingItem(pasteboardWriter: writer)
            let shift = CGFloat(offset) * iconOffset
            draggingItem.setDraggingFrame(
                NSRect(
                    x: origin.x - iconSize.width / 2 + shift,
                    y: origin.y - iconSize.height / 2 - shift,
                    width: iconSize.width,
                    height: iconSize.height
                ),
                contents: icon(for: writer)
            )
            return draggingItem
        }
    }

    /// ドラッグ中に出す絵。実体のあるファイルは Finder と同じアイコンにして、
    /// 何を運んでいるのかが手元で分かるようにする
    private static func icon(for writer: NSPasteboardWriting) -> NSImage {
        guard let url = writer as? NSURL else {
            return NSWorkspace.shared.icon(for: .plainText)
        }
        guard url.isFileURL, let path = url.path else {
            return NSWorkspace.shared.icon(for: .url)
        }
        return NSWorkspace.shared.icon(forFile: path)
    }
}
