import Foundation

/// 履歴をいつまで保持するかのポリシー。
/// ピン留めされたアイテムはどの設定でも削除対象にならない。
public struct RetentionPolicy: Equatable {
    /// 保持する最大件数。nil は無制限
    public var maxItems: Int?
    /// 保持期間（秒）。nil は無期限
    public var maxAge: TimeInterval?

    public static let `default` = RetentionPolicy(maxItems: CaptureRules.maxItems, maxAge: nil)

    public init(maxItems: Int?, maxAge: TimeInterval?) {
        self.maxItems = maxItems
        self.maxAge = maxAge
    }
}
