import PasteCore
import SwiftUI

/// パネルのルートビュー: 上部バー（検索・フィルター・ヒント）と横スクロールのカード列
struct PanelView: View {
    @ObservedObject var viewModel: PanelViewModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            topBar
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(panelBackground)
        .overlay(editorOverlay)
        .clipShape(panelShape)
        .overlay(panelShape.stroke(.white.opacity(0.14), lineWidth: 1))
        .onChange(of: viewModel.focusToken) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                searchFocused = true
            }
        }
    }

    private var panelShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(cornerRadii: .init(
            topLeading: 18,
            bottomLeading: 0,
            bottomTrailing: 0,
            topTrailing: 18
        ))
    }

    private var panelBackground: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            LinearGradient(
                colors: [Color.white.opacity(0.05), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    /// ⌘E の編集画面。パネル内に重ねる（別ウィンドウにするとパネルが閉じてしまう）
    @ViewBuilder
    private var editorOverlay: some View {
        if viewModel.editingItem != nil {
            TextEditorOverlay(viewModel: viewModel)
        } else if viewModel.isImageEditing {
            ImageEditorOverlay(viewModel: viewModel)
        }
    }

    // MARK: - 上部バー

    private var topBar: some View {
        HStack(spacing: 18) {
            HStack(spacing: 7) {
                Image(systemName: "square.stack.fill")
                    .foregroundStyle(Color.accentColor)
                Text("PasteDeck")
                    .font(.system(.headline, design: .rounded))
            }

            searchField

            HStack(spacing: 7) {
                pinnedFilterChip
                // 押す前にキーが分かるよう、ボタンのすぐ横にも出す。右端の一覧
                // （KeyHintsView）は固定幅の検索欄と横幅を取り合って隠れることがあり、
                // ツールチップはポインタを合わせてからでないと読めない
                KeycapView(key: "⇧⌘P")
            }

            Spacer(minLength: 12)

            Text("\(viewModel.visible.count) 件")
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)

            KeyHintsView(alternatePaste: viewModel.alternatePaste)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("検索…", text: $viewModel.query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($searchFocused)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(width: 260)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(searchFocused ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var pinnedFilterChip: some View {
        Button {
            viewModel.pinnedOnly.toggle()
        } label: {
            Label("ピン留め", systemImage: "pin.fill")
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(viewModel.pinnedOnly ? Color.accentColor : Color.primary.opacity(0.06))
                )
                .foregroundStyle(viewModel.pinnedOnly ? Color.white : Color.secondary)
        }
        .buttonStyle(.plain)
        // 横のキーキャップだけでは「押すと何が起きるか」までは分からないため、
        // 動作の説明はツールチップに残す
        .help("ピン留めした項目だけを表示（⇧⌘P）")
    }

    // MARK: - カード列

    @ViewBuilder
    private var content: some View {
        if viewModel.visible.isEmpty {
            emptyState
        } else {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        // ⌘1〜⌘9 は表示中の並びで数えるため、位置ごと渡す。
                        // 検索で絞り込むと、絞り込んだ結果の先頭が ⌘1 になる
                        ForEach(Array(viewModel.visible.enumerated()), id: \.element.id) { index, item in
                            ItemCardView(
                                item: item,
                                isSelected: item.id == viewModel.selectedID,
                                quickPasteKey: NumberKeyRules.quickPasteLabel(forIndex: index),
                                viewModel: viewModel
                            )
                            .id(item.id)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 18)
                }
                .onChange(of: viewModel.selectedID) {
                    guard let id = viewModel.selectedID else { return }
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(id)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: viewModel.query.isEmpty ? "clipboard" : "magnifyingglass")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.quaternary)
            if viewModel.query.isEmpty {
                Text(viewModel.pinnedOnly ? "ピン留めした項目はまだありません" : "コピーした内容がここに並びます")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                if !viewModel.pinnedOnly {
                    Text("テキスト・リンク・画像・ファイルに対応しています")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            } else {
                Text("「\(viewModel.query)」に一致する履歴はありません")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
