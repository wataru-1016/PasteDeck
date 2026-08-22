import PasteCore
import SwiftUI

/// ショートカット設定ウィンドウの状態。キー入力の受け取りは
/// `ShortcutSettingsController` が担い、ここは表示のための値だけを持つ
final class ShortcutSettingsModel: ObservableObject {
    @Published var shortcuts: [HotkeyAction: HotkeyShortcut]
    /// どの行のキーを待ち受けているか。nil の間はキー入力をそのままウィンドウへ流す。
    /// 行を選ばせてから記録するのは、2 枠を同時に開くと入力先が分からなくなるため
    @Published var recordingAction: HotkeyAction?
    /// 登録できなかった理由。押し直せるよう、表示したまま待ち受けは続ける
    @Published var errorMessage: String?

    init(shortcuts: [HotkeyAction: HotkeyShortcut]) {
        self.shortcuts = shortcuts
    }

    func shortcut(for action: HotkeyAction) -> HotkeyShortcut {
        shortcuts[action] ?? action.defaultShortcut
    }
}

struct ShortcutSettingsView: View {
    @ObservedObject var model: ShortcutSettingsModel

    let onStartRecording: (HotkeyAction) -> Void
    let onReset: (HotkeyAction) -> Void
    let onClose: () -> Void

    private static let keycapFontSize: Double = 22

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("ショートカット")
                    .font(.system(size: 15, weight: .semibold))
                Text("行をクリックしてから、新しいキーの組み合わせを押してください。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 10) {
                ForEach(HotkeyAction.allCases, id: \.self) { action in
                    row(for: action)
                }
            }

            status

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("完了", action: onClose)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 420, height: 330)
    }

    /// 1 つの action の行。記録中は枠を強調して「ここが変わる」ことを示す
    private func row(for action: HotkeyAction) -> some View {
        let isRecording = model.recordingAction == action
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        let shortcut = model.shortcut(for: action)
        return HStack(spacing: 12) {
            Text(action.displayName)
                .font(.system(size: 13, weight: .medium))
            Spacer()
            KeycapView(
                key: shortcut.displayString,
                fontSize: Self.keycapFontSize,
                minWidth: 0
            )
            Button("初期設定に戻す") { onReset(action) }
                .disabled(shortcut == action.defaultShortcut)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(shape.fill(Color.primary.opacity(isRecording ? 0.05 : 0.02)))
        .overlay(
            shape.strokeBorder(
                isRecording ? Color.accentColor : Color.primary.opacity(0.12),
                lineWidth: isRecording ? 2 : 1
            )
        )
        .contentShape(shape)
        .onTapGesture { onStartRecording(action) }
    }

    @ViewBuilder
    private var status: some View {
        if let errorMessage = model.errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        } else if let action = model.recordingAction {
            Text("「\(action.displayName)」の新しいキーを押してください（⌘ ⌃ ⌥ のいずれかを含む組み合わせ）")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text("変更したい行をクリックしてください。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
