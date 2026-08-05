import PasteCore
import SwiftUI

/// ショートカット設定ウィンドウの状態。キー入力の受け取りは
/// `ShortcutSettingsController` が担い、ここは表示のための値だけを持つ
final class ShortcutSettingsModel: ObservableObject {
    @Published var shortcut: HotkeyShortcut
    /// キー入力の待ち受け中か。待ち受けを止めている間は現在の設定をそのまま見せる
    @Published var isRecording = true
    /// 登録できなかった理由。押し直せるよう、表示したまま待ち受けは続ける
    @Published var errorMessage: String?

    init(shortcut: HotkeyShortcut) {
        self.shortcut = shortcut
    }
}

struct ShortcutSettingsView: View {
    @ObservedObject var model: ShortcutSettingsModel

    let onReset: () -> Void
    let onClose: () -> Void

    private static let keycapFontSize: Double = 28

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("履歴パネルを開くショートカット")
                    .font(.system(size: 15, weight: .semibold))
                Text("押したキーの組み合わせがそのまま登録されます。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            keycap

            status

            Spacer(minLength: 0)

            HStack {
                Button("デフォルトに戻す", action: onReset)
                    .disabled(model.shortcut == .default)
                Spacer()
                Button("完了", action: onClose)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 380, height: 250)
    }

    /// 現在の組み合わせ。待ち受け中は枠を強調して「ここが変わる」ことを示す
    private var keycap: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return HStack {
            Spacer()
            KeycapView(
                key: model.shortcut.displayString,
                fontSize: Self.keycapFontSize,
                minWidth: 0
            )
            Spacer()
        }
        .padding(.vertical, 14)
        .background(shape.fill(Color.primary.opacity(model.isRecording ? 0.05 : 0.02)))
        .overlay(
            shape.strokeBorder(
                model.isRecording ? Color.accentColor : Color.primary.opacity(0.12),
                lineWidth: model.isRecording ? 2 : 1
            )
        )
    }

    @ViewBuilder
    private var status: some View {
        if let errorMessage = model.errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        } else if model.isRecording {
            Text("新しいキーを押してください（⌘ ⌃ ⌥ のいずれかを含む組み合わせ）")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
