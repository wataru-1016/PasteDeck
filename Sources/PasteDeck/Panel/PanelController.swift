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
    /// 画像編集中の高さ。340pt のままではキャンバスが小さすぎて塗る場所を狙えない。
    /// 固定値ではなく画面の高さに対する割合で決める。固定だと、広いディスプレイほど
    /// 上下に余白ばかりが残り、画面の割にキャンバスが小さいままになる
    private static let editingHeightRatio: CGFloat = 0.88
    /// 画面が高ければ割合で伸びるが、低い画面でもここまでは確保しようとする
    /// （画面の高さ自体が足りなければ、下の `min` で画面に収まるほうを採る）
    private static let minEditingPanelHeight: CGFloat = 720
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
    var onPaste: ((ClipboardItem, _ alternate: Bool) -> Void)?

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

        viewModel.onActivate = { [weak self] item, alternate in
            // 閉じアニメーション中のダブルクリックで、パネルがまだ key のうちに
            // ⌘V が合成されるのを防ぐ（表示中のときだけ受け付ける）
            guard let self, self.isShown else { return }
            self.hide { self.onPaste?(item, alternate) }
        }
        viewModel.onImageEditingChange = { [weak self] isEditing in
            self?.setExpanded(isEditing)
        }
        viewModel.onDragEnded = { [weak self] didDrop in
            guard let self else { return }
            // 渡し終えたら閉じる。貼り付けと同じで、用が済んだパネルが置いた先に
            // 覆いかぶさったままにならないようにする。
            // 置かずに放した場合でも、運んでいる間にフォーカスが他へ移っていれば閉じる
            // （その間は windowDidResignKey の自動クローズを止めているため）
            if didDrop || !self.panel.isKeyWindow { self.hide() }
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
        // カードを運んでいる間は閉じない。窓を下ろすと運んでいるものの出どころが
        // 無くなり、置く前にドラッグごと取り消されてしまう。
        // 運び終えたあとの後始末は onDragEnded で行う
        guard !viewModel.isDraggingCard else { return }
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
            viewModel.activateSelected(alternate: modifiers.contains(.shift))
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
        case 15 where modifiers == .command:  // ⌘R
            viewModel.recognizeSelected()
            return nil
        default:
            // ⌘1〜⌘9 は並びの n 番目を、選び直さずにそのまま貼る。
            // 修飾キー無しの数字は検索の文字として通したいので ⌘ を要る形にしてある。
            // ⇧ を足したときは ⇧↩ と同じ貼り方になる
            let isQuickPaste = modifiers == .command || modifiers == [.command, .shift]
            if isQuickPaste, let index = NumberKeyRules.index(forKeyCode: event.keyCode) {
                viewModel.activate(at: index, alternate: modifiers.contains(.shift))
                return nil
            }
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
        // 数値欄が先。文字の入力欄を出したまま大きさを変えることがあり、
        // そのとき打った数字は道具の切り替えではなく数値欄へ届かなければならない
        if viewModel.isEditingImageTextSize {
            return handleImageTextSizeKey(event)
        }
        if viewModel.isTypingImageText {
            return handleImageTextKey(event, modifiers: modifiers)
        }

        switch event.keyCode {
        case 53:  // esc
            viewModel.cancelEditing()
            return nil
        case 36, 76:  // return / keypad enter
            guard modifiers.contains(.command) else { return nil }
            viewModel.commitImageEditing(mode: Self.saveMode(for: modifiers))
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

    /// 文字の大きさを打ち込んでいる間のキー操作。
    ///
    /// ↩ と esc はどちらも「数値を確定して欄から抜ける」にする。esc をそのまま通すと
    /// 大きさを打ち直しただけのつもりで編集画面ごと閉じてしまい、描き込みが消える
    private func handleImageTextSizeKey(_ event: NSEvent) -> NSEvent? {
        switch event.keyCode {
        case 53, 36, 76:  // esc / return / keypad enter
            viewModel.isEditingImageTextSize = false
            return nil
        default:
            return event
        }
    }

    /// 文字を書き込んでいる間のキー操作。
    /// 打った文字が入力欄へ届くよう、確定（↩）と取り消し（esc）以外はすべて通す
    private func handleImageTextKey(
        _ event: NSEvent,
        modifiers: NSEvent.ModifierFlags
    ) -> NSEvent? {
        switch event.keyCode {
        case 53:  // esc
            viewModel.cancelImageText()
            return nil
        case 36, 76:  // return / keypad enter
            viewModel.commitImageText()
            // ⌘↩ は編集全体の保存でもある。文字を確定してからそのまま保存する
            if modifiers.contains(.command) {
                viewModel.commitImageEditing(mode: Self.saveMode(for: modifiers))
            }
            return nil
        default:
            return event
        }
    }

    /// ⌘↩ は上書き、⇧⌘↩ は新規。⇧ の有無だけで元画像が残るかどうかが変わるため、
    /// 判定は 1 か所に置いて呼び出し側で書き分けない
    private static func saveMode(for modifiers: NSEvent.ModifierFlags) -> ImageSaveMode {
        modifiers.contains(.shift) ? .addNew : .overwrite
    }

    /// 1〜8 で道具を切り替える。並びは編集画面のツールバーと同じ。
    /// 道具は 8 つしかないため、9 は空振りさせる
    private static func tool(forKeyCode keyCode: UInt16) -> ImageTool? {
        guard let index = NumberKeyRules.index(forKeyCode: keyCode),
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

    /// 画像編集中のパネルの高さ。画面をはみ出さない範囲で、できるだけ大きく取る
    private static func editingHeight(inside visibleFrame: NSRect) -> CGFloat {
        let preferred = max(visibleFrame.height * editingHeightRatio, minEditingPanelHeight)
        return min(preferred, visibleFrame.height)
    }

    /// 画像編集の間だけパネルを高くする。
    ///
    /// 高さが変わる間は中身を窓へ張り付ける（`.height`）。上端固定（`.minYMargin`）の
    /// ままだと、伸びた分がそのまま中身の下の空白として残ってしまう
    private func setExpanded(_ expanded: Bool) {
        guard isShown, !isAnimatingOut else { return }
        guard let screen = panel.screen ?? screenWithMouse() else { return }

        let height = expanded
            ? Self.editingHeight(inside: screen.visibleFrame)
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
