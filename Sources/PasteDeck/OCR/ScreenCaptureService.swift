import CoreGraphics
import Foundation
import ImageIO
import PasteCore

/// macOS 標準の screencapture コマンドで範囲を選ばせ、CGImage として返す
enum ScreenCaptureService {
    enum Outcome {
        case captured(CGImage)
        /// esc で閉じられた。何も知らせずに戻る
        case cancelled
        case failed
    }

    /// 実行中の screencapture を保持する。`Process` は自分の寿命を保証しないため、
    /// 呼び出し元が参照を手放すと `terminationHandler` が呼ばれる前に解放されうる
    private static let runningLock = NSLock()
    private static var runningTasks: [Process] = []

    /// 範囲選択を始める。`completion` はバックグラウンドスレッドで呼ばれる
    static func selectRegion(completion: @escaping (Outcome) -> Void) {
        let path = NSTemporaryDirectory() + "pastedeck-ocr-\(UUID().uuidString).png"

        // macOS 標準の screencapture コマンドを利用する
        //   -i: マウスで範囲をドラッグ選択（esc でキャンセル可能）
        //   -x: シャッター音を鳴らさない
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        task.arguments = ["-i", "-x", path]
        task.terminationHandler = { finished in
            let outcome = read(path: path)
            release(finished)
            completion(outcome)
        }

        retain(task)
        do {
            try task.run()
        } catch {
            Log.error("範囲選択を開始できませんでした: \(error)")
            release(task)
            completion(.failed)
        }
    }

    private static func retain(_ task: Process) {
        runningLock.lock()
        defer { runningLock.unlock() }
        runningTasks.append(task)
    }

    private static func release(_ task: Process) {
        runningLock.lock()
        defer { runningLock.unlock() }
        runningTasks.removeAll { $0 === task }
    }

    /// 撮れた PNG を読む。読めても読めなくても一時ファイルは必ず片付ける
    private static func read(path: String) -> Outcome {
        defer { try? FileManager.default.removeItem(atPath: path) }

        // esc でキャンセルされた場合はファイルが生成されない
        guard FileManager.default.fileExists(atPath: path) else { return .cancelled }

        // ピクセルは ImageIO から取る。NSImage 経由だと解像度を加味した論理サイズになり、
        // Retina のキャプチャが半分の大きさで認識にかかってしまう
        let url = URL(fileURLWithPath: path)
        // CGImage は既定では描画時に遅延デコードする。直後に一時ファイルを削除しても
        // Vision が読めるよう、ここでピクセルを完全にデコードして保持させる
        let options = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, options)
        else {
            Log.error("撮影した画像を読み込めませんでした: \(path)")
            return .failed
        }
        return .captured(image)
    }
}
