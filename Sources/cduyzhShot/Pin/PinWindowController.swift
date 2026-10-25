import AppKit
import CoreGraphics

public final class PinWindow: NSPanel {
    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { true }

    public var onScrollDelta: ((CGFloat, Bool) -> Void)?
    public var onEscape: (() -> Void)?
    public var onFlip: (() -> Void)?
    public var onReset: (() -> Void)?

    public override func scrollWheel(with event: NSEvent) {
        let isCommandPressed = event.modifierFlags.contains(.command)
        let delta = event.scrollingDeltaY
        if abs(delta) > 0.1 {
            onScrollDelta?(delta, isCommandPressed)
        }
    }

    public override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // Esc
            onEscape?()
        case 3 where event.modifierFlags.contains(.command): // Cmd+F or 'F'
            onFlip?()
        case 3: // 'F'
            onFlip?()
        case 15: // 'R'
            onReset?()
        default:
            super.keyDown(with: event)
        }
    }
}

public final class PinWindowController: NSWindowController, NSMenuDelegate {
    public let image: CGImage
    private let imageView = NSImageView()
    private var currentScale: CGFloat = 1.0
    private var isFlippedHorizontal = false
    private var initialSize: CGSize = .zero

    public var onClose: (() -> Void)?

    public init(image: CGImage, initialOrigin: CGPoint? = nil) {
        self.image = image
        super.init(window: nil)

        let screenScale = NSScreen.main?.backingScaleFactor ?? 2.0
        let displayWidth = CGFloat(image.width) / screenScale
        let displayHeight = CGFloat(image.height) / screenScale
        self.initialSize = CGSize(width: displayWidth, height: displayHeight)

        let origin = initialOrigin ?? CGPoint(x: 200, y: 300)
        let frame = NSRect(origin: origin, size: initialSize)

        let panel = PinWindow(
            contentRect: frame,
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.hasShadow = true

        panel.onScrollDelta = { [weak self] delta, isZoom in
            self?.handleScroll(delta: delta, isZoom: isZoom)
        }
        panel.onEscape = { [weak self] in
            self?.closeWindow()
        }
        panel.onFlip = { [weak self] in
            self?.flipHorizontal()
        }
        panel.onReset = { [weak self] in
            self?.resetSize()
        }

        self.window = panel
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        guard let window = self.window else { return }

        let container = NSView(frame: window.contentView?.bounds ?? .zero)
        container.wantsLayer = true
        container.layer?.cornerRadius = 8
        container.layer?.masksToBounds = true
        container.layer?.borderColor = NSColor(white: 0.8, alpha: 0.3).cgColor
        container.layer?.borderWidth = 1.0

        let nsImage = NSImage(cgImage: image, size: initialSize)
        imageView.image = nsImage
        imageView.imageScaling = .scaleAxesIndependently
        imageView.frame = container.bounds
        imageView.autoresizingMask = [.width, .height]
        container.addSubview(imageView)

        window.contentView = container

        // Context Menu
        let menu = NSMenu(title: "贴图选项")
        menu.addItem(NSMenuItem(title: "复制图片 (⌘C)", action: #selector(copyImage), keyEquivalent: "c"))
        menu.addItem(NSMenuItem(title: "另存为... (⌘S)", action: #selector(saveImage), keyEquivalent: "s"))
        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(title: "水平翻转 (F)", action: #selector(flipHorizontal), keyEquivalent: "f"))
        menu.addItem(NSMenuItem(title: "还原 100% 尺寸 (R)", action: #selector(resetSize), keyEquivalent: "r"))
        menu.addItem(NSMenuItem.separator())

        let opacityMenu = NSMenu(title: "透明度 (滚轮可微调)")
        for opacity in [1.0, 0.8, 0.5, 0.3] {
            let item = NSMenuItem(title: "\(Int(opacity * 100))%", action: #selector(setOpacity(_:)), keyEquivalent: "")
            item.representedObject = opacity
            opacityMenu.addItem(item)
        }
        let opacityItem = NSMenuItem(title: "透明度", action: nil, keyEquivalent: "")
        opacityItem.submenu = opacityMenu
        menu.addItem(opacityItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "关闭贴图 (Esc / 双击)", action: #selector(closeWindow), keyEquivalent: "w"))

        container.menu = menu

        // Double click recognizer to close
        let doubleClick = NSClickGestureRecognizer(target: self, action: #selector(handleDoubleClick))
        doubleClick.numberOfClicksRequired = 2
        container.addGestureRecognizer(doubleClick)
    }

    private func handleScroll(delta: CGFloat, isZoom: Bool) {
        guard let win = window else { return }
        if isZoom {
            // Zoom in / out (0.2x ~ 4.0x)
            let factor: CGFloat = delta > 0 ? 1.08 : 0.92
            let newScale = max(0.2, min(4.0, currentScale * factor))
            currentScale = newScale

            let newW = initialSize.width * currentScale
            let newH = initialSize.height * currentScale
            let currentCenter = CGPoint(x: win.frame.midX, y: win.frame.midY)
            let newFrame = NSRect(x: currentCenter.x - newW / 2, y: currentCenter.y - newH / 2, width: newW, height: newH)
            win.setFrame(newFrame, display: true, animate: false)
        } else {
            // Smooth Opacity adjustment (20% ~ 100%)
            let step: CGFloat = delta > 0 ? 0.05 : -0.05
            let currentAlpha = win.alphaValue
            let newAlpha = max(0.2, min(1.0, currentAlpha + step))
            win.alphaValue = newAlpha
        }
    }

    @objc public func flipHorizontal() {
        isFlippedHorizontal.toggle()
        guard let win = window, let container = win.contentView else { return }
        container.wantsLayer = true
        let flipTransform = isFlippedHorizontal ? CATransform3DMakeScale(-1.0, 1.0, 1.0) : CATransform3DIdentity
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            container.layer?.transform = flipTransform
        }
    }

    @objc public func resetSize() {
        guard let win = window else { return }
        currentScale = 1.0
        let currentCenter = CGPoint(x: win.frame.midX, y: win.frame.midY)
        let newFrame = NSRect(x: currentCenter.x - initialSize.width / 2, y: currentCenter.y - initialSize.height / 2, width: initialSize.width, height: initialSize.height)
        win.setFrame(newFrame, display: true, animate: true)
    }

    @objc private func copyImage() {
        PasteboardHelper.copyImage(image)
        SoundManager.shared.playCameraShutterSound()
    }

    @objc private func saveImage() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "贴图_\(Int(Date().timeIntervalSince1970)).png"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self = self else { return }
            let rep = NSBitmapImageRep(cgImage: self.image)
            if let data = rep.representation(using: .png, properties: [:]) {
                try? data.write(to: url)
            }
        }
    }

    @objc private func setOpacity(_ sender: NSMenuItem) {
        if let opacity = sender.representedObject as? Double {
            window?.alphaValue = CGFloat(opacity)
        }
    }

    @objc private func handleDoubleClick() {
        closeWindow()
    }

    @objc private func closeWindow() {
        window?.orderOut(nil)
        onClose?()
    }
}

public final class PinManager {
    public static let shared = PinManager()

    private var activePins: [PinWindowController] = []

    /// 状态面板只读取实际窗口状态，不复制贴图管理逻辑。
    public var pinCount: Int { activePins.count }
    public var visiblePinCount: Int { activePins.filter { $0.window?.isVisible == true }.count }
    public var arePinsHidden: Bool { !activePins.isEmpty && visiblePinCount == 0 }

    private init() {}

    public func pin(image: CGImage, origin: CGPoint? = nil) {
        let pinController = PinWindowController(image: image, initialOrigin: origin)
        pinController.onClose = { [weak self, weak pinController] in
            guard let self = self, let pin = pinController else { return }
            self.activePins.removeAll { $0 === pin }
        }
        activePins.append(pinController)
        pinController.showWindow(nil)
    }

    public func toggleVisibility() {
        let shouldHide = !arePinsHidden
        for pin in activePins {
            if shouldHide {
                pin.window?.orderOut(nil)
            } else {
                pin.window?.makeKeyAndOrderFront(nil)
            }
        }
    }

    public func closeAll() {
        for pin in activePins {
            pin.window?.orderOut(nil)
        }
        activePins.removeAll()
    }
}
