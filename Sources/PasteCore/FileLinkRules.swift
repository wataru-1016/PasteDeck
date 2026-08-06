import Foundation

/// ファイル履歴が指す実体がまだ在るか。
/// 元ファイルは PasteDeck の外で移動・削除されうるため、履歴の URL は途中で切れる
public enum FileLinkStatus: Equatable, Sendable {
    /// すべて在る（ファイルを持たない履歴もここに入る）
    case available
    /// 一部だけ見つからない
    case partiallyMissing(missing: Int)
    /// すべて見つからない
    case missing
}

/// ファイル履歴のリンク切れ判定（テスト対象）
public enum FileLinkRules {
    /// まだ実体が在るものだけを残す。
    /// ディスクを見るため、画面を止めたくない場所ではメインスレッドの外で呼ぶこと
    public static func existing(_ urls: [URL], fileManager: FileManager = .default) -> [URL] {
        // file:// URL の path は percent デコード済みの文字列を返す。
        // 名前に空白や日本語が入ったファイルを「無い」と誤判定しないための前提
        urls.filter { fileManager.fileExists(atPath: $0.path) }
    }

    public static func status(of urls: [URL], fileManager: FileManager = .default) -> FileLinkStatus {
        status(total: urls.count, missing: urls.count - existing(urls, fileManager: fileManager).count)
    }

    /// - Parameters:
    ///   - total: 履歴が持つファイル数
    ///   - missing: そのうち実体が見つからなかった数
    public static func status(total: Int, missing: Int) -> FileLinkStatus {
        guard total > 0, missing > 0 else { return .available }
        guard missing < total else { return .missing }
        return .partiallyMissing(missing: missing)
    }

    /// カードに出す注意書き。問題なければ nil。
    /// 貼っても何も出てこない理由が、貼る前に分かるようにするためのもの
    public static func warning(for status: FileLinkStatus) -> String? {
        switch status {
        case .available:
            return nil
        case .partiallyMissing(let missing):
            return "\(missing) 件の元ファイルが見つかりません"
        case .missing:
            return "元ファイルが見つかりません"
        }
    }
}
