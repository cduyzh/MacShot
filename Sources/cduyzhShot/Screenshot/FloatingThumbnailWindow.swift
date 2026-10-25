import AppKit
import CoreGraphics

private final class ThumbnailContentView: NSVisualEffectView {
    var onHoverChanged: ((Bool) -> Void)?
    private var hoverTrackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area = hoverTrackingArea { removeTrackingArea(area) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { onHoverChanged?(true) }
    override func mouseExited(with event: NSEvent) { onHoverChanged?(false) }
}

private final class ThumbnailActionButton: NSButton {
    private var hoverTrackingArea: NSTrackingArea?
    private var isHovered = false
    private var isPressed = false

    override var isEnabled: Bool {
        didSet {
            updateAppearance()
            window?.invalidateCursorRects(for: self)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area = hoverTrackingArea { removeTrackingArea(area) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if isEnabled { addCursorRect(bounds, cursor: .pointingHand) }
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isHovered = true
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovered = false
        updateAppearance()
    }

    override func highlight(_ flag: Bool) {
        super.highlight(flag)
        isPressed = flag
        updateAppearance()
    }

    func updateAppearance() {
        alphaValue = isEnabled ? 1 : 0.35
        let opacity: CGFloat = isEnabled && isPressed ? 0.22 : (isEnabled && isHovered ? 0.15 : 0.07)
        layer?.backgroundColor = NSColor.white.withAlphaComponent(opacity).cgColor
    }
}

public final class FloatingThumbnailWindow: NSPanel {
    public static let shared = FloatingThumbnailWindow()

    private let imageView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "已复制到剪贴板，直接 ⌘V 粘贴")
    private let pathLabel = NSTextField(labelWithString: "")
    private let actionButtonStudio = ThumbnailActionButton()
    private let actionButton1 = ThumbnailActionButton()
    private let actionButton2 = ThumbnailActionButton()
    private let closeButton = ThumbnailActionButton()
    private var dismissTimer: Timer?
    private var dismissDeadline: Date?
    private var remainingDismissInterval: TimeInterval = 6
    private var isPointerInside = false
    private var isAutoDismissing = false
    private var isDismissing = false
    private var presentationRevision = 0
    private var currentImage: CGImage?
    private var currentFileURL: URL?

    private init() {
        let frame = NSRect(x: 0, y: 0, width: 356, height: 98)
        super.init(
            contentRect: frame,
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar + 20
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .transient]
        appearance = NSAppearance(named: .darkAqua)
        setupUI()
    }

    private func setupUI() {
        let container = ThumbnailContentView(frame: NSRect(origin: .zero, size: frame.size))
        container.material = .hudWindow
        container.blendingMode = .behindWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 16
        container.layer?.masksToBounds = true
        container.layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        container.layer?.borderWidth = 0.5
        container.onHoverChanged = { [weak self] isHovered in
            self?.setPointerInside(isHovered)
        }
        contentView = container

        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 9
        imageView.layer?.masksToBounds = true
        imageView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.16).cgColor
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(imageView)

        titleLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(titleLabel)

        pathLabel.font = NSFont.systemFont(ofSize: 10)
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(pathLabel)

        let buttonStack = NSStackView()
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 6
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(buttonStack)

        setupSmallButton(actionButtonStudio, title: "美化", symbol: "wand.and.stars", tip: "进入图片美化工作室")
        actionButtonStudio.target = self
        actionButtonStudio.action = #selector(actionStudioClicked)
        buttonStack.addArrangedSubview(actionButtonStudio)

        setupSmallButton(actionButton1, title: "贴图", symbol: "pin", tip: "将图片固定在屏幕上")
        actionButton1.target = self
        actionButton1.action = #selector(action1Clicked)
        buttonStack.addArrangedSubview(actionButton1)

        setupSmallButton(actionButton2, title: "访达", symbol: "folder", tip: "在访达中显示文件")
        actionButton2.target = self
        actionButton2.action = #selector(action2Clicked)
        buttonStack.addArrangedSubview(actionButton2)

        setupSmallButton(closeButton, title: "", symbol: "xmark", tip: "关闭预览")
        closeButton.target = self
        closeButton.action = #selector(dismissWindow)
        container.addSubview(closeButton)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            imageView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 76),
            imageView.heightAnchor.constraint(equalToConstant: 74),
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 13),
            titleLabel.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -6),
            pathLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            pathLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            pathLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            buttonStack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
            buttonStack.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            buttonStack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -12),
            closeButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            closeButton.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            closeButton.widthAnchor.constraint(equalToConstant: 22)
        ])

        let click = NSClickGestureRecognizer(target: self, action: #selector(action2Clicked))
        click.numberOfClicksRequired = 2
        container.addGestureRecognizer(click)
    }

    private func setupSmallButton(_ button: ThumbnailActionButton, title: String, symbol: String, tip: String) {
        button.title = title
        button.font = NSFont.systemFont(ofSize: 10.5, weight: .medium)
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 6
        button.contentTintColor = .labelColor
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 10, weight: .medium))
        button.imagePosition = title.isEmpty ? .imageOnly : .imageLeading
        button.toolTip = tip
        button.setAccessibilityLabel(tip)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 24).isActive = true
        if !title.isEmpty { button.widthAnchor.constraint(greaterThanOrEqualToConstant: 60).isActive = true }
        button.updateAppearance()
    }

    public func show(image: CGImage, fileURL: URL? = nil, message: String = "已复制到剪贴板，直接 ⌘V 粘贴") {
        guard UserPreferences.shared.showFloatingThumbnail else { return }
        presentationRevision += 1
        isAutoDismissing = false
        isDismissing = false
        invalidateDismissTimer()
        currentImage = image
        currentFileURL = fileURL
        imageView.image = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        titleLabel.stringValue = message
        titleLabel.toolTip = message

        let isVideo = fileURL?.pathExtension.lowercased() == "mp4"
        imageView.setAccessibilityLabel(isVideo ? "录屏预览" : "截图预览")
        if let url = fileURL {
            pathLabel.stringValue = url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
            pathLabel.toolTip = url.path
            pathLabel.setAccessibilityLabel("文件位置：\(url.path)")
        } else {
            pathLabel.stringValue = "\(image.width) × \(image.height) 像素"
            pathLabel.toolTip = nil
            pathLabel.setAccessibilityLabel(pathLabel.stringValue)
        }

        actionButtonStudio.isHidden = isVideo
        actionButton1.title = isVideo ? "播放" : "贴图"
        actionButton1.image = NSImage(systemSymbolName: isVideo ? "play.fill" : "pin", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 10, weight: .medium))
        let actionTip = isVideo ? "使用系统默认播放器打开" : "将图片固定在屏幕上"
        actionButton1.toolTip = actionTip
        actionButton1.setAccessibilityLabel(actionTip)
        actionButton2.isEnabled = fileURL != nil

        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let visibleFrame = screen.visibleFrame
            setFrameOrigin(NSPoint(x: visibleFrame.maxX - frame.width - 24, y: visibleFrame.minY + 24))
        }

        let wasVisible = isVisible
        if !wasVisible { alphaValue = 0 }
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.18
            self.animator().alphaValue = 1
        }

        remainingDismissInterval = 6
        isPointerInside = frame.contains(NSEvent.mouseLocation)
        if !isPointerInside { scheduleDismissTimer() }
    }

    private func setPointerInside(_ isInside: Bool) {
        guard isPointerInside != isInside else { return }
        isPointerInside = isInside
        if isInside {
            if let deadline = dismissDeadline { remainingDismissInterval = max(0, deadline.timeIntervalSinceNow) }
            invalidateDismissTimer()
            if isAutoDismissing {
                presentationRevision += 1
                isAutoDismissing = false
                isDismissing = false
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.10
                    self.animator().alphaValue = 1
                }
            }
        } else if isVisible && alphaValue > 0 && !isDismissing {
            remainingDismissInterval = max(2, remainingDismissInterval)
            scheduleDismissTimer()
        }
    }

    private func scheduleDismissTimer() {
        invalidateDismissTimer()
        dismissDeadline = Date().addingTimeInterval(remainingDismissInterval)
        dismissTimer = Timer.scheduledTimer(withTimeInterval: remainingDismissInterval, repeats: false) { [weak self] _ in
            guard let self else { return }
            if self.frame.contains(NSEvent.mouseLocation) {
                self.setPointerInside(true)
            } else {
                self.performDismiss(automatically: true)
            }
        }
    }

    private func invalidateDismissTimer() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        dismissDeadline = nil
    }

    @objc private func actionStudioClicked() {
        if let image = currentImage { ScreenshotStudioWindowController.shared.openStudio(image: image) }
        dismissWindow()
    }

    @objc private func action1Clicked() {
        if currentFileURL?.pathExtension.lowercased() == "mp4" {
            if let url = currentFileURL { NSWorkspace.shared.open(url) }
        } else if let image = currentImage {
            PinManager.shared.pin(image: image)
        }
        dismissWindow()
    }

    @objc private func action2Clicked() {
        guard let url = currentFileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
        dismissWindow()
    }

    @objc public func dismissWindow() {
        performDismiss(automatically: false)
    }

    private func performDismiss(automatically: Bool) {
        invalidateDismissTimer()
        presentationRevision += 1
        let revision = presentationRevision
        isAutoDismissing = automatically
        isDismissing = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.18
            self.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, self.presentationRevision == revision else { return }
            self.isAutoDismissing = false
            self.isDismissing = false
            self.orderOut(nil)
        })
    }
}
