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

    /// ⌘E で編集中のアイテム。nil なら編集していない
    @Published private(set) var editingItem: ClipboardItem?
    @Published var editingText = ""
    /// 保存すると装飾が破棄されるか。編集画面での事前警告に使う
    @Published private(set) var editingDiscardsDecoration = false

    private var editingOriginalText = ""

    let store: HistoryStore
    /// アイテム決定時（Enter / ダブルクリック）の処理。PanelController が設定する
    var onActivate: ((ClipboardItem, _ plainTextOnly: Bool) -> Void)?

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

    func activate(_ item: ClipboardItem, plainTextOnly: Bool = false) {
        onActivate?(item, plainTextOnly)
    }

    func activateSelected(plainTextOnly: Bool) {
        guard let item = selectedItem else { return }
        activate(item, plainTextOnly: plainTextOnly)
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

    // MARK: - テキスト編集（⌘E）

    /// 選択中アイテムの編集を開始する。
    /// 編集対象は `preview`（先頭 400 文字）ではなく flavor に入っている全文
    func beginEditingSelected() {
        guard let item = selectedItem,
              TextEditRules.canEdit(kind: item.kind, byteSize: item.byteSize)
        else { return }

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

    private func endEditing() {
        editingItem = nil
        editingText = ""
        editingOriginalText = ""
        editingDiscardsDecoration = false
        // 編集欄を閉じたあとは検索欄へフォーカスを戻す
        focusToken += 1
    }

    private func ensureSelectionValid() {
        if selectedID == nil || !visible.contains(where: { $0.id == selectedID }) {
            selectedID = visible.first?.id
        }
    }
}
