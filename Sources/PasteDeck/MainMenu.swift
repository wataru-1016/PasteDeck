import AppKit

/// 標準のテキスト編集ショートカットを有効にするためのメインメニュー。
///
/// ⌘A や ⌘C は responder chain へ直接届くのではなく、メインメニューのキー等価として
/// 配送される。`.accessory` なアプリはメニューバーを表示しないためメニュー自体は
/// 目に見えないが、登録していないと検索欄で ⌘A・⌘C・⌘X・⌘V・⌘Z がすべて無反応になる。
enum MainMenu {
    static func make() -> NSMenu {
        let menu = NSMenu()

        // 先頭のメニューはアプリケーションメニューとして扱われ、システムが
        // 「サービス」などを追加する。表示されないので中身は空のままでよい
        let appItem = NSMenuItem()
        appItem.submenu = NSMenu(title: "PasteDeck")
        menu.addItem(appItem)

        let editItem = NSMenuItem()
        editItem.submenu = editMenu()
        menu.addItem(editItem)

        return menu
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: "編集")

        // undo: / redo: は Swift から参照できる宣言がないためセレクタ名で指定する
        menu.addItem(withTitle: "取り消す", action: Selector(("undo:")), keyEquivalent: "z")
        let redoItem = menu.addItem(
            withTitle: "やり直す",
            action: Selector(("redo:")),
            keyEquivalent: "z"
        )
        redoItem.keyEquivalentModifierMask = [.command, .shift]

        menu.addItem(.separator())
        menu.addItem(withTitle: "カット", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "コピー", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "ペースト", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(
            withTitle: "すべてを選択",
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        )

        return menu
    }
}
