import Foundation

/// ⇧↩ で貼るときの貼り方。↩ との違いは種別によって変わる
public enum AlternatePaste: String, Equatable, Sendable {
    /// 書式を捨てて文字だけにする
    case plainText
    /// 一時ファイルへ書き出し、ファイルとして渡す
    case file
}

/// 貼り付け方の判定（純粋関数のみ・テスト対象）
public enum PasteRules {
    /// 書き出した画像を溜めておく場所の名前。一時領域の直下は他と混ざるため 1 段掘る
    public static let exportDirectoryName = "PasteDeck"

    /// 書き出したファイルを残す時間。
    /// ⌘V の直後に貼り先がコピーし終わるので本来は数秒で足りるが、
    /// あとから読むアプリ（アップロード中のチャットなど）の途中で消さないよう 1 日残す
    public static let exportLifetime: TimeInterval = 24 * 60 * 60

    /// ⇧↩ の意味。
    ///
    /// 画像はクリップボードに「データ」としてしか載らず、Finder が受け取るのは
    /// ファイル（file-url）だけなので、そのままでは Finder に貼れない。
    /// 一方で書式を捨てるプレーン化は画像には意味がないため、⇧↩ の役割を種別で振り分ける
    public static func alternatePaste(for kind: ItemKind) -> AlternatePaste {
        switch kind {
        case .text, .link:
            return .plainText
        // ファイル履歴は ↩ でもファイルとして貼るので、⇧↩ でも結果は変わらない。
        // それでもここに含めるのは、ヒント表示（⇧↩ ファイル）が嘘にならないようにするため
        case .image, .fileList:
            return .file
        }
    }

    /// 書き出す画像のファイル名。
    /// Finder に貼るとこの名前がそのまま見えるため、ID ではなくコピーした日時から作る
    public static func imageFileName(createdAt: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        // 端末の暦や言語で名前が変わらないよう固定する
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        // 時刻の区切りに ":" は使えない（Finder では "/" として表示される）
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return "PasteDeck \(formatter.string(from: createdAt)).png"
    }

    /// 書き出したファイルを消してよいか
    public static func isExpiredExport(modifiedAt: Date, now: Date) -> Bool {
        now.timeIntervalSince(modifiedAt) > exportLifetime
    }
}
