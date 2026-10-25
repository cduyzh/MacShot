import AppKit

/// 非激活面板：保留最后成功拼接的画面，在失配时作为找回位置的视觉参照。
public final class ScrollCapturePreviewWindow: NSPanel {
    private let thumbnail = NSImageView()
    private let heightLabel = NSTextField(labelWithString: "正在准备…")
    private let referenceLabel = NSTextField(labelWithString: "已接上的画面")
    private let hintLabel = NSTextField(wrappingLabelWithString: "在选区内上下滚动，或选择自动捕获方向。")
    private let upButton = NSButton()
    private let downButton = NSButton()
    private let recoverButton = NSButton()
    private let doneButton = NSButton()
    private let cancelButton = NSButton()
    public var onDone: (() -> Void)?
    public var onCancel: (() -> Void)?
    public var onAutoScrollDirection: ((ScrollCaptureDirection?) -> Void)?
    public var onRecover: (() -> Void)?
    private var autoDirection: ScrollCaptureDirection?
    private var hasAccessibility = false
    private var capturedHeight: Int?
    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }

    public init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 372, height: 236),
                   styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        title = "滚动长截图控制"
        setAccessibilityLabel("滚动长截图控制")
        isFloatingPanel = true
        isReleasedWhenClosed = false
        level = .statusBar + 5
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        setupUI()
    }

    private func setupUI() {
        let container = NSVisualEffectView(frame: NSRect(origin: .zero, size: frame.size))
        container.material = .hudWindow
        container.blendingMode = .behindWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 16
        container.layer?.masksToBounds = true
        contentView = container
        thumbnail.imageScaling = .scaleProportionallyUpOrDown
        thumbnail.wantsLayer = true
        thumbnail.layer?.cornerRadius = 7
        thumbnail.layer?.masksToBounds = true
        thumbnail.setAccessibilityLabel("最后成功拼接的画面；找回位置时请对照此图")
        heightLabel.font = .monospacedDigitSystemFont(ofSize: 18, weight: .semibold)
        heightLabel.textColor = .labelColor
        referenceLabel.font = .systemFont(ofSize: 10)
        referenceLabel.textColor = .tertiaryLabelColor
        hintLabel.font = .systemFont(ofSize: 12)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.maximumNumberOfLines = 5
        for view in [thumbnail, heightLabel, referenceLabel, hintLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
        }
        let directions = NSStackView(views: [upButton, downButton])
        let actions = NSStackView(views: [cancelButton, recoverButton, doneButton])
        for row in [directions, actions] {
            row.orientation = .horizontal
            row.spacing = 8
            row.distribution = .fillEqually
            row.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(row)
        }
        configure(upButton, title: "向上捕获", symbol: "arrow.up", action: #selector(upClicked))
        configure(downButton, title: "向下捕获", symbol: "arrow.down", action: #selector(downClicked))
        configure(recoverButton, title: "帮我接回", symbol: "arrow.uturn.backward", action: #selector(recoverClicked))
        configure(cancelButton, title: "取消", symbol: "xmark", action: #selector(cancelClicked))
        configure(doneButton, title: "完成", symbol: "checkmark", action: #selector(doneClicked))
        doneButton.bezelColor = .controlAccentColor
        doneButton.contentTintColor = .white
        doneButton.isEnabled = false
        upButton.isEnabled = false
        downButton.isEnabled = false
        recoverButton.isHidden = true
        cancelButton.toolTip = "取消并丢弃本次长截图（Esc）"
        doneButton.toolTip = "完成长截图（Enter）"
        upButton.toolTip = "自动向上查看文档，将前面的内容接到长图顶部；再次点击暂停"
        downButton.toolTip = "自动向下查看文档，将后面的内容接到长图底部；再次点击暂停"
        recoverButton.toolTip = "反向小步滚动，找到可靠重叠后停止；需要辅助功能权限"
        NSLayoutConstraint.activate([
            thumbnail.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            thumbnail.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            thumbnail.widthAnchor.constraint(equalToConstant: 78),
            thumbnail.heightAnchor.constraint(equalToConstant: 96),
            referenceLabel.centerXAnchor.constraint(equalTo: thumbnail.centerXAnchor),
            referenceLabel.topAnchor.constraint(equalTo: thumbnail.bottomAnchor, constant: 5),
            heightLabel.leadingAnchor.constraint(equalTo: thumbnail.trailingAnchor, constant: 16),
            heightLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            heightLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            hintLabel.leadingAnchor.constraint(equalTo: heightLabel.leadingAnchor),
            hintLabel.trailingAnchor.constraint(equalTo: heightLabel.trailingAnchor),
            hintLabel.topAnchor.constraint(equalTo: heightLabel.bottomAnchor, constant: 8),
            hintLabel.bottomAnchor.constraint(lessThanOrEqualTo: directions.topAnchor, constant: -12),
            directions.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            directions.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            directions.bottomAnchor.constraint(equalTo: actions.topAnchor, constant: -10),
            directions.heightAnchor.constraint(equalToConstant: 32),
            actions.leadingAnchor.constraint(equalTo: directions.leadingAnchor),
            actions.trailingAnchor.constraint(equalTo: directions.trailingAnchor),
            actions.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),
            actions.heightAnchor.constraint(equalToConstant: 30)
        ])
    }

    private func configure(_ button: NSButton, title: String, symbol: String, action: Selector) {
        button.title = title
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.imagePosition = .imageLeading
        button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        button.font = .systemFont(ofSize: 12, weight: .medium)
        button.bezelStyle = .rounded
        button.target = self
        button.action = action
        button.setAccessibilityLabel(title)
    }

    public func updatePreview(image: CGImage, totalHeight: Int) {
        capturedHeight = totalHeight
        thumbnail.image = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        restoreHeightLabel()
        doneButton.isEnabled = true
        upButton.isEnabled = true
        downButton.isEnabled = true
    }

    public func setAutoScrollState(direction: ScrollCaptureDirection?, isAccessibilityGranted: Bool) {
        restoreHeightLabel()
        autoDirection = direction
        hasAccessibility = isAccessibilityGranted
        recoverButton.isHidden = true
        updateDirectionButtons()
        resetDoneButton()
        setStatus(direction.map { "正在\($0.title)捕获；手动滚动可接管。空格暂停。" }
            ?? "在选区内上下滚动，建议每次半屏。也可选择自动捕获方向；Enter 完成。")
    }

    private func updateDirectionButtons() {
        for (button, direction) in [(upButton, ScrollCaptureDirection.up), (downButton, .down)] {
            let active = autoDirection == direction
            button.title = active ? "暂停\(direction.title)" : "\(direction.title)捕获"
            button.image = NSImage(systemSymbolName: active ? "pause.fill" : direction.symbol, accessibilityDescription: nil)
            button.setAccessibilityLabel(button.title)
        }
    }

    public func setStatus(_ message: String, isWarning: Bool = false) {
        hintLabel.stringValue = message
        hintLabel.textColor = isWarning ? .systemOrange : .secondaryLabelColor
        hintLabel.toolTip = message
    }

    public func showRecovering(direction: ScrollCaptureDirection, isSearching: Bool = false, canSavePartial: Bool = false) {
        restoreHeightLabel()
        autoDirection = nil
        updateDirectionButtons()
        upButton.isEnabled = false
        downButton.isEnabled = false
        recoverButton.isHidden = false
        recoverButton.isEnabled = hasAccessibility && !isSearching
        recoverButton.title = isSearching ? "正在接回…" : "帮我接回"
        recoverButton.setAccessibilityLabel(recoverButton.title)
        doneButton.isEnabled = true
        if canSavePartial {
            doneButton.title = "保存当前"
            doneButton.toolTip = "保存已经成功拼接的部分；未接上的画面不会加入"
            doneButton.setAccessibilityLabel("保存已捕获部分")
        }
        referenceLabel.stringValue = "请对照这幅画面"
        let message = isSearching ? "正在\(direction.title)小步寻找重叠，接上后会自动停止。手动滚动可接管。"
            : "先\(direction.title)回滚半屏，对照左图找回内容；接上会自动继续。\(hasAccessibility ? "也可点“帮我接回”。" : "建议每次只滚半屏。")"
        setStatus(message, isWarning: !isSearching)
    }

    private func resetDoneButton() {
        doneButton.title = "完成"
        doneButton.toolTip = "完成长截图（Enter）"
        doneButton.setAccessibilityLabel("完成长截图")
        referenceLabel.stringValue = "已接上的画面"
    }

    public func showTargetPaused(_ message: String) {
        restoreHeightLabel()
        autoDirection = nil
        updateDirectionButtons()
        upButton.isEnabled = true
        downButton.isEnabled = true
        recoverButton.isHidden = true
        doneButton.isEnabled = true
        resetDoneButton()
        setStatus(message, isWarning: true)
    }

    public func showInterrupted(_ message: String) {
        restoreHeightLabel()
        autoDirection = nil
        updateDirectionButtons()
        upButton.isEnabled = false
        downButton.isEnabled = false
        recoverButton.isHidden = true
        doneButton.isEnabled = true
        doneButton.title = "保存当前"
        doneButton.toolTip = "保存已经成功拼接的部分"
        doneButton.setAccessibilityLabel("保存已捕获部分")
        setStatus(message, isWarning: true)
    }

    public func showFinishing() {
        upButton.isEnabled = false
        downButton.isEnabled = false
        recoverButton.isEnabled = false
        doneButton.isEnabled = false
        heightLabel.stringValue = "正在合成…"
        setStatus("正在生成完整图片，请稍候。")
    }

    private func restoreHeightLabel() {
        guard let capturedHeight else { return }
        heightLabel.stringValue = "\(capturedHeight.formatted()) px"
        heightLabel.setAccessibilityLabel("已捕获高度 \(capturedHeight) 像素")
    }

    @objc private func upClicked() { onAutoScrollDirection?(autoDirection == .up ? nil : .up) }
    @objc private func downClicked() { onAutoScrollDirection?(autoDirection == .down ? nil : .down) }
    @objc private func recoverClicked() { onRecover?() }
    @objc private func doneClicked() { onDone?() }
    @objc private func cancelClicked() { onCancel?() }
}
