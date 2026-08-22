import AppKit
import PasteCore
import ServiceManagement

/// メニューバーアイコンが示す状態
enum StatusIconState {
    case idle
    case working
    case succeeded
    case failed

    var symbolName: String {
        switch self {
        case .idle: return "doc.on.clipboard"
        case .working: return "sparkles"
        case .succeeded: return "checkmark.circle"
        case .failed: return "exclamationmark.triangle"
        }
    }
}

/// メニューバー常駐アイコンとメニュー
final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let store: HistoryStore
    private let monitor: ClipboardMonitor
    private let panelController: PanelController
    private let shortcutSettings: ShortcutSettingsController
    private let ocrController: OCRController

    /// 一時表示（✓ / ⚠︎）を出しておく時間
    private static let transientIconDuration: TimeInterval = 1.2

    private var baseIconState: StatusIconState = .idle
    /// 一時表示を戻す予約。連打したときに前回の予約が後発の表示を消さないよう、
    /// 新しい表示のたびに前の予約を取り消す
    private var transientIconReset: DispatchWorkItem?

    private let showItem = NSMenuItem(title: "履歴を表示", action: #selector(showPanel), keyEquivalent: "")
    private let captureItem = NSMenuItem(
        title: "画面の文字を読み取ってコピー",
        action: #selector(startCapture),
        keyEquivalent: ""
    )
    private let recopyItem = NSMenuItem(
        title: "読み取り結果をもう一度コピー",
        action: #selector(recopyLast),
        keyEquivalent: ""
    )
    private let aiPolishItem = NSMenuItem(
        title: "AI 校正（Apple Intelligence）",
        action: #selector(toggleAIPolish),
        keyEquivalent: ""
    )
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
    private var outputFormatMenuItems: [NSMenuItem] = []

    init(
        store: HistoryStore,
        monitor: ClipboardMonitor,
        panelController: PanelController,
        shortcutSettings: ShortcutSettingsController,
        ocrController: OCRController
    ) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.store = store
        self.monitor = monitor
        self.panelController = panelController
        self.shortcutSettings = shortcutSettings
        self.ocrController = ocrController
        super.init()

        applyIcon(.idle)
        statusItem.menu = buildMenu()
    }

    // MARK: - アイコンの状態

    func setIconState(_ state: StatusIconState) {
        transientIconReset?.cancel()
        transientIconReset = nil
        switch state {
        case .idle, .working:
            baseIconState = state
            applyIcon(state)
        case .succeeded, .failed:
            // 成否が出た時点で作業は終わっている。戻り先を待機にしておかないと、
            // 直前に保存した .working へ 1.2 秒後に戻り、処理中のまま固まって見える
            baseIconState = .idle
            applyIcon(state)
            let reset = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.applyIcon(self.baseIconState)
                self.transientIconReset = nil
            }
            transientIconReset = reset
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.transientIconDuration, execute: reset)
        }
    }

    private func applyIcon(_ state: StatusIconState) {
        statusItem.button?.image = NSImage(
            systemSymbolName: state.symbolName,
            accessibilityDescription: "PasteDeck"
        )
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        // 既定の true のままだと、menuWillOpen で設定した isEnabled が
        // 表示直前に上書きされ、「もう一度コピー」が常に有効に見えてしまう
        menu.autoenablesItems = false

        showItem.target = self
        menu.addItem(showItem)

        captureItem.target = self
        menu.addItem(captureItem)

        recopyItem.target = self
        menu.addItem(recopyItem)

        menu.addItem(.separator())

        menu.addItem(buildOutputFormatMenuItem())

        aiPolishItem.target = self
        menu.addItem(aiPolishItem)

        menu.addItem(.separator())

        pauseItem.target = self
        menu.addItem(pauseItem)

        menu.addItem(buildRetentionMenuItem())

        let clearItem = NSMenuItem(title: "未ピンの履歴を消去…", action: #selector(clearHistory), keyEquivalent: "")
        clearItem.target = self
        menu.addItem(clearItem)

        menu.addItem(.separator())

        let shortcutItem = NSMenuItem(
            title: "ショートカットを変更…",
            action: #selector(openShortcutSettings),
            keyEquivalent: ""
        )
        shortcutItem.target = self
        menu.addItem(shortcutItem)

        loginItem.target = self
        menu.addItem(loginItem)

        let accessibilityItem = NSMenuItem(
            title: "アクセシビリティ設定を開く…",
            action: #selector(openAccessibilitySettings),
            keyEquivalent: ""
        )
        accessibilityItem.target = self
        menu.addItem(accessibilityItem)

        let screenRecordingItem = NSMenuItem(
            title: "画面収録の設定を開く…",
            action: #selector(openScreenRecordingSettings),
            keyEquivalent: ""
        )
        screenRecordingItem.target = self
        menu.addItem(screenRecordingItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "PasteDeck を終了", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    /// 「出力形式」サブメニュー。tag には `OutputFormat.allCases` の位置を入れる
    private func buildOutputFormatMenuItem() -> NSMenuItem {
        let formatMenu = NSMenu()
        formatMenu.autoenablesItems = false
        outputFormatMenuItems = OutputFormat.allCases.enumerated().map { index, format in
            let item = NSMenuItem(
                title: Self.title(for: format),
                action: #selector(selectOutputFormat(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = index
            formatMenu.addItem(item)
            return item
        }

        let formatItem = NSMenuItem(title: "出力形式", action: nil, keyEquivalent: "")
        formatItem.submenu = formatMenu
        return formatItem
    }

    private static func title(for format: OutputFormat) -> String {
        switch format {
        case .text: return "テキスト"
        case .markdown: return "Markdown"
        }
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
        updateShortcutLabels()
        updateOCRItems()
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

    /// 各項目に現在のショートカットを添える。
    /// `NSMenuItem` は特殊キーごとに固有の文字を求めるため、表せない組み合わせのときは
    /// 何も出さない（実際の発火は Carbon 側が担うため、表示だけの問題に留まる）
    private func updateShortcutLabels() {
        apply(.panel, to: showItem)
        apply(.ocr, to: captureItem)
    }

    /// 登録できていないキーは表記しない。他アプリに取られたままの表記を出すと、
    /// 押しても効かないキーを案内することになる
    private func apply(_ action: HotkeyAction, to item: NSMenuItem) {
        guard shortcutSettings.isRegistered(action) else {
            item.keyEquivalent = ""
            item.keyEquivalentModifierMask = []
            return
        }
        let shortcut = shortcutSettings.shortcut(for: action)
        item.keyEquivalent = shortcut.menuKeyEquivalent ?? ""
        item.keyEquivalentModifierMask = Self.menuModifierMask(shortcut.modifiers)
    }

    /// 出力形式・AI 校正・「もう一度コピー」の状態を引き直す
    private func updateOCRItems() {
        let format = OCRPreferences.loadOutputFormat()
        for (index, item) in outputFormatMenuItems.enumerated() {
            item.state = OutputFormat.allCases[index] == format ? .on : .off
        }

        // 起動時にアラートを出す代わりに、使えない理由を項目名に載せて無効化する
        if let reason = AIPolisher.unavailableReason {
            aiPolishItem.title = "AI 校正（\(reason)）"
            aiPolishItem.isEnabled = false
            aiPolishItem.state = .off
        } else {
            aiPolishItem.title = "AI 校正（Apple Intelligence）"
            aiPolishItem.isEnabled = true
            aiPolishItem.state = OCRPreferences.loadAIPolishEnabled() ? .on : .off
        }

        // 読み取り中はどちらも押させない。押せてしまうと OCRController 側の
        // 排他に弾かれてビープが鳴るだけで、なぜ効かないのかが分からない
        captureItem.isEnabled = !ocrController.isWorking
        recopyItem.isEnabled = ocrController.lastText != nil && !ocrController.isWorking
    }

    private static func menuModifierMask(_ modifiers: HotkeyShortcut.Modifiers) -> NSEvent.ModifierFlags {
        var mask: NSEvent.ModifierFlags = []
        if modifiers.contains(.command) { mask.insert(.command) }
        if modifiers.contains(.shift) { mask.insert(.shift) }
        if modifiers.contains(.option) { mask.insert(.option) }
        if modifiers.contains(.control) { mask.insert(.control) }
        return mask
    }

    @objc private func openShortcutSettings() {
        shortcutSettings.show()
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

    @objc private func startCapture() {
        ocrController.capture()
    }

    @objc private func recopyLast() {
        ocrController.recopyLast()
    }

    @objc private func selectOutputFormat(_ sender: NSMenuItem) {
        guard OutputFormat.allCases.indices.contains(sender.tag) else { return }
        OCRPreferences.save(outputFormat: OutputFormat.allCases[sender.tag])
    }

    @objc private func toggleAIPolish() {
        OCRPreferences.save(aiPolishEnabled: !OCRPreferences.loadAIPolishEnabled())
    }

    @objc private func openAccessibilitySettings() {
        PasteService.openAccessibilitySettings()
    }

    @objc private func openScreenRecordingSettings() {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
