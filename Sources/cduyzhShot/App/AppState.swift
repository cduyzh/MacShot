import AppKit

public final class AppState {
    public static let shared = AppState()

    private let prefs = UserPreferences.shared
    private let hotkeys = HotkeyManager.shared

    private init() {}

    public func setup() {
        registerAllHotkeys()
    }

    public func registerAllHotkeys() {
        // Screenshot Hotkey (Default: Control + A)
        hotkeys.register(name: "screenshot", combo: prefs.hotkeyScreenshot) { [weak self] in
            self?.triggerScreenshot()
        }

        // Recording Hotkey (Default: Control + [)
        hotkeys.register(name: "recording", combo: prefs.hotkeyRecording) { [weak self] in
            self?.triggerScreenRecording()
        }

        // Scroll Screenshot Hotkey (Default: Option + S)
        hotkeys.register(name: "scroll_screenshot", combo: prefs.hotkeyScroll) { [weak self] in
            self?.triggerScrollScreenshot()
        }

        // Pin Hotkey (Default: Option + P)
        hotkeys.register(name: "pin", combo: prefs.hotkeyPin) { [weak self] in
            self?.triggerPinFromClipboard()
        }
    }

    public func triggerScreenshot() {
        if StatusPanelController.deferCaptureIfPresented({ [weak self] in self?.triggerScreenshot() }) { return }
        guard Permissions.hasScreenRecordingPermission else {
            Permissions.requestScreenRecordingPermission(promptUser: true)
            return
        }
        ScreenshotOverlayController.shared.startCapture()
    }

    public func triggerScrollScreenshot() {
        if StatusPanelController.deferCaptureIfPresented({ [weak self] in self?.triggerScrollScreenshot() }) { return }
        guard Permissions.hasScreenRecordingPermission else {
            Permissions.requestScreenRecordingPermission(promptUser: true)
            return
        }
        ScreenshotOverlayController.shared.startCapture(scrollModeDirect: true)
    }

    public func triggerScreenRecording() {
        if StatusPanelController.deferCaptureIfPresented({ [weak self] in self?.triggerScreenRecording() }) { return }
        guard Permissions.hasScreenRecordingPermission else {
            Permissions.requestScreenRecordingPermission(promptUser: true)
            return
        }

        if ScreenRecorder.shared.isRecording {
            ScreenRecorder.shared.stopRecording()
        } else {
            ScreenRecorder.shared.startRecording(capturesSystemAudio: prefs.captureSystemAudio) { result in
                switch result {
                case .success(let url):
                    print("[AppState] Screen recording saved at \(url)")
                case .failure(let error):
                    print("[AppState] Screen recording error: \(error)")
                }
            }
        }
    }

    public func triggerPinFromClipboard() {
        // Check if pasteboard has image
        let pb = NSPasteboard.general
        if let image = NSImage(pasteboard: pb), let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            PinManager.shared.pin(image: cgImage)
            SoundManager.shared.playCameraShutterSound()
        } else {
            // If no image on clipboard, take screenshot first
            triggerScreenshot()
        }
    }

    public func triggerStudioFromClipboardOrOpen() {
        let pb = NSPasteboard.general
        if let image = NSImage(pasteboard: pb), let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            ScreenshotStudioWindowController.shared.openStudio(image: cgImage)
        } else {
            let panel = NSOpenPanel()
            panel.title = "选择要美化的图片"
            panel.allowedContentTypes = [.png, .jpeg, .tiff]
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            panel.begin { response in
                if response == .OK, let url = panel.url, let img = NSImage(contentsOf: url), let cgImg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    ScreenshotStudioWindowController.shared.openStudio(image: cgImg)
                }
            }
        }
    }
}
