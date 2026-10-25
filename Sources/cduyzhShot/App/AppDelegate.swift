import AppKit

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private lazy var statusPanel = StatusPanelController()
    private var periodicCleanupTimer: Timer?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize Notification Center
        _ = NotificationHelper.shared

        let mainMenu = NSMenu()
        let applicationMenu = NSMenu()
        let statusPanelItem = applicationMenu.addItem(withTitle: "状态与操作…", action: #selector(showStatusPanelClicked), keyEquivalent: "0")
        statusPanelItem.target = self
        applicationMenu.addItem(.separator())
        let aboutItem = applicationMenu.addItem(withTitle: "关于 cduyzhShot…", action: #selector(aboutClicked), keyEquivalent: "")
        aboutItem.target = self
        let checkUpdateItem = applicationMenu.addItem(withTitle: "检查更新…", action: #selector(checkUpdatesClicked), keyEquivalent: "")
        checkUpdateItem.target = self
        let historyItem = applicationMenu.addItem(withTitle: "更新记录…", action: #selector(releaseNotesClicked), keyEquivalent: "")
        historyItem.target = self
        let preferencesItem = applicationMenu.addItem(withTitle: "设置…", action: #selector(settingsClicked), keyEquivalent: ",")
        preferencesItem.target = self
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(withTitle: "退出 cduyzhShot", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let applicationItem = NSMenuItem()
        applicationItem.submenu = applicationMenu
        mainMenu.addItem(applicationItem)
        ApplicationMenus.addEditMenu(to: mainMenu)
        let helpMenu = NSMenu(title: "帮助")
        let example = helpMenu.addItem(withTitle: "滚动长截图使用示例…", action: #selector(scrollExampleClicked), keyEquivalent: "4")
        example.target = self
        let helpItem = NSMenuItem(title: "帮助", action: nil, keyEquivalent: "")
        helpItem.submenu = helpMenu
        mainMenu.addItem(helpItem)
        NSApp.mainMenu = mainMenu

        // Setup AppState and Register Global Hotkeys
        AppState.shared.setup()

        // Setup Menu Bar Status Item
        setupStatusItem()

        // Initial scheduled cache cleanup
        CacheManager.shared.performScheduledCleanup()

        // Background periodic cache cleanup every 6 hours
        periodicCleanupTimer = Timer.scheduledTimer(withTimeInterval: 3600 * 6, repeats: true) { _ in
            CacheManager.shared.performScheduledCleanup()
        }

        // Check permissions on launch silently
        if !Permissions.hasScreenRecordingPermission {
            Permissions.requestScreenRecordingPermission(promptUser: false)
        }
        ReleaseNotesWindowController.shared.showIfNeeded()

        // Background update check if enabled
        if UserPreferences.shared.autoCheckForUpdates {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                UpdateManager.shared.checkForUpdates(isUserInitiated: false)
            }
        }
    }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { SettingsWindowController.shared.show() }
        return true
    }

    public func applicationWillTerminate(_ notification: Notification) {
        ScrollCaptureManager.shared.cancel()
        periodicCleanupTimer?.invalidate()
        statusPanel.close()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            if let image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "cduyzhShot") {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "📸"
            }
            button.toolTip = "cduyzhShot \(AppVersion.current.displayString) · 左键截图，右键查看状态与更多操作"
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel("cduyzhShot；左键截图，右键查看状态与更多操作")
            button.setAccessibilityCustomActions([
                NSAccessibilityCustomAction(name: "查看状态与更多操作", target: self, selector: #selector(showStatusPanelAccessibility))
            ])
        }

        buildMenu()
    }

    /// 保留设置刷新入口，快捷键与权限由面板在每次显示时重新读取。
    public func buildMenu() {
        statusItem?.menu = nil
        statusPanel.refreshIfVisible()
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            statusPanel.toggle(relativeTo: sender)
        } else {
            statusPanel.captureFromStatusItem()
        }
    }

    @objc private func showStatusPanelAccessibility() -> Bool {
        guard let button = statusItem?.button else { return false }
        statusPanel.show(relativeTo: button)
        return true
    }

    @objc private func showStatusPanelClicked() {
        if let button = statusItem?.button { statusPanel.show(relativeTo: button) }
    }

    @objc private func settingsClicked() {
        SettingsWindowController.shared.show()
    }

    @objc private func checkUpdatesClicked() {
        UpdateManager.shared.checkForUpdates(isUserInitiated: true)
    }

    @objc private func aboutClicked() {
        SettingsWindowController.shared.showAbout()
    }

    @objc private func releaseNotesClicked() {
        ReleaseNotesWindowController.shared.show()
    }

    @objc private func scrollExampleClicked() {
        ScrollCaptureFixtureWindow.shared.show()
    }

}
