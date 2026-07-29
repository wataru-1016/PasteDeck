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

    // MARK: - 上部バー

    private var topBar: some View {
        HStack(spacing: 14) {
            HStack(spacing: 7) {
                Image(systemName: "square.stack.fill")
                    .foregroundStyle(Color.accentColor)
                Text("PasteDeck")
                    .font(.system(.headline, design: .rounded))
            }

            searchField

            pinnedFilterChip

            Spacer(minLength: 12)

            Text("\(viewModel.visible.count) 件")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Text("↩ 貼り付け　⌥↩ プレーン　⌘P ピン　⌘⌫ 削除　esc 閉じる")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
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
        .help("ピン留めした項目だけを表示")
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
                        ForEach(viewModel.visible) { item in
                            ItemCardView(
                                item: item,
                                isSelected: item.id == viewModel.selectedID,
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
