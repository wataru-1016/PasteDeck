import AppKit
import Combine
import Foundation
import PasteCore

/// パネル UI の状態（検索・フィルター・選択）を管理する
final class PanelViewModel: ObservableObject {
    @Published var query = ""
    @Published var pinnedOnly = false
    @Published private(set) var visible: [ClipboardItem] = []
    @Published var selectedID: UUID?
    /// インクリメントすると検索フィールドへフォーカスが移る
    @Published var focusToken = 0

    /// ⌘E でテキストを編集中のアイテム。nil なら編集していない
    @Published private(set) var editingItem: ClipboardItem?
    @Published var editingText = ""
    /// 保存すると装飾が破棄されるか。編集画面での事前警告に使う
    @Published private(set) var editingDiscardsDecoration = false

    /// ⌘E で画像を編集中のアイテム。読み込みが終わるまで `editingImage` は nil のまま
    @Published private(set) var editingImageItem: ClipboardItem?
    @Published private(set) var editingImage: ImageEditSource?
    @Published var imageTool: ImageTool = .redaction {
        didSet {
            guard oldValue != imageTool else { return }
            // 入力途中の文字は道具を変えた時点で書き込む。捨てると打ち直しになる
            commitImageText()
        }
    }
    /// 選んでいる色と太さ。編集画面を閉じても持ち越す（毎回選び直すのは煩わしい）
    @Published var imageColor: StrokeColor = .marker
    @Published var imageWeight: StrokeWeight = .regular
    /// 書き込む文字の大きさ（画像ピクセル）。色や太さと違い、画像を開くたびに
    /// その画像に合った既定値へ戻す。同じ 24px でも 4K のスクリーンショットでは
    /// 小さすぎ、小さな画像でははみ出すため、持ち越すと毎回直す羽目になる
    @Published private(set) var imageTextSize = ImageEditRules.minFontSize
    /// 大きさの数値欄に入力しているか。打った数字が道具の切り替えに吸われないようにする
    @Published var isEditingImageTextSize = false
    /// 確定済みの操作。末尾から取り消す（⌘Z）
    @Published private(set) var imageEdits: [ImageEdit] = []
    /// ドラッグ中の操作。離すまで `imageEdits` には入れない
    @Published private(set) var imageDraft: ImageEdit?
    /// 文字を書き込む位置（画像座標）。nil なら入力していない
    @Published private(set) var imageTextAnchor: CGPoint?
    @Published var imageText = ""
    @Published private(set) var imageEditError: String?

    private var editingOriginalText = ""
    private var imageDraftPoints: [CGPoint] = []
    /// 読み込み中に取り消されたかどうかの判定に使う
    private var imageLoadToken = UUID()

    /// 何らかの編集画面を開いているか。パネルのキー操作の分岐に使う
    var isEditing: Bool { editingItem != nil || editingImageItem != nil }
    var isImageEditing: Bool { editingImageItem != nil }
    /// 文字の入力欄を出しているか。キー入力を入力欄へ通すかの判定に使う
    var isTypingImageText: Bool { imageTextAnchor != nil }

    let store: HistoryStore
    /// アイテム決定時（Enter / ダブルクリック）の処理。PanelController が設定する
    var onActivate: ((ClipboardItem, _ alternate: Bool) -> Void)?
    /// 画像編集の開始・終了。キャンバスを確保するためパネルを広げる
    var onImageEditingChange: ((Bool) -> Void)?
    /// カードのドラッグが終わったときの処理。引数はどこかに置かれたかどうか。
    /// PanelController が設定する
    var onDragEnded: ((_ didDrop: Bool) -> Void)?
    /// 画像カードの ⌘R。AppDelegate が OCRController へ繋ぐ
    var onRecognizeText: ((ClipboardItem) -> Void)?

    /// 進行中のドラッグ。AppKit 側は始めたセッションを保持しないため、終わるまでここで持つ。
    /// 入っている間は次のドラッグを始めない
    private var dragSession: CardDragSession?

    /// カードを運んでいる最中か。運んでいる間にパネルを閉じないための判定に使う
    var isDraggingCard: Bool { dragSession != nil }

    private var cancellables = Set<AnyCancellable>()

    init(store: HistoryStore) {
        self.store = store

        Publishers.CombineLatest3(store.$items, $query, $pinnedOnly)
            .map { items, query, pinnedOnly in
                SearchFilter.apply(items, query: query, pinnedOnly: pinnedOnly)
            }
            .sink { [weak self] filtered in
                self?.visible = filtered
                self?.ensureSelectionValid()
            }
            .store(in: &cancellables)
    }

    var selectedItem: ClipboardItem? {
        visible.first { $0.id == selectedID }
    }

    func panelWillShow() {
        // 編集中にパネルが閉じた（他アプリをクリックした）場合、その編集は破棄した扱いにする。
        // 残したままだと、次に開いたときに前回の編集画面が載ったままになる
        if isEditing { endEditing() }
        query = ""
        pinnedOnly = false
        selectedID = visible.first?.id
        focusToken += 1
    }

    func select(_ item: ClipboardItem) {
        // 削除ボタンとカードのタップが同時発火した場合に、
        // 削除済みアイテムが選択されるのを防ぐ
        guard visible.contains(where: { $0.id == item.id }) else { return }
        selectedID = item.id
    }

    func moveSelection(_ delta: Int) {
        guard !visible.isEmpty else { return }
        let current = visible.firstIndex { $0.id == selectedID } ?? 0
        let next = min(max(current + delta, 0), visible.count - 1)
        selectedID = visible[next].id
    }

    /// - Parameter alternate: ⇧ を押しながら決定したか（⇧↩ での貼り付け）
    func activate(_ item: ClipboardItem, alternate: Bool = false) {
        onActivate?(item, alternate)
    }

    func activateSelected(alternate: Bool) {
        guard let item = selectedItem else { return }
        activate(item, alternate: alternate)
    }

    /// ⌘1〜⌘9。並びの n 番目（0 始まり）を選ばずにそのまま貼り付ける。
    ///
    /// 数えるのは表示中の並びで、検索で絞り込んだあとは絞り込んだ結果の先頭からになる。
    /// カードに出しているキー表記と同じ数え方でなければ、見えている番号と貼られるものがずれる
    func activate(at index: Int, alternate: Bool) {
        guard visible.indices.contains(index) else { return }
        activate(visible[index], alternate: alternate)
    }

    // MARK: - ドラッグして書き出す

    /// カードを Finder などへドラッグする。渡せるものが無ければ何も起きない。
    ///
    /// 貼り付けと違って前面アプリを選ばないため、パネルを開いたまま
    /// 目的の場所へ直接置ける（複数ファイルの履歴も一式のまま渡せる）
    func beginDrag(_ item: ClipboardItem) {
        guard dragSession == nil else { return }
        dragSession = CardDragSession.begin(item: item, store: store) { [weak self] didDrop in
            guard let self else { return }
            self.dragSession = nil
            // 置いたときだけ、貼り付けたときと同じ扱いにする。使ったものが先頭に
            // 来ないと、次に開いたときまた探し直すことになる。
            // どこにも置かずに放したときは履歴の並びを触らない
            if didDrop { self.store.moveToFront(item.id) }
            self.onDragEnded?(didDrop)
        }
    }

    /// ⇧↩ を押すと何が起きるか。選んでいるアイテムの種別で変わるためヒント表示に使う。
    /// 何も選んでいなければ、履歴の大半を占めるテキストの挙動を出しておく
    var alternatePaste: AlternatePaste {
        PasteRules.alternatePaste(for: selectedItem?.kind ?? .text)
    }

    func togglePin(_ item: ClipboardItem) {
        store.togglePin(item.id)
    }

    func delete(_ item: ClipboardItem) {
        let index = visible.firstIndex { $0.id == item.id }
        let neighborID: UUID? = index.flatMap { i in
            if i + 1 < visible.count { return visible[i + 1].id }
            if i > 0 { return visible[i - 1].id }
            return nil
        }
        let wasSelected = selectedID == item.id
        store.delete(item.id)
        if wasSelected {
            selectedID = neighborID ?? visible.first?.id
        }
    }

    func deleteSelected() {
        guard let item = selectedItem else { return }
        delete(item)
    }

    func togglePinSelected() {
        guard let item = selectedItem else { return }
        togglePin(item)
    }

    // MARK: - 編集（⌘E）

    /// 選択中アイテムの編集を開始する。開く画面は種別で決まる
    /// 選択中が画像のときだけ読み取る。文字は既に読めているので対象外。
    /// 読み取り結果は新しいカードとして増えるため、パネルは閉じない
    func recognizeSelected() {
        guard let item = selectedItem, item.kind == .image else { return }
        onRecognizeText?(item)
    }

    func beginEditingSelected() {
        guard let item = selectedItem else { return }
        switch item.kind {
        case .text, .link:
            beginTextEditing(item)
        case .image:
            beginImageEditing(item)
        case .fileList:
            // ファイルは実体がディスク上にあり、履歴側で書き換えるものではない
            break
        }
    }

    // MARK: - テキスト編集

    /// 編集対象は `preview`（先頭 400 文字）ではなく flavor に入っている全文
    private func beginTextEditing(_ item: ClipboardItem) {
        guard TextEditRules.canEdit(kind: item.kind, byteSize: item.byteSize) else { return }

        let flavors = store.flavors(for: item.id) ?? [:]
        guard let data = flavors[CaptureRules.plainTextType],
              let text = String(data: data, encoding: .utf8)
        else { return }

        editingOriginalText = text
        editingText = text
        editingDiscardsDecoration = TextEditRules.discardsDecoration(flavors)
        editingItem = item
    }

    func commitEditing() {
        guard let item = editingItem else { return }
        if TextEditRules.shouldSave(editingText, original: editingOriginalText) {
            store.replaceText(editingText, for: item.id)
            // 装飾を破棄したので、キャッシュ済みの装飾付き表示を捨てて読み直させる
            RichTextProvider.shared.invalidate(id: item.id)
        }
        endEditing()
    }

    func cancelEditing() {
        endEditing()
    }

    // MARK: - 画像編集

    private func beginImageEditing(_ item: ClipboardItem) {
        guard ImageEditRules.canEdit(kind: item.kind, byteSize: item.byteSize) else { return }

        let token = UUID()
        imageLoadToken = token
        editingImageItem = item
        onImageEditingChange?(true)

        // 数 MB の PNG を展開する間パネルが固まらないよう、読み込みだけ別スレッドで行う
        let persistence = store.persistence
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let source = persistence.loadFlavors(id: item.id)
                .flatMap { ImageEditLoader.load(flavors: $0) }
            DispatchQueue.main.async {
                // 読み込んでいる間に esc で閉じられていたら結果を捨てる
                guard let self, self.imageLoadToken == token else { return }
                guard let source else {
                    self.imageEditError = "この画像は編集できません"
                    return
                }
                self.editingImage = source
                self.imageTextSize = ImageEditRules.defaultFontSize(forImageSize: source.size)
            }
        }
    }

    /// ドラッグ中の操作を更新する。`point` は画像のピクセル座標
    func updateImageDraft(at point: CGPoint) {
        guard let source = editingImage else { return }

        // 文字は押した位置に入力欄を出すだけで、ドラッグでは形を作らない
        guard imageTool != .text else {
            imageDraftPoints = [point]
            return
        }

        if imageDraftPoints.isEmpty {
            imageDraftPoints = [point]
        } else if imageTool.usesAllPoints {
            imageDraftPoints.append(point)
        } else {
            // 形が始点と終点で決まる道具は、途中の点を捨てて 2 点だけ保つ
            imageDraftPoints = [imageDraftPoints[0], point]
        }
        imageDraft = makeImageDraft(lineWidth: lineWidth(for: imageTool, imageSize: source.size))
    }

    /// ドラッグを離したときに呼ぶ。誤クリック相当の操作はここで捨てる
    func commitImageDraft() {
        defer {
            imageDraftPoints = []
            imageDraft = nil
        }
        guard let source = editingImage else { return }

        // 文字だけは離した時点では確定しない。押した位置に入力欄を出し、
        // 打ち終わってから（↩）書き込みになる
        if imageTool == .text {
            guard let point = imageDraftPoints.last else { return }
            // 入力欄を出したまま別の場所を押したときは、前の入力を先に書き込む
            commitImageText()
            imageTextAnchor = point
            return
        }

        guard let draft = imageDraft else { return }
        switch draft {
        case .crop(let rect):
            let current = ImageEditRules.cropRect(in: imageEdits, imageSize: source.size)
            guard ImageEditRules.isValidCrop(rect, in: current) else { return }
            imageEdits.append(.crop(rect.intersection(current)))
        case .stroke(let stroke):
            guard ImageEditRules.isDrawable(stroke) else { return }
            imageEdits.append(.stroke(stroke))
        }
    }

    /// 入力中の文字を書き込みとして確定する。空なら何も残さない。
    /// どの経路を通っても、呼んだあとは入力欄が閉じて空になる
    func commitImageText() {
        guard let anchor = imageTextAnchor, let source = editingImage else {
            cancelImageText()
            return
        }
        let stroke = ImageStroke(
            tool: .text,
            points: [anchor],
            lineWidth: lineWidth(for: .text, imageSize: source.size),
            color: imageColor,
            text: ImageEditRules.sanitizedText(imageText),
            // 打ち終わった時点の大きさで書き込む。入力中に大きさを変えられるようにするため、
            // 入力欄を出した時点の値は覚えない
            fontSize: imageTextSize
        )
        cancelImageText()
        guard ImageEditRules.isDrawable(stroke) else { return }
        imageEdits.append(.stroke(stroke))
    }

    func cancelImageText() {
        imageTextAnchor = nil
        imageText = ""
    }

    /// 文字の大きさを画像ピクセルで指定する。
    /// 範囲外の値は入力欄から届きうるため、受け取る側で必ず丸める
    func setImageTextSize(_ size: CGFloat) {
        // 読み込みが終わるまでは上限が決まらない。既定値のまま触らせない
        guard let source = editingImage else { return }
        imageTextSize = ImageEditRules.clampedFontSize(size, forImageSize: source.size)
    }

    func undoImageEdit() {
        guard !imageEdits.isEmpty else { return }
        imageEdits.removeLast()
        imageEditError = nil
    }

    /// - Parameter mode: 上書き（元のアイテムを書き換える）か、新規（元を残して増やす）か
    func commitImageEditing(mode: ImageSaveMode = .overwrite) {
        guard let item = editingImageItem else { return }
        // 入力欄に残ったままの文字も書き込んでから保存する
        commitImageText()
        // 何も描いていなければ、どちらの保存でも履歴に触れずに閉じる。
        // 新規で増やしても元と同じ画像が並ぶだけで、探すときの邪魔にしかならない
        guard let source = editingImage, ImageEditRules.shouldSave(imageEdits) else {
            endEditing()
            return
        }

        // フル解像度への描き込みはここで一度だけ行う。保存を押した直後の一瞬なので同期で処理する
        guard let output = ImageAnnotationRenderer.render(source: source, edits: imageEdits) else {
            imageEditError = "画像を書き出せませんでした"
            return
        }
        guard ImageEditRules.canStore(byteCount: output.png.count) else {
            imageEditError = "編集後の画像が大きすぎるため保存できません"
            return
        }

        switch mode {
        case .overwrite:
            store.replaceImage(
                output.png,
                pixelWidth: output.pixelWidth,
                pixelHeight: output.pixelHeight,
                for: item.id
            )
            // 同じ ID のまま中身が変わるため、カードのサムネイルを読み直させる
            ThumbnailProvider.shared.invalidate(id: item.id)
        case .addNew:
            // 取り込みと同じ経路に乗せる。重複排除・保持ポリシー・永続化を
            // 二重に書かずに済み、コピーで増えたアイテムと同じ扱いになる
            store.ingest(CapturedContent(
                flavors: ImageEditRules.flavors(forEditedPNG: output.png),
                sourceAppName: item.sourceAppName,
                sourceAppBundleID: item.sourceAppBundleID,
                imageSizeLabel: ImageEditRules.sizeLabel(
                    pixelWidth: output.pixelWidth,
                    pixelHeight: output.pixelHeight
                )
            ))
            // 元のカードは変わらないので、サムネイルの作り直しは要らない
        }
        endEditing()
    }

    private func makeImageDraft(lineWidth: CGFloat) -> ImageEdit? {
        guard let first = imageDraftPoints.first, let last = imageDraftPoints.last else { return nil }
        guard imageTool != .crop else {
            guard imageDraftPoints.count >= 2 else { return nil }
            return .crop(ImageEditRules.rect(from: first, to: last))
        }
        return .stroke(ImageStroke(
            tool: imageTool,
            points: imageDraftPoints,
            lineWidth: lineWidth,
            color: imageColor
        ))
    }

    /// 描き込みの寸法。太さを選べない道具は、選択に関わらず標準の太さで描く
    private func lineWidth(for tool: ImageTool, imageSize: CGSize) -> CGFloat {
        ImageEditRules.lineWidth(
            forImageSize: imageSize,
            weight: tool.usesStyle ? imageWeight : .regular
        )
    }

    // MARK: - 編集の終了

    private func endEditing() {
        let wasImageEditing = isImageEditing
        editingItem = nil
        editingText = ""
        editingOriginalText = ""
        editingDiscardsDecoration = false

        editingImageItem = nil
        editingImage = nil
        imageEdits = []
        imageDraft = nil
        imageDraftPoints = []
        imageTextAnchor = nil
        imageText = ""
        isEditingImageTextSize = false
        imageEditError = nil
        // 読み込み中だった場合、あとから届く結果を捨てさせる
        imageLoadToken = UUID()
        if wasImageEditing { onImageEditingChange?(false) }

        // 編集欄を閉じたあとは検索欄へフォーカスを戻す
        focusToken += 1
    }

    private func ensureSelectionValid() {
        if selectedID == nil || !visible.contains(where: { $0.id == selectedID }) {
            selectedID = visible.first?.id
        }
    }
}
