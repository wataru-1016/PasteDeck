import SwiftUI

/// キーボードのキートップに寄せたチップ。面をわずかに起こして輪郭を付ける。
/// パネル上部のキーヒントと、ショートカット設定の現在値表示で共有する
struct KeycapView: View {
    let key: String
    var fontSize: Double = 12
    /// `⌘⌫` のような 2 文字のキーと `↩` のような 1 文字のキーで大きさが揃うようにする下限幅
    var minWidth: Double = 27

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: fontSize * 0.42, style: .continuous)
        return Text(key)
            .font(.system(size: fontSize, weight: .semibold))
            .foregroundStyle(.primary.opacity(0.8))
            .padding(.horizontal, fontSize * 0.58)
            .padding(.vertical, fontSize * 0.25)
            .frame(minWidth: minWidth)
            .background(shape.fill(Color.primary.opacity(0.09)))
            .overlay(shape.stroke(Color.primary.opacity(0.14), lineWidth: 1))
    }
}
