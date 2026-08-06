import Foundation
import PasteCore

/// 履歴の画像を一時ファイルへ書き出し、ファイルとして貼り付けられるようにする。
///
/// クリップボードに画像データを載せても Finder はファイルを作れない（受け取るのは
/// file-url だけ）。⇧↩ のときだけここで実体を作り、その URL を渡す
enum ImageFileExporter {
    /// 書き出して URL を返す。失敗したら nil（呼び出し側は通常の貼り付けへ落とす）
    ///
    /// アイテムごとにディレクトリを掘るのは、名前を日時から作るため別のアイテムと
    /// 衝突しうるから。同じアイテムなら常に同じ場所を使うので、貼り直しても増えない
    static func write(png: Data, item: ClipboardItem) -> URL? {
        let manager = FileManager.default
        let root = manager.temporaryDirectory
            .appendingPathComponent(PasteRules.exportDirectoryName, isDirectory: true)
        let directory = root.appendingPathComponent(item.id.uuidString, isDirectory: true)
        let url = directory.appendingPathComponent(
            PasteRules.imageFileName(createdAt: item.createdAt)
        )

        do {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            // 既にあっても書き直す。⌘E の上書き保存では ID も日時も変えずに中身だけが
            // 差し替わるため、前回の書き出しを使い回すと古い画像を貼ってしまう
            try png.write(to: url, options: .atomic)
        } catch {
            Log.error("画像をファイルに書き出せませんでした: \(error)")
            return nil
        }

        sweepExpired(in: root, keeping: directory.lastPathComponent)
        return url
    }

    /// 古い書き出しを片付ける。
    /// 溜め続けると一時領域を圧迫するが、貼った直後のものを消すと貼り先が読む前に消える
    private static func sweepExpired(in root: URL, keeping name: String, now: Date = Date()) {
        let manager = FileManager.default
        guard let entries = try? manager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for entry in entries where entry.lastPathComponent != name {
            let modified = (try? entry.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate
            guard let modified,
                  PasteRules.isExpiredExport(modifiedAt: modified, now: now)
            else { continue }
            try? manager.removeItem(at: entry)
        }
    }
}
