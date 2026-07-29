import AppKit
import PasteCore

/// NSPasteboard には変更通知 API がないため、changeCount をポーリングして
/// 新しいコピーを検出し HistoryStore へ取り込む。
final class ClipboardMonitor {
    private static let pollInterval: TimeInterval = 0.25

    private let store: HistoryStore
    private var timer: Timer?
    private var lastChangeCount = -1
    private var ignoredChangeCount: Int?

    var isPaused = false

    init(store: HistoryStore) {
        self.store = store
    }

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        poll()
    }

    /// PasteService が自分で書き込んだ直後に呼び、その変更を履歴に再取り込みしない
    func ignoreNextChange() {
        ignoredChangeCount = NSPasteboard.general.changeCount
    }

    private func poll() {
        let pasteboard = NSPasteboard.general
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount

        if changeCount == ignoredChangeCount { return }
        guard !isPaused else { return }
        guard let types = pasteboard.types, !types.isEmpty else { return }
        guard !CaptureRules.shouldSkip(types: types.map(\.rawValue)) else { return }

        var flavors: [String: Data] = [:]
        for type in CaptureRules.storedTextTypes {
            if let data = pasteboard.data(forType: NSPasteboard.PasteboardType(type)), !data.isEmpty {
                flavors[type] = data
            }
        }

        var imageSizeLabel: String?
        if let png = pasteboard.data(forType: .png), !png.isEmpty {
            flavors["public.png"] = png
            imageSizeLabel = Self.imageSizeLabel(from: png)
        } else if let tiff = pasteboard.data(forType: .tiff), !tiff.isEmpty {
            // TIFF は巨大になりやすいので PNG へ変換して保存する
            if let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                flavors["public.png"] = png
                imageSizeLabel = "\(rep.pixelsWide) × \(rep.pixelsHigh)"
            }
        }

        let fileURLs = (pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL])?.map(\.absoluteString) ?? []

        guard !flavors.isEmpty || !fileURLs.isEmpty else { return }

        let frontApp = NSWorkspace.shared.frontmostApplication
        store.ingest(CapturedContent(
            flavors: flavors,
            fileURLs: fileURLs,
            sourceAppName: frontApp?.localizedName,
            sourceAppBundleID: frontApp?.bundleIdentifier,
            imageSizeLabel: imageSizeLabel
        ))
    }

    private static func imageSizeLabel(from data: Data) -> String? {
        guard let rep = NSBitmapImageRep(data: data) else { return nil }
        return "\(rep.pixelsWide) × \(rep.pixelsHigh)"
    }
}
