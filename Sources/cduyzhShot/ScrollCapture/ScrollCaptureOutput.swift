import AppKit

/// PNG 与剪贴板编码不占用交互线程；成功写盘后才发出保存通知。
enum ScrollCaptureOutput {
    static func deliver(_ image: CGImage) {
        let prefs = UserPreferences.shared
        let directory = prefs.saveDirectoryURL
        let copy = prefs.autoCopyToClipboard
        let copyAsFile = prefs.copyAsTempFileToClipboard
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH.mm.ss"
        let file = directory.appendingPathComponent("cduyzhShot_Scroll_\(formatter.string(from: Date()))_\(UUID().uuidString.prefix(4)).png")
        DispatchQueue.global(qos: .userInitiated).async {
            let write: Result<Void, Error> = Result {
                guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                try data.write(to: file, options: .atomic)
            }
            let clipboard = copy ? PasteboardHelper.prepareImage(image, alsoAsFile: copyAsFile) : nil
            DispatchQueue.main.async {
                let copied = clipboard.map { PasteboardHelper.publish($0) } ?? false
                var saved: URL?
                switch write {
                case .success:
                    saved = file
                    NotificationHelper.notifyScreenshotSaved(url: file)
                case .failure(let error):
                    let alert = NSAlert()
                    alert.messageText = "长截图未能保存"
                    alert.informativeText = "\(error.localizedDescription)\n\(copied ? "图片已复制到剪贴板，可先粘贴保留。" : "请检查保存目录的可写权限后重试。")"
                    alert.runModal()
                }
                SoundManager.shared.playCameraShutterSound()
                FloatingThumbnailWindow.shared.show(image: image, fileURL: saved,
                    message: copied ? "长截图已复制，可直接 ⌘V 粘贴" : (saved != nil ? "长截图已保存" : "长截图保存失败"))
            }
        }
    }
}
