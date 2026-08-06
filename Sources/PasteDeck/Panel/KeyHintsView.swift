import PasteCore
import SwiftUI

/// 上部バー右端に並ぶキーボードショートカットの一覧。
///
/// キーと説明を 1 本のテキストで繋げると `⇧↩ プレーン ⌘P ピン` のように記号と語が
/// 地続きになって読み取りづらいため、キーだけキーキャップ風のチップに分けている。
struct KeyHintsView: View {
    /// ⇧↩ の意味は選んでいるアイテムで変わるため、外から受け取る
    let alternatePaste: AlternatePaste

    private static let keyFontSize: Double = 12
    private static let labelFontSize: Double = 12
    /// 「キー＋説明」の組どうしの間隔。組の内側（`itemSpacing`）より広く取って、
    /// どのキーがどの動作に対応しているかが間隔だけで読み取れるようにする
    private static let groupSpacing: Double = 20
    private static let itemSpacing: Double = 7

    private struct KeyHint: Identifiable {
        let key: String
        let label: String

        var id: String { key }
    }

    /// キーと動作の対応。`PanelController.handleKey(_:)` の分岐と一致させる
    private var hints: [KeyHint] {
        [
            KeyHint(key: "↩", label: "貼り付け"),
            KeyHint(key: "⇧↩", label: Self.label(for: alternatePaste)),
            KeyHint(key: "⌘E", label: "編集"),
            KeyHint(key: "⌘P", label: "ピン"),
            KeyHint(key: "⌘⌫", label: "削除"),
            KeyHint(key: "esc", label: "閉じる"),
        ]
    }

    /// どちらも 4 文字に揃える。長さが変わると、カードを選び直すたびに
    /// 右端の一覧全体が横にずれて目障りになる
    private static func label(for alternatePaste: AlternatePaste) -> String {
        switch alternatePaste {
        case .plainText: return "プレーン"
        case .file: return "ファイル"
        }
    }

    var body: some View {
        HStack(spacing: Self.groupSpacing) {
            ForEach(hints) { hint in
                HStack(spacing: Self.itemSpacing) {
                    KeycapView(key: hint.key, fontSize: Self.keyFontSize)
                    Text(hint.label)
                        .font(.system(size: Self.labelFontSize))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .lineLimit(1)
        // 検索フィールドが固定幅のため、余白の取り合いで潰れないよう理想サイズを保つ
        .fixedSize()
    }
}
