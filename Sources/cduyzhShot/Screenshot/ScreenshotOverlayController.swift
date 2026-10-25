import AppKit
import CoreGraphics

public final class ScreenshotOverlayController: NSObject, ScreenshotOverlayDelegate {
    public static let shared = ScreenshotOverlayController()

    private var panels: [NSPanel] = []
    private var overlayViews: [ScreenshotOverlayView] = []
    private var isCapturing = false

    private var localEscMonitor: Any?
    private var globalEscMonitor: Any?
    private var previousActiveApp: NSRunningApplication?

    public var onFinished: ((CGImage?) -> Void)?

    private override init() {
        super.init()
    }

    public func startCapture(scrollModeDirect: Bool = false) {
        guard !isCapturing else { return }
        // Clean up any lingering scroll capture state or rogue windows
        if ScrollCaptureManager.shared.isRunning {
            ScrollCaptureManager.shared.cancel()
        }
        ScrollCaptureManager.cleanupAllScrollWindows()

        isCapturing = true

        // 1. Capture and remember the target application before cduyzhShot takes focus
        previousActiveApp = NSWorkspace.shared.frontmostApplication

        // 2. Capture screens while unoccluded
        var screenImages: [(NSScreen, CGImage)] = []
        for screen in NSScreen.screens {
            if let img = ScreenCaptureEngine.shared.capture(screen: screen) {
                screenImages.append((screen, img))
            }
        }

        panels.removeAll()
        overlayViews.removeAll()

        let currentMouseScreen = DisplayHelper.screenContaining(point: NSEvent.mouseLocation) ?? NSScreen.main

        for (screen, image) in screenImages {
            let panel = NSPanel(
                contentRect: screen.frame,
                styleMask: [.nonactivatingPanel, .borderless],
                backing: .buffered,
                defer: false
            )

            panel.isFloatingPanel = true
            panel.level = .screenSaver
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

            let overlayView = ScreenshotOverlayView(frame: NSRect(origin: .zero, size: screen.frame.size))
            overlayView.screenImage = image
            overlayView.isScrollMode = scrollModeDirect
            overlayView.delegate = self
            panel.contentView = overlayView

            panels.append(panel)
            overlayViews.append(overlayView)

            panel.orderFrontRegardless()
            if screen == currentMouseScreen {
                panel.makeKey()
            }
        }

        NSApp.activate(ignoringOtherApps: true)

        // 3. Register cascading Esc monitors across all apps and screens (undo -> cancel)
        removeEscMonitors()
        localEscMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Esc
                guard let self = self else { return nil }
                let mouseLocation = NSEvent.mouseLocation
                let targetView = self.overlayViews.first(where: { $0.window?.frame.contains(mouseLocation) == true }) ?? self.overlayViews.first
                if let view = targetView, view.handleEscape() {
                    return nil // Consumed by undoing annotation or draft
                }
                self.overlayDidCancel()
                return nil
            }
            return event
        }
        globalEscMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Esc
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    let mouseLocation = NSEvent.mouseLocation
                    let targetView = self.overlayViews.first(where: { $0.window?.frame.contains(mouseLocation) == true }) ?? self.overlayViews.first
                    if let view = targetView, view.handleEscape() {
                        return // Consumed by undoing annotation or draft
                    }
                    self.overlayDidCancel()
                }
            }
        }
    }

    private func removeEscMonitors() {
        if let monitor = localEscMonitor {
            NSEvent.removeMonitor(monitor)
            localEscMonitor = nil
        }
        if let monitor = globalEscMonitor {
            NSEvent.removeMonitor(monitor)
            globalEscMonitor = nil
        }
    }

    public func dismiss() {
        removeEscMonitors()
        for panel in panels {
            panel.orderOut(nil)
        }
        panels.removeAll()
        overlayViews.removeAll()
        isCapturing = false
    }

    // MARK: - ScreenshotOverlayDelegate
    public func overlayDidCancel() {
        dismiss()
        onFinished?(nil)
    }

    public func overlayDidFinish(image: CGImage, rect: CGRect) {
        dismiss()
        onFinished?(image)
    }

    public func overlayDidRequestPin(image: CGImage, rect: CGRect) {
        dismiss()
        PinManager.shared.pin(image: image, origin: rect.origin)
    }

    public func overlayDidRequestStudio(image: CGImage, rect: CGRect) {
        dismiss()
        ScreenshotStudioWindowController.shared.openStudio(image: image)
    }

    public func overlayDidRequestScrollCapture(rect: CGRect) {
        let targetApp = previousActiveApp
        dismiss()
        targetApp?.activate()
        ScrollCaptureManager.shared.start(in: rect, targetApp: targetApp, onError: { message in
            let alert = NSAlert()
            alert.messageText = "长截图无法继续"
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.runModal()
        }) { image in
            guard let image else { return }
            ScrollCaptureOutput.deliver(image)
        }
    }

    public func overlayDidRequestRecord(rect: CGRect) {
        dismiss()

        let targetApp = previousActiveApp
        targetApp?.activate()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            ScreenRecorder.shared.startRecording(
                in: rect,
                capturesSystemAudio: true,
                skipCountdown: false
            ) { _ in }
        }
    }
}
