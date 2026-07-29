import Foundation
import PasteCore

/// 履歴保持ポリシーの UserDefaults 永続化。
/// 0 を「無制限 / 無期限」として保存し、未設定時はデフォルト（500 件・無期限）を返す
enum RetentionPreferences {
    private static let maxItemsKey = "retentionMaxItems"
    private static let maxAgeKey = "retentionMaxAgeSeconds"

    static func load() -> RetentionPolicy {
        let defaults = UserDefaults.standard
        let storedItems = defaults.object(forKey: maxItemsKey) as? Int
        let storedAge = defaults.object(forKey: maxAgeKey) as? Double
        return RetentionPolicy(
            maxItems: storedItems.map { $0 <= 0 ? nil : $0 } ?? RetentionPolicy.default.maxItems,
            maxAge: storedAge.map { $0 <= 0 ? nil : $0 } ?? RetentionPolicy.default.maxAge
        )
    }

    static func save(_ policy: RetentionPolicy) {
        let defaults = UserDefaults.standard
        defaults.set(policy.maxItems ?? 0, forKey: maxItemsKey)
        defaults.set(policy.maxAge ?? 0, forKey: maxAgeKey)
    }
}
