import AppKit
import ImageIO
import PasteCore
import QuickLookThumbnailing
import UniformTypeIdentifiers

/// コピー元アプリのアイコン取得（キャッシュ付き）
enum AppIconProvider {
    private static let cache = NSCache<NSString, NSImage>()

    static func icon(forBundleID bundleID: String?) -> NSImage {
        let key = (bundleID ?? "generic") as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        let icon: NSImage
        if let bundleID,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            icon = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            icon = NSWorkspace.shared.icon(for: .applicationBundle)
        }
        cache.setObject(icon, forKey: key)
        return icon
    }
}

/// ファイルアイテムの Quick Look サムネイル生成（非同期・キャッシュ付き）。
/// 画像に限らず PDF・動画なども Finder と同等のプレビューが得られる。
final class FileThumbnailProvider {
    static let shared = FileThumbnailProvider()

    private let cache = NSCache<NSString, NSImage>()

    init() {
        cache.countLimit = 200
    }

    func thumbnail(
        for fileURL: URL,
        cacheKey: String,
        completion: @escaping (NSImage?) -> Void
    ) {
        let key = cacheKey as NSString
        if let cached = cache.object(forKey: key) {
            completion(cached)
            return
        }

        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let request = QLThumbnailGenerator.Request(
            fileAt: fileURL,
            size: CGSize(width: 320, height: 200),
            scale: scale,
            representationTypes: .thumbnail
        )
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] representation, _ in
            let image = representation?.nsImage
            DispatchQueue.main.async {
                if let image {
                    self?.cache.setObject(image, forKey: key)
                }
                completion(image)
            }
        }
    }
}

/// 画像アイテムのサムネイル読み込み（ディスクから非同期・縮小してキャッシュ）。
/// フル解像度で NSImage 展開するとカード表示に対して過大なメモリを食うため、
/// ImageIO で表示サイズ相当までダウンサンプリングする
final class ThumbnailProvider {
    private static let maxPixelSize = 640

    static let shared = ThumbnailProvider()

    private let cache = NSCache<NSString, NSImage>()

    init() {
        cache.countLimit = 100
    }

    func thumbnail(
        for item: ClipboardItem,
        persistence: Persistence,
        completion: @escaping (NSImage?) -> Void
    ) {
        let key = item.id.uuidString as NSString
        if let cached = cache.object(forKey: key) {
            completion(cached)
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let flavors = persistence.loadFlavors(id: item.id)
            let data = flavors?["public.png"] ?? flavors?["public.tiff"]
            let image = data.flatMap { Self.downsampledImage(from: $0) }
            DispatchQueue.main.async {
                if let image {
                    self?.cache.setObject(image, forKey: key)
                }
                completion(image)
            }
        }
    }

    private static func downsampledImage(from data: Data) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
