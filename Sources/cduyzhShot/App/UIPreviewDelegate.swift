import AppKit
import SwiftUI

/// 独立预览入口：不注册全局热键、不发起截屏、不执行缓存清理。
final class UIPreviewDelegate: NSObject, NSApplicationDelegate {
    private var toolbarWindow: NSWindow?
    private var scrollPanel: ScrollCapturePreviewWindow?
    private var statusPreviewWindow: NSWindow?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let mainMenu = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "退出预览", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)
        ApplicationMenus.addEditMenu(to: mainMenu)
        let previewMenu = NSMenu(title: "预览")
        for (title, action, key) in [
            ("图片美化", #selector(showStudio), "1"),
            ("设置", #selector(showSettings), "2"),
            ("截图工具栏", #selector(showToolbar), "3"),
            ("长截图测试文档", #selector(showScrollFixture), "4"),
            ("长截图控制面板", #selector(showScrollPanel), "5"),
            ("右键状态面板", #selector(showStatusPanel), "6"),
            ("接缝恢复状态", #selector(showScrollRecovery), "7"),
            ("浅色外观", #selector(useLightAppearance), "l"),
            ("深色外观", #selector(useDarkAppearance), "d")
        ] {
            let item = previewMenu.addItem(withTitle: title, action: action, keyEquivalent: key)
            item.target = self
        }
        let previewItem = NSMenuItem(title: "预览", action: nil, keyEquivalent: "")
        previewItem.submenu = previewMenu
        mainMenu.addItem(previewItem)
        NSApp.mainMenu = mainMenu
        if CommandLine.arguments.contains("--preview-capture-controls") {
            showToolbar()
            showScrollPanel()
        } else if CommandLine.arguments.contains("--preview-status-panel") {
            showStatusPanel()
        } else { showStudio() }
    }

    @objc private func showStudio() {
        ScreenshotStudioWindowController.shared.openStudio(image: Self.sampleImage())
    }

    @objc private func showSettings() {
        SettingsWindowController.shared.show()
    }

    @objc private func showToolbar() {
        if let toolbarWindow { toolbarWindow.makeKeyAndOrderFront(nil); return }
        let toolbar = ScreenshotToolbarView()
        let width = max(toolbar.fittingSize.width + 32, 570)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 180), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "截图工具栏 · 交互预览"
        window.isReleasedWhenClosed = false
        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 180))
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(toolbar)
        NSLayoutConstraint.activate([
            toolbar.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            toolbar.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            toolbar.widthAnchor.constraint(equalToConstant: width - 32),
            toolbar.heightAnchor.constraint(equalToConstant: 38)
        ])
        window.contentView = container
        window.center()
        toolbarWindow = window
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func showScrollFixture() { ScrollCaptureFixtureWindow.shared.show() }

    @objc private func showScrollPanel() {
        let panel = scrollPanel ?? ScrollCapturePreviewWindow()
        scrollPanel = panel
        panel.updatePreview(image: Self.sampleImage(), totalHeight: 1680)
        panel.setAutoScrollState(direction: nil, isAccessibilityGranted: true)
        panel.onAutoScrollDirection = { [weak panel] direction in
            panel?.setAutoScrollState(direction: direction, isAccessibilityGranted: true)
        }
        panel.onRecover = { [weak panel] in panel?.showRecovering(direction: .down, isSearching: true) }
        panel.onCancel = { [weak panel] in panel?.orderOut(nil) }
        panel.onDone = { [weak panel] in panel?.showFinishing() }
        panel.center()
        panel.orderFrontRegardless()
    }

    @objc private func showStatusPanel() {
        if let statusPreviewWindow { statusPreviewWindow.makeKeyAndOrderFront(nil); return }
        let controller = NSHostingController(rootView: StatusPanelView(snapshot: .preview))
        let size = controller.view.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "右键状态面板 · 视觉预览"
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        window.center()
        statusPreviewWindow = window
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func showScrollRecovery() {
        showScrollPanel()
        scrollPanel?.showRecovering(direction: .up)
    }

    func applicationWillTerminate(_ notification: Notification) {
        ScrollCaptureManager.shared.cancel()
    }

    @objc private func useLightAppearance() { NSApp.appearance = NSAppearance(named: .aqua) }
    @objc private func useDarkAppearance() { NSApp.appearance = NSAppearance(named: .darkAqua) }

    static func sampleImage() -> CGImage {
        let width = 960
        let height = 600
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor(white: 0.98, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        NSColor(white: 0.94, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 192, height: height).fill()
        func text(_ string: String, x: CGFloat, y: CGFloat, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .darkGray) {
            (string as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color])
        }
        text("灵感收藏", x: 28, y: 536, size: 22, weight: .semibold)
        text("所有灵感", x: 28, y: 467, size: 16, weight: .medium, color: .systemBlue)
        text("最近添加", x: 28, y: 421, size: 16)
        text("我的收藏", x: 28, y: 375, size: 16)
        text("把灵感，留在眼前。", x: 234, y: 507, size: 34, weight: .semibold, color: .black)
        text("清晰记录每一个好想法。", x: 236, y: 468, size: 17, color: .gray)
        let cards: [(String, String, NSColor)] = [
            ("设计日常", "简单，也可以很动人。", NSColor(red: 0.84, green: 0.89, blue: 0.98, alpha: 1)),
            ("片刻灵感", "给想法一点留白。", NSColor(red: 0.91, green: 0.86, blue: 0.97, alpha: 1)),
            ("值得收藏", "看见细节，留下美好。", NSColor(red: 0.96, green: 0.9, blue: 0.79, alpha: 1))
        ]
        for (index, card) in cards.enumerated() {
            let x = CGFloat(234 + index * 228)
            card.2.setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: 192, width: 208, height: 226), xRadius: 18, yRadius: 18).fill()
            text(card.0, x: x + 18, y: 238, size: 20, weight: .semibold)
            text(card.1, x: x + 18, y: 211, size: 12)
            NSColor.white.withAlphaComponent(0.7).setFill()
            NSBezierPath(ovalIn: NSRect(x: x + 55, y: 305, width: 98, height: 98)).fill()
        }
        text("3 个收藏 · 每一天都有新发现", x: 236, y: 136, size: 13, color: .gray)
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.cgImage!
    }
}
