import AppKit
import PasteCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: HistoryStore!
    private var monitor: ClipboardMonitor!
    private var pasteService: PasteService!
    private var hotkeyManager: HotkeyManager!
    private var shortcutSettings: ShortcutSettingsController!
    private var statusBarController: StatusBarController!
    private var panelController: PanelController!
    private var ocrController: OCRController!
    private var activityToken: NSObjectProtocol?
    private var retentionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 検索欄で ⌘A・⌘C・⌘X・⌘V・⌘Z を効かせるために必要（詳細は MainMenu）
        NSApp.mainMenu = MainMenu.make()

        let persistence: Persistence
        do {
            persistence = try Persistence(rootURL: Persistence.defaultRootURL())
        } catch {
            Log.error("保存先ディレクトリを作成できませんでした: \(error)")
            NSApp.terminate(nil)
            return
        }

        store = HistoryStore(persistence: persistence, policy: RetentionPreferences.load())
        monitor = ClipboardMonitor(store: store)
        pasteService = PasteService(store: store, monitor: monitor)

        let viewModel = PanelViewModel(store: store)
        panelController = PanelController(viewModel: viewModel)
        panelController.onPaste = { [weak self] item, alternate in
            self?.pasteService.paste(item, alternate: alternate)
        }

        ocrController = OCRController(
            store: store,
            monitor: monitor,
            panelController: panelController
        )
        viewModel.onRecognizeText = { [weak self] item in
            self?.ocrController.recognize(item)
        }

        hotkeyManager = HotkeyManager(shortcuts: HotkeyPreferences.loadAll()) { [weak self] action in
            switch action {
            case .panel: self?.panelController.toggle()
            case .ocr: self?.ocrController.capture()
            }
        }
        // 登録できなくてもメニューからは操作できるため、起動自体は続ける
        // （登録に失敗した action は HotkeyManager が個別にログへ残す）
        hotkeyManager.start()
        shortcutSettings = ShortcutSettingsController(hotkeyManager: hotkeyManager)

        statusBarController = StatusBarController(
            store: store,
            monitor: monitor,
            panelController: panelController,
            shortcutSettings: shortcutSettings,
            ocrController: ocrController
        )
        // self ではなく statusBarController を弱参照で捕まえ、循環参照を作らない
        ocrController.onStatusChange = { [weak statusBarController] state in
            statusBarController?.setIconState(state)
        }

        // App Nap によるポーリング停止を防ぐ（システムのスリープは妨げない）
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "クリップボード監視"
        )

        monitor.start()

        // 保持期間の期限切れを定期的に整理する（5 分間隔）
        let timer = Timer(timeInterval: 300, repeats: true) { [weak self] _ in
            self?.store.applyRetention()
        }
        timer.tolerance = 30
        RunLoop.main.add(timer, forMode: .common)
        retentionTimer = timer
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}
