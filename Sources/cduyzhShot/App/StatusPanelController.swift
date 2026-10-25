import AppKit
import SwiftUI

/// NSPopover 负责系统定位与点外关闭；SwiftUI 负责随真实状态刷新的内容。
final class StatusPanelController: NSObject, NSPopoverDelegate {
    private static weak var current: StatusPanelController?
    private static var captureLaunchPending = false
    private let popover = NSPopover()
    private let model = StatusPanelModel()
    private var refreshTimer: Timer?
    private var keyMonitor: Any?
    private var activationObserver: NSObjectProtocol?
    private var previousActiveApp: NSRunningApplication?
    private var moreMenu: NSMenu?
    private var restoreTargetOnDismiss = true
    private var dismissalGeneration = 0

    override init() {
        super.init()
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        let content = NSHostingController(rootView: StatusPanelContent(model: model) { [weak self] in self?.perform($0) })
        popover.contentViewController = content
        popover.contentSize = content.view.fittingSize
    }

    deinit {
        stopObserving()
    }

    func toggle(relativeTo button: NSStatusBarButton) {
        if popover.isShown { close(); return }
        show(relativeTo: button)
    }

    func show(relativeTo button: NSStatusBarButton) {
        if popover.isShown { refreshIfVisible(); return }
        if let active = NSWorkspace.shared.frontmostApplication,
           active.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousActiveApp = active }
        dismissalGeneration += 1
        restoreTargetOnDismiss = true
        refresh(includePermissions: true)
        model.focusedAction = .screenshot
        Self.current = self
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // 菜单栏应用也可接收 Tab / 方向键；启动捕获前会恢复原来的目标应用。
        NSApp.activate(ignoringOtherApps: true)
        popover.contentViewController?.view.window?.makeKey()
        installObservers()
    }

    func close(restoringTarget: Bool = true) {
        restoreTargetOnDismiss = restoringTarget
        moreMenu?.cancelTracking()
        let wasShown = popover.isShown
        popover.performClose(nil)
        stopObserving()
        if Self.current === self { Self.current = nil }
        if !wasShown && restoringTarget { restoreDismissedTarget() }
    }

    func captureFromStatusItem() {
        // 系统可能先关闭 transient popover，再派发同一按钮的左键动作。
        let wasActivatedByPanel = previousActiveApp != nil
            && NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier
        if popover.isShown || wasActivatedByPanel { perform(.screenshot) }
        else { AppState.shared.triggerScreenshot() }
    }

    func refreshIfVisible() {
        if popover.isShown { refresh(includePermissions: true) }
    }

    func popoverDidClose(_ notification: Notification) {
        stopObserving()
        model.focusedAction = nil
        if Self.current === self { Self.current = nil }
        if restoreTargetOnDismiss { restoreDismissedTarget() }
    }

    private func restoreDismissedTarget() {
        let generation = dismissalGeneration
        // 点击别的应用时尊重系统已经切换的焦点；Esc 或仅关闭面板才恢复原目标。
        DispatchQueue.main.async { [weak self] in
            guard let self, generation == self.dismissalGeneration, !self.popover.isShown,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier else { return }
            self.previousActiveApp?.activate()
        }
    }

    /// 捕获入口及 Carbon 全局热键共用，防止将仍在显示的状态面板截入图片。
    /// 关闭后 current 已清空，因此延迟调用原入口不会递归。
    static func deferCaptureIfPresented(_ action: @escaping () -> Void) -> Bool {
        if captureLaunchPending { return true }
        guard let current, current.popover.isShown else { return false }
        current.afterClosing(restoreTarget: true, action)
        return true
    }

    private func afterClosing(restoreTarget: Bool = false, _ action: @escaping () -> Void) {
        let target = previousActiveApp
        dismissalGeneration += 1
        close(restoringTarget: false)
        if restoreTarget {
            Self.captureLaunchPending = true
            target?.activate()
            // 等窗口服务器移除 popover，再读屏；同时让滚动会话恢复原目标的焦点。
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                Self.captureLaunchPending = false
                action()
            }
        } else {
            previousActiveApp = nil
            DispatchQueue.main.async(execute: action)
        }
    }

    private func refresh(includePermissions: Bool) {
        var state = model.snapshot
        if includePermissions {
            state.screenGranted = Permissions.hasScreenRecordingPermission
            state.accessibilityGranted = Permissions.hasAccessibilityPermission
        }
        state.recording = ScreenRecorder.shared.isRecording
        state.scrollCapturing = ScrollCaptureManager.shared.isRunning
        state.scrollHeight = ScrollCaptureManager.shared.capturedPixelHeight
        state.pinCount = PinManager.shared.pinCount
        state.visiblePinCount = PinManager.shared.visiblePinCount
        state.pinsHidden = PinManager.shared.arePinsHidden
        state.screenshotShortcut = UserPreferences.shared.hotkeyScreenshot.displayString
        state.scrollShortcut = UserPreferences.shared.hotkeyScroll.displayString
        state.recordingShortcut = UserPreferences.shared.hotkeyRecording.displayString
        state.pinShortcut = UserPreferences.shared.hotkeyPin.displayString
        state.hasUnreadRelease = ReleaseNotesWindowController.shared.hasUnreadRelease
        if state != model.snapshot { model.snapshot = state }
        if let focused = model.focusedAction, !focusOrder.contains(focused) { model.focusedAction = nil }
    }

    private func installObservers() {
        stopObserving()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.refresh(includePermissions: false) }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
        activationObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: NSApp, queue: .main) { [weak self] _ in
            self?.refresh(includePermissions: true)
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.popover.isShown, self.moreMenu == nil,
                  event.window === self.popover.contentViewController?.view.window else { return event }
            return self.handleKey(event) ? nil : event
        }
    }

    private func stopObserving() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
        activationObserver = nil
    }

    private var focusOrder: [StatusPanelAction] {
        var order: [StatusPanelAction] = [.settings, .screenshot, .scroll, .record, .pin, .studio, .screenPermission, .accessibilityPermission]
        if model.snapshot.pinCount > 0 { order += [.togglePins, .closePins] }
        return order + [.more, .quit]
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if modifiers == .command, event.charactersIgnoringModifiers == "," { perform(.settings); return true }
        if modifiers == .option, event.charactersIgnoringModifiers?.lowercased() == "e" { perform(.studio); return true }
        guard modifiers.isEmpty || (event.keyCode == 48 && modifiers == .shift) else { return false }
        switch event.keyCode {
        case 53: close(); return true
        case 48, 123, 124, 125, 126:
            let order = focusOrder
            let backward = event.keyCode == 123 || event.keyCode == 126 || modifiers == .shift
            if let selected = model.focusedAction, let index = order.firstIndex(of: selected) {
                model.focusedAction = order[(index + (backward ? -1 : 1) + order.count) % order.count]
            } else {
                model.focusedAction = backward ? order.last : .screenshot
            }
            return true
        case 36, 76, 49:
            if let action = model.focusedAction { perform(action) }
            return true
        default: return false
        }
    }

    private func perform(_ action: StatusPanelAction) {
        switch action {
        case .screenshot: afterClosing(restoreTarget: true) { AppState.shared.triggerScreenshot() }
        case .scroll:
            afterClosing(restoreTarget: true) {
                if ScrollCaptureManager.shared.isRunning { ScrollCaptureManager.shared.finish() }
                else { AppState.shared.triggerScrollScreenshot() }
            }
        case .record: afterClosing(restoreTarget: true) { AppState.shared.triggerScreenRecording() }
        case .pin: afterClosing(restoreTarget: true) { AppState.shared.triggerPinFromClipboard() }
        case .studio: afterClosing { AppState.shared.triggerStudioFromClipboardOrOpen() }
        case .settings: afterClosing { SettingsWindowController.shared.show() }
        case .screenPermission: afterClosing { Permissions.openSystemSettings(for: "screen") }
        case .accessibilityPermission: afterClosing { Permissions.openSystemSettings(for: "accessibility") }
        case .togglePins: PinManager.shared.toggleVisibility(); refresh(includePermissions: false)
        case .closePins: PinManager.shared.closeAll(); refresh(includePermissions: false)
        case .more: showMoreMenu()
        case .quit: afterClosing { NSApp.terminate(nil) }
        case .clearCache:
            guard !ScreenRecorder.shared.isRecording, !ScrollCaptureManager.shared.isRunning else { return }
            CacheManager.shared.clearAllCache()
        case .checkUpdates: afterClosing { UpdateManager.shared.checkForUpdates(isUserInitiated: true) }
        case .releaseNotes: afterClosing { ReleaseNotesWindowController.shared.show() }
        case .scrollExample: afterClosing { ScrollCaptureFixtureWindow.shared.show() }
        case .relaunch: afterClosing { Permissions.relaunchApp() }
        case .about: afterClosing { SettingsWindowController.shared.showAbout() }
        case .dismiss: close()
        }
    }

    private func showMoreMenu() {
        guard let view = popover.contentViewController?.view else { return }
        let menu = NSMenu(title: "更多操作")
        func item(_ title: String, _ action: StatusPanelAction, _ symbol: String, enabled: Bool = true) {
            let item = NSMenuItem(title: title, action: #selector(moreItemClicked(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = action
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            item.isEnabled = enabled
            menu.addItem(item)
        }
        item("清理缓存（\(CacheManager.shared.formattedCacheSize())）", .clearCache, "trash", enabled: !ScreenRecorder.shared.isRecording && !ScrollCaptureManager.shared.isRunning)
        menu.addItem(.separator())
        item("检查更新…", .checkUpdates, "arrow.triangle.2.circlepath")
        item(ReleaseNotesWindowController.shared.hasUnreadRelease ? "更新记录… · 新" : "更新记录…", .releaseNotes, "clock.arrow.circlepath")
        item("长截图使用示例…", .scrollExample, "questionmark.circle")
        item("关于 cduyzhShot…", .about, "info.circle")
        menu.addItem(.separator())
        item("重新启动 cduyzhShot", .relaunch, "arrow.clockwise")
        moreMenu = menu
        menu.autoenablesItems = false
        menu.popUp(positioning: nil, at: NSPoint(x: 18, y: 42), in: view)
        moreMenu = nil
    }

    @objc private func moreItemClicked(_ item: NSMenuItem) {
        guard let action = item.representedObject as? StatusPanelAction else { return }
        perform(action)
    }
}
