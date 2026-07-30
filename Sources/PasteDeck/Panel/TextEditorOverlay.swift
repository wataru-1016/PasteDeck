import PasteCore
import SwiftUI

/// ⌘E のテキスト編集画面。パネル内に重ねて表示する。
///
/// 別ウィンドウにするとパネルが key を失って `windowDidResignKey` で閉じてしまうため、
/// オーバーレイにしている。キー操作は `PanelController.handleEditingKey(_:modifiers:)` が
/// 担当する（↩ は改行、⌘↩ で保存、esc で取り消し）。
struct TextEditorOverlay: View {
    @ObservedObject var viewModel: PanelViewModel
    @FocusState private var editorFocused: Bool

    var body: some View {
        ZStack {
            // 背面のカードを押しても編集が閉じないよう全面を覆う。
            // 覆いを押したときは取り消し扱いにする
            Rectangle()
                .fill(.black.opacity(0.5))
                .onTapGesture { viewModel.cancelEditing() }

            editorCard
        }
    }

    private var editorCard: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return VStack(alignment: .leading, spacing: 10) {
            header
            if viewModel.editingDiscardsDecoration {
                decorationWarning
            }
            editor
            footer
        }
        .padding(18)
        .frame(width: 620)
        .background(shape.fill(Color(nsColor: .windowBackgroundColor)))
        .overlay(shape.stroke(Color.primary.opacity(0.14), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 24, y: 8)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.and.pencil")
                .foregroundStyle(Color.accentColor)
            Text("テキストを編集")
                .font(.system(size: 14, weight: .semibold))
            if let name = viewModel.editingItem?.sourceAppName {
                Text(name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var decorationWarning: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text("保存すると書式（文字色・太さ・大きさ）は破棄され、プレーンテキストになります")
        }
        .font(.caption)
        .foregroundStyle(.orange)
    }

    private var editor: some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        return TextEditor(text: $viewModel.editingText)
            .font(.system(size: 13))
            .scrollContentBackground(.hidden)
            .focused($editorFocused)
            .padding(8)
            .frame(height: 150)
            .background(shape.fill(Color.primary.opacity(0.06)))
            .overlay(shape.stroke(
                editorFocused ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.1),
                lineWidth: 1
            ))
            .onAppear {
                // パネル表示直後と同じ理由で、レイアウトが決まってからフォーカスを移す
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { editorFocused = true }
            }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Text("\(viewModel.editingText.count) 文字")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Spacer(minLength: 12)

            Text("⌘↩ 保存　esc 取り消し")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Button("取り消す") { viewModel.cancelEditing() }
            Button("保存") { viewModel.commitEditing() }
                .buttonStyle(.borderedProminent)
        }
    }
}
