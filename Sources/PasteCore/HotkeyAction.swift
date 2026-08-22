import Foundation

/// グローバルホットキーの割り当て先（純粋な値・テスト対象）。
/// Carbon の `EventHotKeyID.id` と 1 対 1 で対応する
public enum HotkeyAction: String, CaseIterable, Equatable, Sendable {
    case panel
    case ocr

    /// `EventHotKeyID.id`。押されたキーからこの値で action を逆引きする。
    /// 0 は未設定と紛らわしいので 1 から振る
    public var carbonID: UInt32 {
        switch self {
        case .panel: return 1
        case .ocr: return 2
        }
    }

    public var defaultShortcut: HotkeyShortcut {
        switch self {
        case .panel: return .default                                                   // ⇧⌘V
        case .ocr: return HotkeyShortcut(keyCode: 26, modifiers: [.command, .shift])   // ⇧⌘7
        }
    }

    /// 設定画面の行見出しと、重複エラーの文面に使う名前
    public var displayName: String {
        switch self {
        case .panel: return "履歴パネル"
        case .ocr: return "画面読み取り"
        }
    }

    public static func action(forCarbonID id: UInt32) -> HotkeyAction? {
        allCases.first { $0.carbonID == id }
    }
}
