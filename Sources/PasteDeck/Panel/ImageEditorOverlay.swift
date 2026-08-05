import AppKit
import PasteCore
import SwiftUI

extension ImageTool {
    var label: String {
        switch self {
        case .pen: return "ペン"
        case .redaction: return "黒塗り"
        case .arrow: return "矢印"
        case .crop: return "トリミング"
        }
    }

    var symbolName: String {
        switch self {
        case .pen: return "scribble"
        case .redaction: return "rectangle.fill"
        case .arrow: return "arrow.up.right"
        case .crop: return "crop"
        }
    }

    /// 道具を切り替える数字キー。`PanelController.tool(forKeyCode:)` と並びを合わせる
    var shortcutKey: String {
        guard let index = Self.allCases.firstIndex(of: self) else { return "" }
        return String(index + 1)
    }
}

/// ⌘E の画像編集画面。テキスト編集と同じくパネル内に重ねる
/// （別ウィンドウにするとパネルが key を失って閉じてしまう）。
///
/// キー操作は `PanelController.handleImageEditingKey(_:modifiers:)` が担当する
/// （⌘↩ で保存、⌘Z で取り消し、esc で中止、1〜4 で道具の切り替え）
struct ImageEditorOverlay: View {
    @ObservedObject var viewModel: PanelViewModel

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.55))
                .contentShape(Rectangle())
                // テキスト編集と違い、覆いを押しても閉じない。
                // 描き込みは打ち直しが利かず、誤って捨てる代償が大きい
                .onTapGesture {}

            editorCard
        }
    }

    private var editorCard: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return VStack(alignment: .leading, spacing: 10) {
            header
            if let error = viewModel.imageEditError {
                warning(error)
            }
            toolbar
            canvas
            footer
        }
        .padding(16)
        .frame(maxWidth: 1120)
        .background(shape.fill(Color(nsColor: .windowBackgroundColor)))
        .overlay(shape.stroke(Color.primary.opacity(0.14), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 24, y: 8)
        .padding(20)
    }

    // MARK: - ヘッダー

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "photo.badge.checkmark")
                .foregroundStyle(Color.accentColor)
            Text("画像を編集")
                .font(.system(size: 14, weight: .semibold))
            if let name = viewModel.editingImageItem?.sourceAppName {
                Text(name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if let source = viewModel.editingImage {
                Text(currentSizeLabel(source))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func warning(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(message)
        }
        .font(.caption)
        .foregroundStyle(.orange)
    }

    /// 切り抜きを反映した、書き出し後の大きさ
    private func currentSizeLabel(_ source: ImageEditSource) -> String {
        let rect = ImageEditRules.cropRect(in: viewModel.imageEdits, imageSize: source.size)
        return ImageEditRules.sizeLabel(
            pixelWidth: Int(rect.width.rounded()),
            pixelHeight: Int(rect.height.rounded())
        )
    }

    // MARK: - 道具

    private var toolbar: some View {
        HStack(spacing: 8) {
            ForEach(ImageTool.allCases, id: \.self) { tool in
                ToolChip(
                    tool: tool,
                    isSelected: viewModel.imageTool == tool,
                    action: { viewModel.imageTool = tool }
                )
            }

            Spacer(minLength: 12)

            Button {
                viewModel.undoImageEdit()
            } label: {
                Label("取り消す", systemImage: "arrow.uturn.backward")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(viewModel.imageEdits.isEmpty ? Color.secondary : Color.primary)
            .disabled(viewModel.imageEdits.isEmpty)
            .help("直前の操作を取り消す（⌘Z）")
        }
    }

    // MARK: - キャンバス

    private var canvas: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(0.06))

            if let source = viewModel.editingImage {
                ImageEditCanvas(
                    source: source,
                    edits: viewModel.imageEdits,
                    draft: viewModel.imageDraft,
                    onDragChanged: viewModel.updateImageDraft,
                    onDragEnded: viewModel.commitImageDraft
                )
                .padding(8)
            } else if viewModel.imageEditError == nil {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - フッター

    private var footer: some View {
        HStack(spacing: 14) {
            Text("\(viewModel.imageEdits.count) 操作")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Spacer(minLength: 12)

            Text("1〜4 道具　⌘Z 取り消し　⌘↩ 保存　esc 中止")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Button("取り消す") { viewModel.cancelEditing() }
            Button("保存") { viewModel.commitImageEditing() }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.editingImage == nil)
        }
    }
}

/// 道具のボタン。上部バーのピン留めチップと意匠を揃える
private struct ToolChip: View {
    let tool: ImageTool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: tool.symbolName)
                    .font(.system(size: 11, weight: .semibold))
                Text(tool.label)
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(isSelected ? Color.accentColor : Color.primary.opacity(0.06))
            )
            .foregroundStyle(isSelected ? Color.white : Color.secondary)
        }
        .buttonStyle(.plain)
        .help("\(tool.label)（\(tool.shortcutKey)）")
    }
}

/// 画像と描き込みを重ねて表示し、ドラッグを画像座標へ変換して伝える。
///
/// 縮小版の画像は 1 枚だけ持ち、トリミングは描く位置をずらして表現する。
/// 切り抜くたびに画像を作り直すより速く、切り抜きの取り消しも位置を戻すだけで済む
private struct ImageEditCanvas: View {
    let source: ImageEditSource
    let edits: [ImageEdit]
    let draft: ImageEdit?
    let onDragChanged: (CGPoint) -> Void
    let onDragEnded: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let cropRect = ImageEditRules.cropRect(in: edits, imageSize: source.size)
            let fit = ImageEditRules.fit(sourceSize: cropRect.size, in: geometry.size)

            Canvas { context, _ in
                draw(in: &context, fit: fit, cropRect: cropRect)
            }
            .contentShape(Rectangle())
            .gesture(
                // minimumDistance を 0 にして、点を打つだけのペン操作も拾えるようにする
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        onDragChanged(ImageEditRules.imagePoint(
                            fromCanvas: value.location,
                            fit: fit,
                            cropRect: cropRect
                        ))
                    }
                    .onEnded { _ in onDragEnded() }
            )
        }
    }

    // MARK: - 描画

    private func draw(
        in context: inout GraphicsContext,
        fit: ImageEditRules.CanvasFit,
        cropRect: CGRect
    ) {
        guard fit.displayRect.width > 0, fit.displayRect.height > 0 else { return }
        context.clip(to: Path(fit.displayRect))

        // 切り抜き範囲が表示領域と重なるよう、画像全体をずらして描く
        let pointsPerPixel = 1 / fit.scale
        context.draw(
            Image(nsImage: source.display),
            in: CGRect(
                x: fit.displayRect.minX - cropRect.minX * pointsPerPixel,
                y: fit.displayRect.minY - cropRect.minY * pointsPerPixel,
                width: source.size.width * pointsPerPixel,
                height: source.size.height * pointsPerPixel
            )
        )

        for stroke in ImageEditRules.strokes(in: edits) {
            draw(stroke, in: &context, fit: fit, cropRect: cropRect)
        }

        switch draft {
        case .stroke(let stroke):
            draw(stroke, in: &context, fit: fit, cropRect: cropRect)
        case .crop(let rect):
            drawCropPreview(rect, in: &context, fit: fit, cropRect: cropRect)
        case nil:
            break
        }
    }

    /// 保存時（`ImageAnnotationRenderer`）と同じ形になるよう、頂点は画像座標で求めてから変換する。
    /// 表示座標のまま計算すると、縮小率によって矢印の頭の大きさがずれる
    private func draw(
        _ stroke: ImageStroke,
        in context: inout GraphicsContext,
        fit: ImageEditRules.CanvasFit,
        cropRect: CGRect
    ) {
        let color = stroke.tool.color.swiftUIColor
        let lineWidth = stroke.lineWidth / fit.scale
        let toCanvas = { (point: CGPoint) in
            ImageEditRules.canvasPoint(fromImage: point, fit: fit, cropRect: cropRect)
        }

        switch stroke.tool {
        case .pen:
            guard let first = stroke.points.first else { return }
            guard stroke.points.count > 1 else {
                let center = toCanvas(first)
                let dot = CGRect(
                    x: center.x - lineWidth / 2,
                    y: center.y - lineWidth / 2,
                    width: lineWidth,
                    height: lineWidth
                )
                context.fill(Path(ellipseIn: dot), with: .color(color))
                return
            }
            var path = Path()
            path.addLines(stroke.points.map(toCanvas))
            context.stroke(
                path,
                with: .color(color),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            )

        case .redaction:
            guard let rect = stroke.rect else { return }
            let canvasRect = ImageEditRules.rect(
                from: toCanvas(CGPoint(x: rect.minX, y: rect.minY)),
                to: toCanvas(CGPoint(x: rect.maxX, y: rect.maxY))
            )
            context.fill(Path(canvasRect), with: .color(color))

        case .arrow:
            guard let endpoints = stroke.endpoints,
                  let geometry = ImageEditRules.arrowGeometry(
                      from: endpoints.from,
                      to: endpoints.to,
                      lineWidth: stroke.lineWidth
                  )
            else { return }
            var shaft = Path()
            shaft.move(to: toCanvas(endpoints.from))
            shaft.addLine(to: toCanvas(geometry.shaftEnd))
            context.stroke(
                shaft,
                with: .color(color),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )

            var head = Path()
            head.move(to: toCanvas(geometry.tip))
            head.addLine(to: toCanvas(geometry.left))
            head.addLine(to: toCanvas(geometry.right))
            head.closeSubpath()
            context.fill(head, with: .color(color))

        case .crop:
            break
        }
    }

    /// 切り抜き範囲の外を暗くして、残る部分をそのまま見せる
    private func drawCropPreview(
        _ rect: CGRect,
        in context: inout GraphicsContext,
        fit: ImageEditRules.CanvasFit,
        cropRect: CGRect
    ) {
        let canvasRect = ImageEditRules.rect(
            from: ImageEditRules.canvasPoint(
                fromImage: CGPoint(x: rect.minX, y: rect.minY),
                fit: fit,
                cropRect: cropRect
            ),
            to: ImageEditRules.canvasPoint(
                fromImage: CGPoint(x: rect.maxX, y: rect.maxY),
                fit: fit,
                cropRect: cropRect
            )
        )

        var mask = Path(fit.displayRect)
        mask.addRect(canvasRect)
        context.fill(mask, with: .color(.black.opacity(0.5)), style: FillStyle(eoFill: true))
        context.stroke(Path(canvasRect), with: .color(.white), lineWidth: 1)
    }
}
