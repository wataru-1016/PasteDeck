import AppKit
import PasteCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: HistoryStore!
    private var monitor: ClipboardMonitor!
    private var pasteService: PasteService!
    private var hotkeyManager: HotkeyManager!
    private var statusBarController: StatusBarController!
    private var panelController: PanelController!
    private var activityToken: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let persistence: Persistence
        do {
            persistence = try Persistence(rootURL: Persistence.defaultRootURL())
        } catch {
            Log.error("保存先ディレクトリを作成できませんでした: \(error)")
            NSApp.terminate(nil)
            return
        }

        store = HistoryStore(persistence: persistence)
        monitor = ClipboardMonitor(store: store)
        pasteService = PasteService(store: store, monitor: monitor)

        let viewModel = PanelViewModel(store: store)
        panelController = PanelController(viewModel: viewModel)
        panelController.onPaste = { [weak self] item, plainTextOnly in
            self?.pasteService.paste(item, plainTextOnly: plainTextOnly)
        }

        hotkeyManager = HotkeyManager { [weak self] in
            self?.panelController.toggle()
        }
        hotkeyManager.register()

        statusBarController = StatusBarController(
            store: store,
            monitor: monitor,
            panelController: panelController
        )

        // App Nap によるポーリング停止を防ぐ（システムのスリープは妨げない）
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "クリップボード監視"
        )

        monitor.start()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}
