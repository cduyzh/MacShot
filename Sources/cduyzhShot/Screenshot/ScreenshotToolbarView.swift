import AppKit

public protocol ScreenshotToolbarDelegate: AnyObject {
    func toolbarDidSelectTool(_ tool: AnnotationTool)
    func toolbarDidSelectColor(_ color: NSColor)
    func toolbarDidClickPin()
    func toolbarDidClickStudio()
    func toolbarDidClickScrollCapture()
    func toolbarDidClickRecord()
    func toolbarDidClickUndo()
    func toolbarDidClickSave()
    func toolbarDidClickCopy()
    func toolbarDidClickCancel()
}

// MARK: - Dark Toolbar Icon Button
public final class DarkToolbarIconButton: NSButton {
    private var trackingAreaRef: NSTrackingArea?
    public var tooltipItem: ToolbarTooltipItem?
    public var onHoverChanged: ((_ isHovered: Bool, _ button: NSView) -> Void)?

    public var isToolActive: Bool = false {
        didSet {
            state = isToolActive ? .on : .off
            updateVisualState()
        }
    }
    public var normalTintColor: NSColor = NSColor(white: 0.94, alpha: 1.0) {
        didSet { updateVisualState() }
    }
    public var customBackgroundColor: NSColor? {
        didSet { updateVisualState() }
    }
    public var customBorderColor: NSColor? {
        didSet { updateVisualState() }
    }

    private var isHovered: Bool = false
    private var isPressed: Bool = false

    public override var isEnabled: Bool {
        didSet {
            if !isEnabled { onHoverChanged?(false, self) }
            updateVisualState()
            window?.invalidateCursorRects(for: self)
        }
    }

    public init(symbol: String, tooltip: String = "", width: CGFloat = 28, height: CGFloat = 28, pointSize: CGFloat = 14, weight: NSFont.Weight = .medium) {
        super.init(frame: .zero)
        setup(symbol: symbol, tooltip: tooltip, width: width, height: height, pointSize: pointSize, weight: weight)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup(symbol: String, tooltip: String, width: CGFloat, height: CGFloat, pointSize: CGFloat, weight: NSFont.Weight) {
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.masksToBounds = false
        toolTip = nil
        setAccessibilityLabel(tooltip.isEmpty ? symbol : tooltip)

        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)?.withSymbolConfiguration(config) {
            image = img
            imagePosition = .imageOnly
            title = ""
        } else {
            title = symbol
        }

        updateVisualState()

        translatesAutoresizingMaskIntoConstraints = false
        let wc = widthAnchor.constraint(equalToConstant: width)
        wc.priority = .required
        let hc = heightAnchor.constraint(equalToConstant: height)
        hc.priority = .required
        NSLayoutConstraint.activate([wc, hc])
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingAreaRef {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    public override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isHovered = true
        updateVisualState()
        if isEnabled { onHoverChanged?(true, self) }
    }

    public override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovered = false
        updateVisualState()
        onHoverChanged?(false, self)
    }

    public override func resetCursorRects() {
        super.resetCursorRects()
        if isEnabled { addCursorRect(bounds, cursor: .pointingHand) }
    }

    public override func highlight(_ flag: Bool) {
        super.highlight(flag)
        isPressed = flag
        updateVisualState()
    }

    private func updateVisualState() {
        layer?.borderColor = nil
        layer?.borderWidth = 0
        alphaValue = isEnabled ? 1 : 0.35
        if isToolActive {
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(isPressed ? 0.75 : 0.95).cgColor
            contentTintColor = .white
        } else if let customBg = customBackgroundColor {
            let bgAlpha = isEnabled && (isHovered || isPressed) ? min(1.0, customBg.alphaComponent + 0.08) : customBg.alphaComponent
            layer?.backgroundColor = customBg.withAlphaComponent(bgAlpha).cgColor
            layer?.borderColor = customBorderColor?.cgColor
            layer?.borderWidth = customBorderColor != nil ? 0.5 : 0
            contentTintColor = normalTintColor
        } else if isEnabled && (isHovered || isPressed) {
            layer?.backgroundColor = NSColor(white: 1.0, alpha: isPressed ? 0.21 : 0.11).cgColor
            contentTintColor = .white
        } else {
            layer?.backgroundColor = nil
            contentTintColor = normalTintColor
        }
    }
}

// MARK: - Color Swatch Button
public final class ColorIndicatorButton: NSButton {
    private var trackingAreaRef: NSTrackingArea?
    public var tooltipItem: ToolbarTooltipItem?
    public var onHoverChanged: ((_ isHovered: Bool, _ button: NSView) -> Void)?

    public var selectedColor: NSColor = PresetColor.red.color {
        didSet {
            colorLayer.backgroundColor = selectedColor.cgColor
            setAccessibilityValue(PresetColor.all.first(where: { $0.color == selectedColor })?.name)
            needsDisplay = true
        }
    }

    private let colorLayer = CALayer()

    public override var isEnabled: Bool {
        didSet {
            alphaValue = isEnabled ? 1 : 0.35
            if !isEnabled { onHoverChanged?(false, self) }
            window?.invalidateCursorRects(for: self)
        }
    }

    public init() {
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        title = ""
        isBordered = false
        wantsLayer = true
        toolTip = nil
        setAccessibilityLabel("标注颜色")

        colorLayer.cornerRadius = 8
        colorLayer.masksToBounds = true
        colorLayer.backgroundColor = selectedColor.cgColor
        colorLayer.borderColor = NSColor.white.withAlphaComponent(0.85).cgColor
        colorLayer.borderWidth = 1.5
        layer?.addSublayer(colorLayer)

        translatesAutoresizingMaskIntoConstraints = false
        let wc = widthAnchor.constraint(equalToConstant: 22)
        wc.priority = .required
        let hc = heightAnchor.constraint(equalToConstant: 24)
        hc.priority = .required
        NSLayoutConstraint.activate([wc, hc])
    }

    public override func layout() {
        super.layout()
        let side: CGFloat = 16
        colorLayer.frame = CGRect(
            x: (bounds.width - side) / 2,
            y: (bounds.height - side) / 2,
            width: side,
            height: side
        )
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingAreaRef {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    public override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        guard isEnabled else { return }
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            colorLayer.transform = CATransform3DMakeScale(1.06, 1.06, 1.0)
        }
        onHoverChanged?(true, self)
    }

    public override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        colorLayer.transform = CATransform3DIdentity
        onHoverChanged?(false, self)
    }

    public override func resetCursorRects() {
        super.resetCursorRects()
        if isEnabled { addCursorRect(bounds, cursor: .pointingHand) }
    }
}

// MARK: - Recording Action
public final class RecordingToolbarButton: NSButton {
    private var trackingAreaRef: NSTrackingArea?
    public var tooltipItem: ToolbarTooltipItem?
    public var onHoverChanged: ((_ isHovered: Bool, _ button: NSView) -> Void)?
    private var isHovered = false
    private var isPressed = false

    public override var isEnabled: Bool {
        didSet {
            if !isEnabled { onHoverChanged?(false, self) }
            updateVisualState()
            window?.invalidateCursorRects(for: self)
        }
    }

    public init() {
        super.init(frame: .zero)
        title = ""
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.shadowColor = NSColor.systemRed.cgColor
        layer?.shadowOffset = .zero
        layer?.shadowOpacity = 0.04
        layer?.shadowRadius = 1.5
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        image = NSImage(systemSymbolName: "record.circle", accessibilityDescription: "选区录屏")?.withSymbolConfiguration(config)
        imagePosition = .imageOnly
        toolTip = nil
        setAccessibilityLabel("选区录屏")
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 34),
            heightAnchor.constraint(equalToConstant: 28)
        ])
        updateVisualState()
        startDynamicAnimations()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func startDynamicAnimations() {
        layer?.removeAnimation(forKey: "breathingShadowOpacity")
        layer?.removeAnimation(forKey: "breathingShadowRadius")
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }

        let opacity = CABasicAnimation(keyPath: "shadowOpacity")
        opacity.fromValue = 0.04
        opacity.toValue = 0.10
        let radius = CABasicAnimation(keyPath: "shadowRadius")
        radius.fromValue = 1.5
        radius.toValue = 2.5
        for animation in [opacity, radius] {
            animation.duration = 2.4
            animation.autoreverses = true
            animation.repeatCount = .infinity
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        }
        layer?.add(opacity, forKey: "breathingShadowOpacity")
        layer?.add(radius, forKey: "breathingShadowRadius")
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area = trackingAreaRef { removeTrackingArea(area) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingAreaRef = area
    }

    public override func resetCursorRects() {
        super.resetCursorRects()
        if isEnabled { addCursorRect(bounds, cursor: .pointingHand) }
    }

    public override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isHovered = true
        updateVisualState()
        if isEnabled { onHoverChanged?(true, self) }
    }

    public override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovered = false
        updateVisualState()
        onHoverChanged?(false, self)
    }

    public override func highlight(_ flag: Bool) {
        super.highlight(flag)
        isPressed = flag
        updateVisualState()
    }

    private func updateVisualState() {
        alphaValue = isEnabled ? 1 : 0.35
        layer?.backgroundColor = isEnabled && (isHovered || isPressed)
            ? NSColor.systemRed.withAlphaComponent(isPressed ? 0.24 : 0.14).cgColor : nil
        contentTintColor = NSColor.systemRed.blended(withFraction: 0.18, of: .white)
    }
}

// MARK: - Screenshot Toolbar View
public final class ScreenshotToolbarView: NSView {
    public weak var delegate: ScreenshotToolbarDelegate?

    public private(set) var currentTool: AnnotationTool = .select
    public private(set) var currentColor: NSColor = PresetColor.red.color

    private var toolButtons: [AnnotationTool: DarkToolbarIconButton] = [:]
    private var colorIndicatorButton: ColorIndicatorButton?
    private var recordingButton: RecordingToolbarButton?

    private var tooltipShowWorkItem: DispatchWorkItem?
    private weak var hoveredTooltipButton: NSView?

    // 自定义快捷键提示与按钮共享辅助功能描述。
    public let tooltipBubble = ToolbarTooltipBubbleView()

    public override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: 570, height: 38))
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if let parent = superview {
            if tooltipBubble.superview != parent {
                tooltipBubble.removeFromSuperview()
                parent.addSubview(tooltipBubble)
            }
        } else {
            hideTooltip()
            tooltipBubble.removeFromSuperview()
        }
    }

    public func hideTooltip(animated: Bool = false) {
        tooltipShowWorkItem?.cancel()
        tooltipShowWorkItem = nil
        hoveredTooltipButton = nil
        tooltipBubble.hide(animated: animated)
    }

    private func handleButtonHover(isHovered: Bool, button: NSView, item: ToolbarTooltipItem) {
        if !isHovered {
            guard hoveredTooltipButton === button else { return }
            hideTooltip(animated: true)
            return
        }
        guard let container = superview ?? window?.contentView else { return }
        tooltipShowWorkItem?.cancel()
        hoveredTooltipButton = button
        if !tooltipBubble.isHidden {
            tooltipBubble.show(item: item, for: button, in: container)
            return
        }
        let work = DispatchWorkItem { [weak self, weak button, weak container] in
            guard let self, let button, let container,
                  self.hoveredTooltipButton === button else { return }
            self.tooltipBubble.show(item: item, for: button, in: container)
            self.tooltipShowWorkItem = nil
        }
        tooltipShowWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28, execute: work)
    }

    private func bindTooltip(button: NSView, item: ToolbarTooltipItem) {
        button.setAccessibilityLabel(item.title)
        let help = [item.shortcut, item.detail].compactMap { $0 }.joined(separator: "，")
        button.setAccessibilityHelp(help.isEmpty ? nil : help)
        if let btn = button as? DarkToolbarIconButton {
            btn.tooltipItem = item
            btn.onHoverChanged = { [weak self] isHovered, b in
                self?.handleButtonHover(isHovered: isHovered, button: b, item: item)
            }
        } else if let btn = button as? ColorIndicatorButton {
            btn.tooltipItem = item
            btn.onHoverChanged = { [weak self] isHovered, b in
                self?.handleButtonHover(isHovered: isHovered, button: b, item: item)
            }
        } else if let btn = button as? RecordingToolbarButton {
            btn.tooltipItem = item
            btn.onHoverChanged = { [weak self] isHovered, b in
                self?.handleButtonHover(isHovered: isHovered, button: b, item: item)
            }
        }
    }

    private func setupUI() {
        wantsLayer = true
        layer?.cornerRadius = 11
        layer?.masksToBounds = false
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.24
        layer?.shadowRadius = 12
        layer?.shadowOffset = CGSize(width: 0, height: -3)
        appearance = NSAppearance(named: .darkAqua)

        // Frosted glass background
        let visualEffect = NSVisualEffectView(frame: bounds)
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 11
        visualEffect.layer?.masksToBounds = true
        visualEffect.layer?.borderColor = NSColor(white: 1.0, alpha: 0.14).cgColor
        visualEffect.layer?.borderWidth = 0.5
        visualEffect.autoresizingMask = [.width, .height]
        addSubview(visualEffect)

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        // Cluster 1: Core Annotation Tools
        let tools: [(AnnotationTool, String, ToolbarTooltipItem)] = [
            (.rect, "square", ToolbarTooltipItem(title: "矩形", shortcut: "1")),
            (.ellipse, "circle", ToolbarTooltipItem(title: "圆形", shortcut: "2")),
            (.arrow, "arrow.right", ToolbarTooltipItem(title: "箭头", shortcut: "3")),
            (.line, "line.diagonal", ToolbarTooltipItem(title: "直线")),
            (.mosaic, "checkerboard.rectangle", ToolbarTooltipItem(title: "马赛克", shortcut: "6")),
            (.text, "textformat", ToolbarTooltipItem(title: "文字", shortcut: "7")),
            (.stepBadge, "number.circle", ToolbarTooltipItem(title: "序号", shortcut: "8"))
        ]

        for (tool, symbol, tipItem) in tools {
            let btn = DarkToolbarIconButton(symbol: symbol)
            btn.target = self
            btn.action = #selector(toolButtonClicked(_:))
            bindTooltip(button: btn, item: tipItem)
            toolButtons[tool] = btn
            stack.addArrangedSubview(btn)
        }

        stack.addArrangedSubview(createDivider())

        // Cluster 2: Annotation Color
        let colorIndicator = ColorIndicatorButton()
        colorIndicator.selectedColor = currentColor
        colorIndicator.target = self
        colorIndicator.action = #selector(colorIndicatorClicked)
        bindTooltip(button: colorIndicator, item: ToolbarTooltipItem(title: "标注颜色", shortcut: "点击展开"))
        self.colorIndicatorButton = colorIndicator
        stack.addArrangedSubview(colorIndicator)

        stack.addArrangedSubview(createDivider())

        // Cluster 3: Special Capture Actions (Pin, Studio, Scroll Capture, and Dynamic Recording)
        let pinBtn = DarkToolbarIconButton(symbol: "pin.fill")
        pinBtn.target = self
        pinBtn.action = #selector(pinClicked)
        bindTooltip(button: pinBtn, item: ToolbarTooltipItem(title: "钉在屏幕上", shortcut: "⌥P"))
        stack.addArrangedSubview(pinBtn)

        let studioBtn = DarkToolbarIconButton(symbol: "wand.and.stars")
        studioBtn.target = self
        studioBtn.action = #selector(studioClicked)
        bindTooltip(button: studioBtn, item: ToolbarTooltipItem(title: "图片美化", shortcut: "E"))
        stack.addArrangedSubview(studioBtn)

        let scrollBtn = DarkToolbarIconButton(symbol: "arrow.up.and.down.text.horizontal")
        scrollBtn.target = self
        scrollBtn.action = #selector(scrollClicked)
        bindTooltip(button: scrollBtn, item: ToolbarTooltipItem(title: "滚动长截图", shortcut: "⌥S"))
        stack.addArrangedSubview(scrollBtn)

        // DYNAMIC RECORDING BUTTON
        let recBtn = RecordingToolbarButton()
        recBtn.target = self
        recBtn.action = #selector(recordClicked)
        bindTooltip(button: recBtn, item: ToolbarTooltipItem(title: "选区录屏", shortcut: "R"))
        self.recordingButton = recBtn
        stack.addArrangedSubview(recBtn)

        stack.addArrangedSubview(createDivider())

        // Cluster 4: History & Output Tools (Undo, Cancel, Save As, and Done)
        let undoBtn = DarkToolbarIconButton(symbol: "arrow.uturn.backward")
        undoBtn.target = self
        undoBtn.action = #selector(undoClicked)
        bindTooltip(button: undoBtn, item: ToolbarTooltipItem(title: "撤销", shortcut: "⌘Z"))
        stack.addArrangedSubview(undoBtn)

        let cancelBtn = DarkToolbarIconButton(symbol: "xmark")
        cancelBtn.normalTintColor = NSColor(white: 0.82, alpha: 1.0)
        cancelBtn.target = self
        cancelBtn.action = #selector(cancelClicked)
        bindTooltip(button: cancelBtn, item: ToolbarTooltipItem(title: "取消截图", shortcut: "Esc"))
        stack.addArrangedSubview(cancelBtn)

        let saveBtn = DarkToolbarIconButton(symbol: "arrow.down.to.line")
        saveBtn.normalTintColor = NSColor(white: 0.94, alpha: 1.0)
        saveBtn.target = self
        saveBtn.action = #selector(saveClicked)
        bindTooltip(button: saveBtn, item: ToolbarTooltipItem(title: "另存为...", shortcut: "⌘S"))
        stack.addArrangedSubview(saveBtn)

        // 完成操作使用唯一的主强调色。
        let doneBtn = DarkToolbarIconButton(symbol: "checkmark", width: 34, height: 28, pointSize: 14, weight: .bold)
        doneBtn.normalTintColor = .white
        doneBtn.customBackgroundColor = NSColor.controlAccentColor
        doneBtn.target = self
        doneBtn.action = #selector(copyClicked)
        bindTooltip(button: doneBtn, item: ToolbarTooltipItem(title: "完成并复制", shortcut: "Enter"))
        stack.addArrangedSubview(doneBtn)
    }

    private func createDivider() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: 8),
            container.heightAnchor.constraint(equalToConstant: 26)
        ])

        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.13).cgColor
        line.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(line)

        NSLayoutConstraint.activate([
            line.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            line.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            line.widthAnchor.constraint(equalToConstant: 0.5),
            line.heightAnchor.constraint(equalToConstant: 18)
        ])
        return container
    }

    @objc private func toolButtonClicked(_ sender: DarkToolbarIconButton) {
        hideTooltip(animated: false)
        for (tool, btn) in toolButtons {
            if btn == sender {
                if currentTool == tool {
                    currentTool = .select
                    btn.isToolActive = false
                } else {
                    currentTool = tool
                    btn.isToolActive = true
                }
                delegate?.toolbarDidSelectTool(currentTool)
            } else {
                btn.isToolActive = false
            }
        }
    }

    @objc private func colorIndicatorClicked() {
        hideTooltip(animated: false)
        guard let button = colorIndicatorButton else { return }
        showColorPalettePopover(relativeTo: button)
    }

    private func showColorPalettePopover(relativeTo button: NSButton) {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.appearance = NSAppearance(named: .darkAqua)

        let vc = NSViewController()
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 226, height: 40))
        container.wantsLayer = true
        container.layer?.cornerRadius = 8
        container.layer?.backgroundColor = NSColor(calibratedWhite: 0.14, alpha: 0.98).cgColor

        let stack = NSStackView(frame: container.bounds.insetBy(dx: 8, dy: 6))
        stack.orientation = .horizontal
        stack.spacing = 7
        stack.alignment = .centerY

        for preset in PresetColor.all {
            let colorBtn = NSButton(frame: NSRect(x: 0, y: 0, width: 17, height: 17))
            colorBtn.isBordered = false
            colorBtn.wantsLayer = true
            colorBtn.layer?.cornerRadius = 8.5
            colorBtn.layer?.backgroundColor = preset.color.cgColor
            colorBtn.layer?.borderColor = (preset.color == currentColor) ? NSColor.white.cgColor : NSColor(white: 1.0, alpha: 0.35).cgColor
            colorBtn.layer?.borderWidth = (preset.color == currentColor) ? 2.5 : 0.8
            colorBtn.toolTip = preset.name
            colorBtn.setAccessibilityLabel(preset.name)
            colorBtn.state = preset.color == currentColor ? .on : .off
            colorBtn.target = self
            colorBtn.action = #selector(paletteColorSelected(_:))
            colorBtn.identifier = NSUserInterfaceItemIdentifier(preset.name)
            colorBtn.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                colorBtn.widthAnchor.constraint(equalToConstant: 17),
                colorBtn.heightAnchor.constraint(equalToConstant: 17)
            ])
            stack.addArrangedSubview(colorBtn)
        }

        container.addSubview(stack)
        vc.view = container
        popover.contentViewController = vc
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
    }

    @objc private func paletteColorSelected(_ sender: NSButton) {
        if let name = sender.identifier?.rawValue,
           let preset = PresetColor.all.first(where: { $0.name == name }) {
            currentColor = preset.color
            colorIndicatorButton?.selectedColor = currentColor
            delegate?.toolbarDidSelectColor(currentColor)
        }
    }

    @objc private func pinClicked() {
        hideTooltip(animated: false)
        delegate?.toolbarDidClickPin()
    }

    @objc private func studioClicked() {
        hideTooltip(animated: false)
        delegate?.toolbarDidClickStudio()
    }

    @objc private func scrollClicked() {
        hideTooltip(animated: false)
        delegate?.toolbarDidClickScrollCapture()
    }

    @objc private func recordClicked() {
        hideTooltip(animated: false)
        delegate?.toolbarDidClickRecord()
    }

    @objc private func undoClicked() {
        hideTooltip(animated: false)
        delegate?.toolbarDidClickUndo()
    }

    @objc private func saveClicked() {
        hideTooltip(animated: false)
        delegate?.toolbarDidClickSave()
    }

    @objc private func copyClicked() {
        hideTooltip(animated: false)
        delegate?.toolbarDidClickCopy()
    }

    @objc private func cancelClicked() {
        hideTooltip(animated: false)
        delegate?.toolbarDidClickCancel()
    }

    public func selectTool(_ tool: AnnotationTool) {
        if let btn = toolButtons[tool] {
            toolButtonClicked(btn)
        }
    }
}
