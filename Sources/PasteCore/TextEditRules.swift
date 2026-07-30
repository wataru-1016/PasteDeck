import Foundation

/// テキスト編集（⌘E）のルール（純粋関数のみ・テスト対象）。
///
/// クリップボードの 1 アイテムは、同じ内容の独立した複数表現
/// （`public.utf8-plain-text` / `public.rtf` / `public.html` / 画像）を持つ。
/// どれを採用するかは貼り付け先のアプリが決めるため、プレーンだけを書き換えると
/// 「Word に貼ると直したはずの誤字が残っている」という不整合になる。OS はこれを
/// 調整しないので、編集を保存するときは装飾側の flavor をすべて破棄する。
public enum TextEditRules {
    /// 編集画面に載せるテキストの上限。読み込みと描画で UI が止まるのを防ぐ。
    /// 手で直せる分量をはるかに超えているため、対象外にしても実害がない
    public static let maxEditableBytes = 1024 * 1024

    /// 編集できるアイテムか。画像とファイルは編集できるテキストを持たない
    public static func canEdit(kind: ItemKind, byteSize: Int) -> Bool {
        guard kind == .text || kind == .link else { return false }
        return byteSize <= maxEditableBytes
    }

    /// 保存すべき変更か。
    /// 空・空白のみへの変更は誤操作とみなし、変更なしなら履歴を書き換えない
    public static func shouldSave(_ text: String, original: String) -> Bool {
        guard text != original else { return false }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 保存時に破棄される flavor を持つか。編集画面で事前に知らせるために使う
    public static func discardsDecoration(_ flavors: [String: Data]) -> Bool {
        flavors.keys.contains { $0 != CaptureRules.plainTextType }
    }

    /// 編集後に残す flavor。プレーンテキストのみ
    public static func flavors(forEditedText text: String) -> [String: Data] {
        [CaptureRules.plainTextType: Data(text.utf8)]
    }
}
