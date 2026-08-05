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
    /// 画像編集中の高さ。340pt のままではキャンバスが小さすぎて塗る場所を狙えない
    private static let editingPanelHeight: CGFloat = 720
    private static let showDuration: TimeInterval = 0.22
    private static let hideDuration: TimeInterval = 0.16
    private static let resizeDuration: TimeInterval = 0.18
    /// 畳んだときの窓の高さ。0 は AppKit が最小サイズへ丸めることがあるため 1 にする
    private static let collapsedHeight: CGFloat = 1
    /// キー判定で意味を持つ修飾キー。`.deviceIndependentFlagsMask` には capsLock や
    /// numericPad も含まれるため、そのまま完全一致で比べると Caps Lock を点けている
    /// だけで ⌘P が成立しなくなる。判定に使う 4 つだけに絞る
    private static let significantModifiers: NSEvent.ModifierFlags = [.command, .shift, .option, .control]

    private let panel: KeyablePanel
    private let hostingView: NSHostingView<PanelView>
    let viewModel: PanelViewModel
    private var keyMonitor: Any?
    private(set) var isShown = false
    private var isAnimatingOut = false
    /// いま中身に与えている高さ。画像編集の間だけ `editingPanelHeight` になる
    private var contentHeight = PanelController.panelHeight

    /// 貼り付け実行時の処理。AppDelegate が設定する
    var onPaste: ((ClipboardItem, _ plainTextOnly: Bool) -> Void)?

    init(viewModel: PanelViewModel) {
        self.viewModel = viewModel
        self.hostingView = NSHostingView(rootView: PanelView(viewModel: viewModel))
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

        // 中身は contentView に直接せず、入れ物の NSView に「上端固定」でぶら下げる。
        // 表示・非表示は窓の高さだけを変えるスライドで（理由は show() のコメントを参照）、
        // 高さが変わる間の追従は autoresizing（下側の余白だけが伸縮）に任せる
        hostingView.autoresizingMask = [.width, .minYMargin]
        let container = NSView()
        container.addSubview(hostingView)
        panel.contentView = container
        panel.delegate = self

        viewModel.onActivate = { [weak self] item, plainTextOnly in
            // 閉じアニメーション中のダブルクリックで、パネルがまだ key のうちに
            // ⌘V が合成されるのを防ぐ（表示中のときだけ受け付ける）
            guard let self, self.isShown else { return }
            self.hide { self.onPaste?(item, plainTextOnly) }
        }
        viewModel.onImageEditingChange = { [weak self] isEditing in
            self?.setExpanded(isEditing)
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
        // 窓ごと画面の下の外からスライドさせてはいけない。ディスプレイを縦に並べていると
        // 「上の画面の下端の外」は下の画面の上端そのものなので、アニメーションの間だけ
        // 下の画面に映ってしまう。窓は最初から表示先の画面内に置き、高さだけを広げる。
        // 中身は窓の上端に固定してあり、窓の外は描画されないため、見た目は同じ
        // スライドインのまま他の画面には一切はみ出さない
        var startFrame = endFrame
        startFrame.size.height = Self.collapsedHeight

        contentHeight = Self.panelHeight
        viewModel.panelWillShow()
        panel.setFrame(startFrame, display: false)
        pinContentToTop()
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

        // show() と同じ理由で、画面外へ動かす代わりに高さを畳んで消す
        var downFrame = panel.frame
        downFrame.size.height = Self.collapsedHeight
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

        let modifiers = event.modifierFlags.intersection(Self.significantModifiers)

        if viewModel.isEditing {
            return handleEditingKey(event, modifiers: modifiers)
        }

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
        // 修飾キーは `contains(.command)` ではなく完全一致で判定する。
        // `contains` は ⇧⌘ の組み合わせにも一致するため、⌘◯ と ⇧⌘◯ を
        // 別の動作に割り当てられなくなる
        case 51 where modifiers == .command:  // ⌘⌫
            viewModel.deleteSelected()
            return nil
        // ⇧⌘P は ⌘P より先に置く。switch は上から順にマッチするため、
        // 逆順だと ⇧⌘P が ⌘P の分岐に吸われて到達しない
        case 35 where modifiers == [.command, .shift]:  // ⇧⌘P
            viewModel.pinnedOnly.toggle()
            return nil
        case 35 where modifiers == .command:  // ⌘P
            viewModel.togglePinSelected()
            return nil
        case 14 where modifiers == .command:  // ⌘E
            viewModel.beginEditingSelected()
            return nil
        default:
            return event
        }
    }

    /// 編集中のキー操作。↩ は改行として編集欄へ渡すため、保存は ⌘↩ に割り当てる。
    /// ⌘A や ⌘C などの標準編集キーは `default` で通し、メインメニュー（`MainMenu`）へ任せる
    private func handleEditingKey(
        _ event: NSEvent,
        modifiers: NSEvent.ModifierFlags
    ) -> NSEvent? {
        if viewModel.isImageEditing {
            return handleImageEditingKey(event, modifiers: modifiers)
        }

        switch event.keyCode {
        case 53:  // esc
            viewModel.cancelEditing()
            return nil
        case 36, 76:  // return / keypad enter
            guard modifiers.contains(.command) else { return event }
            viewModel.commitEditing()
            return nil
        default:
            return event
        }
    }

    /// 画像編集中のキー操作。
    ///
    /// 文字入力を使わないため、⌘ を伴わないキーはここですべて消費する。通してしまうと
    /// 編集画面の裏で検索が絞り込まれ、閉じたときに履歴の並びが変わってしまう。
    /// ⌘Z も横取りする（メインメニューの「取り消す」はテキスト欄向けのため）
    private func handleImageEditingKey(
        _ event: NSEvent,
        modifiers: NSEvent.ModifierFlags
    ) -> NSEvent? {
        switch event.keyCode {
        case 53:  // esc
            viewModel.cancelEditing()
            return nil
        case 36, 76:  // return / keypad enter
            guard modifiers.contains(.command) else { return nil }
            viewModel.commitImageEditing()
            return nil
        case 6 where modifiers == .command:  // ⌘Z
            viewModel.undoImageEdit()
            return nil
        default:
            if modifiers.isEmpty, let tool = Self.tool(forKeyCode: event.keyCode) {
                viewModel.imageTool = tool
                return nil
            }
            // ⌘Q などアプリ全体のキー等価はメインメニューへ通す
            return modifiers.contains(.command) ? event : nil
        }
    }

    /// 1〜4 で道具を切り替える。並びは編集画面のツールバーと同じ
    private static func tool(forKeyCode keyCode: UInt16) -> ImageTool? {
        let numberKeyCodes: [UInt16] = [18, 19, 20, 21]  // 1 / 2 / 3 / 4
        guard let index = numberKeyCodes.firstIndex(of: keyCode),
              index < ImageTool.allCases.count
        else { return nil }
        return ImageTool.allCases[index]
    }

    // MARK: - 内部処理

    /// 中身を窓の上端に張り付ける。窓の高さが collapsedHeight のときは中身のほぼ全体が
    /// 窓の下端からはみ出すが、窓の外は描画されないので画面には映らない。
    /// 画面が変わると窓の幅も変わるため、表示のたびに呼び直す
    private func pinContentToTop() {
        guard let container = panel.contentView else { return }
        hostingView.frame = NSRect(
            x: 0,
            y: container.bounds.height - contentHeight,
            width: container.bounds.width,
            height: contentHeight
        )
    }

    /// 画像編集の間だけパネルを高くする。
    ///
    /// 高さが変わる間は中身を窓へ張り付ける（`.height`）。上端固定（`.minYMargin`）の
    /// ままだと、伸びた分がそのまま中身の下の空白として残ってしまう
    private func setExpanded(_ expanded: Bool) {
        guard isShown, !isAnimatingOut else { return }
        guard let screen = panel.screen ?? screenWithMouse() else { return }

        let height = expanded
            ? min(Self.editingPanelHeight, screen.visibleFrame.height)
            : Self.panelHeight
        guard height != contentHeight else { return }
        contentHeight = height

        hostingView.autoresizingMask = [.width, .height]
        if let container = panel.contentView {
            hostingView.frame = container.bounds
        }

        var frame = panel.frame
        frame.size.height = height
        animate(to: frame, duration: Self.resizeDuration) { [weak self] in
            guard let self else { return }
            self.hostingView.autoresizingMask = [.width, .minYMargin]
            self.pinContentToTop()
        }
    }

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
