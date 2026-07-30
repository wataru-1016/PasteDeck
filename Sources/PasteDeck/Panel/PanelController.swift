import AppKit
import PasteCore
import QuartzCore
import SwiftUI

/// 借りたフォーカスでキー入力を受けられる borderless パネル
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// 画面下からスライドインする履歴パネルの表示・非表示とキーボード操作を管理する。
/// .nonactivatingPanel を使い、前面アプリをアクティブなまま保つのが貼り付けの要。
final class PanelController: NSObject, NSWindowDelegate {
    private static let panelHeight: CGFloat = 340
    private static let showDuration: TimeInterval = 0.22
    private static let hideDuration: TimeInterval = 0.16

    private let panel: KeyablePanel
    let viewModel: PanelViewModel
    private var keyMonitor: Any?
    private(set) var isShown = false
    private var isAnimatingOut = false

    /// 貼り付け実行時の処理。AppDelegate が設定する
    var onPaste: ((ClipboardItem, _ plainTextOnly: Bool) -> Void)?

    init(viewModel: PanelViewModel) {
        self.viewModel = viewModel
        self.panel = KeyablePanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        super.init()

        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        // isFloatingPanel = true は level を .floating へ上書きするため使わない
        panel.contentView = NSHostingView(rootView: PanelView(viewModel: viewModel))
        panel.delegate = self

        viewModel.onActivate = { [weak self] item, plainTextOnly in
            // 閉じアニメーション中のダブルクリックで、パネルがまだ key のうちに
            // ⌘V が合成されるのを防ぐ（表示中のときだけ受け付ける）
            guard let self, self.isShown else { return }
            self.hide { self.onPaste?(item, plainTextOnly) }
        }
        installKeyMonitor()
    }

    deinit {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
    }

    func toggle() {
        isShown ? hide() : show()
    }

    func show() {
        guard !isShown, !isAnimatingOut else { return }
        guard let screen = screenWithMouse() else { return }

        let visibleFrame = screen.visibleFrame
        let endFrame = NSRect(
            x: visibleFrame.minX,
            y: visibleFrame.minY,
            width: visibleFrame.width,
            height: Self.panelHeight
        )
        let startFrame = endFrame.offsetBy(dx: 0, dy: -Self.panelHeight - 8)

        viewModel.panelWillShow()
        panel.setFrame(startFrame, display: false)
        panel.makeKeyAndOrderFront(nil)
        isShown = true
        animate(to: endFrame, duration: Self.showDuration)
    }

    func hide(completion: (() -> Void)? = nil) {
        guard isShown, !isAnimatingOut else {
            completion?()
            return
        }
        isAnimatingOut = true
        isShown = false

        let downFrame = panel.frame.offsetBy(dx: 0, dy: -panel.frame.height - 8)
        animate(to: downFrame, duration: Self.hideDuration) { [weak self] in
            self?.panel.orderOut(nil)
            self?.isAnimatingOut = false
            completion?()
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        if isShown {
            hide()
        }
    }

    // MARK: - キーボード操作

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isShown, self.panel.isKeyWindow else { return event }
            return self.handleKey(event)
        }
    }

    /// 検索欄で未確定の変換文字列（marked text）を持っているか。
    /// SwiftUI の `TextField` はフィールドエディタ（`NSTextView`）を first responder にするため、
    /// `NSTextInputClient` として問い合わせられる
    private var isComposingText: Bool {
        guard let client = panel.firstResponder as? NSTextInputClient else { return false }
        return client.hasMarkedText()
    }

    /// 消費したら nil、検索フィールドへ流すならイベントを返す
    private func handleKey(_ event: NSEvent) -> NSEvent? {
        // 日本語入力の変換中はすべてのキーを IME へ渡す。↩ は変換の確定、← → は
        // 変換範囲の調整、esc は変換の取り消しに使われるため、ここで奪うと検索が打てない
        if isComposingText { return event }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        switch event.keyCode {
        case 53:  // esc
            hide()
            return nil
        case 123:  // ←
            viewModel.moveSelection(-1)
            return nil
        case 124:  // →
            viewModel.moveSelection(1)
            return nil
        case 36, 76:  // return / keypad enter
            viewModel.activateSelected(plainTextOnly: modifiers.contains(.shift))
            return nil
        case 51 where modifiers.contains(.command):  // ⌘⌫
            viewModel.deleteSelected()
            return nil
        case 35 where modifiers.contains(.command):  // ⌘P
            viewModel.togglePinSelected()
            return nil
        default:
            return event
        }
    }

    // MARK: - 内部処理

    private func animate(to frame: NSRect, duration: TimeInterval, completion: (() -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(frame, display: true)
        }, completionHandler: completion)
    }

    private func screenWithMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) } ?? NSScreen.main
    }
}
