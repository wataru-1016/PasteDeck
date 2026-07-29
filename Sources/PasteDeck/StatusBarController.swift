import AppKit
import PasteCore
import ServiceManagement

/// メニューバー常駐アイコンとメニュー
final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let store: HistoryStore
    private let monitor: ClipboardMonitor
    private let panelController: PanelController

    private let pauseItem = NSMenuItem(
        title: "監視を一時停止",
        action: #selector(togglePause),
        keyEquivalent: ""
    )
    private let loginItem = NSMenuItem(
        title: "ログイン時に起動",
        action: #selector(toggleLaunchAtLogin),
        keyEquivalent: ""
    )

    private static let maxItemsChoices: [(title: String, value: Int)] = [
        ("100 件", 100), ("500 件", 500), ("1000 件", 1000), ("無制限", 0),
    ]
    private static let maxAgeChoices: [(title: String, seconds: Int)] = [
        ("24 時間", 86_400), ("1 週間", 604_800), ("1 ヶ月", 2_592_000), ("無期限", 0),
    ]
    private var maxItemsMenuItems: [NSMenuItem] = []
    private var maxAgeMenuItems: [NSMenuItem] = []

    init(store: HistoryStore, monitor: ClipboardMonitor, panelController: PanelController) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.store = store
        self.monitor = monitor
        self.panelController = panelController
        super.init()

        statusItem.button?.image = NSImage(
            systemSymbolName: "doc.on.clipboard",
            accessibilityDescription: "PasteDeck"
        )
        statusItem.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        let showItem = NSMenuItem(title: "履歴を表示", action: #selector(showPanel), keyEquivalent: "v")
        showItem.keyEquivalentModifierMask = [.command, .shift]
        showItem.target = self
        menu.addItem(showItem)

        menu.addItem(.separator())

        pauseItem.target = self
        menu.addItem(pauseItem)

        menu.addItem(buildRetentionMenuItem())

        let clearItem = NSMenuItem(title: "未ピンの履歴を消去…", action: #selector(clearHistory), keyEquivalent: "")
        clearItem.target = self
        menu.addItem(clearItem)

        menu.addItem(.separator())

        loginItem.target = self
        menu.addItem(loginItem)

        let accessibilityItem = NSMenuItem(
            title: "アクセシビリティ設定を開く…",
            action: #selector(openAccessibilitySettings),
            keyEquivalent: ""
        )
        accessibilityItem.target = self
        menu.addItem(accessibilityItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "PasteDeck を終了", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    /// 「履歴の保持」サブメニュー（件数上限と保持期間のプリセット選択）
    private func buildRetentionMenuItem() -> NSMenuItem {
        let retentionMenu = NSMenu()

        retentionMenu.addItem(Self.sectionHeader("件数上限"))
        maxItemsMenuItems = Self.maxItemsChoices.map { choice in
            let item = NSMenuItem(title: choice.title, action: #selector(selectMaxItems(_:)), keyEquivalent: "")
            item.target = self
            item.tag = choice.value
            retentionMenu.addItem(item)
            return item
        }

        retentionMenu.addItem(.separator())
        retentionMenu.addItem(Self.sectionHeader("保持期間"))
        maxAgeMenuItems = Self.maxAgeChoices.map { choice in
            let item = NSMenuItem(title: choice.title, action: #selector(selectMaxAge(_:)), keyEquivalent: "")
            item.target = self
            item.tag = choice.seconds
            retentionMenu.addItem(item)
            return item
        }

        let retentionItem = NSMenuItem(title: "履歴の保持", action: nil, keyEquivalent: "")
        retentionItem.submenu = retentionMenu
        return retentionItem
    }

    private static func sectionHeader(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    func menuWillOpen(_ menu: NSMenu) {
        pauseItem.state = monitor.isPaused ? .on : .off
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off

        let policy = store.policy
        for item in maxItemsMenuItems {
            item.state = (policy.maxItems ?? 0) == item.tag ? .on : .off
        }
        for item in maxAgeMenuItems {
            item.state = Int(policy.maxAge ?? 0) == item.tag ? .on : .off
        }
    }

    @objc private func selectMaxItems(_ sender: NSMenuItem) {
        var policy = store.policy
        policy.maxItems = sender.tag == 0 ? nil : sender.tag
        RetentionPreferences.save(policy)
        store.updatePolicy(policy)
    }

    @objc private func selectMaxAge(_ sender: NSMenuItem) {
        var policy = store.policy
        policy.maxAge = sender.tag == 0 ? nil : TimeInterval(sender.tag)
        RetentionPreferences.save(policy)
        store.updatePolicy(policy)
    }

    @objc private func showPanel() {
        panelController.toggle()
    }

    @objc private func togglePause() {
        monitor.isPaused.toggle()
    }

    @objc private func clearHistory() {
        let count = store.unpinnedCount
        guard count > 0 else { return }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "履歴を消去しますか？"
        alert.informativeText = "ピン留めされていない \(count) 件の履歴を削除します。この操作は取り消せません。"
        alert.addButton(withTitle: "消去")
        alert.addButton(withTitle: "キャンセル")
        if alert.runModal() == .alertFirstButtonReturn {
            store.clearUnpinned()
        }
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "ログイン時の起動を設定できませんでした"
            alert.informativeText = """
            .app としてビルドしたものを安定した場所（/Applications など）から起動している必要があります。
            詳細: \(error.localizedDescription)
            """
            alert.runModal()
        }
    }

    @objc private func openAccessibilitySettings() {
        PasteService.openAccessibilitySettings()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
