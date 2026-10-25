import AppKit

public final class RecordingToolbarWindow: NSPanel {
    private let timeLabel = NSTextField(labelWithString: "00:00")
    private let dotView = NSView()
    private let stopButton = NSButton()
    private let capturesSystemAudio: Bool
    private var startedAt: TimeInterval?
    private var elapsedSeconds = 0
    private var timer: Timer?

    public var onStop: (() -> Void)?
    // 保留调用方 API；暂停和取消尚未实现，因此不显示对应控件。
    public var onPauseToggle: ((Bool) -> Void)?
    public var onCancel: (() -> Void)?

    public init(capturesSystemAudio: Bool = true) {
        self.capturesSystemAudio = capturesSystemAudio
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 336, height: 48),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        isReleasedWhenClosed = false
        level = .statusBar + 10
        isMovableByWindowBackground = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        setupUI()
    }

    deinit {
        timer?.invalidate()
    }

    private func setupUI() {
        let container = NSVisualEffectView()
        container.material = .hudWindow
        container.blendingMode = .behindWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 14
        container.layer?.masksToBounds = true
        contentView = container

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 14, bottom: 8, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        dotView.wantsLayer = true
        dotView.layer?.cornerRadius = 4
        dotView.layer?.backgroundColor = NSColor.systemRed.cgColor
        dotView.translatesAutoresizingMaskIntoConstraints = false
        dotView.setAccessibilityLabel("正在录制")
        NSLayoutConstraint.activate([
            dotView.widthAnchor.constraint(equalToConstant: 8),
            dotView.heightAnchor.constraint(equalToConstant: 8)
        ])
        stack.addArrangedSubview(dotView)

        timeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        timeLabel.textColor = .labelColor
        timeLabel.setAccessibilityLabel("录制时长")
        timeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 58).isActive = true
        stack.addArrangedSubview(timeLabel)

        let soundSymbol = capturesSystemAudio ? "speaker.wave.2.fill" : "speaker.slash.fill"
        let soundDescription = capturesSystemAudio ? "录制系统声音" : "不录制声音"
        let soundIcon = NSImageView(image: NSImage(systemSymbolName: soundSymbol, accessibilityDescription: soundDescription) ?? NSImage())
        soundIcon.contentTintColor = .secondaryLabelColor
        soundIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        let soundBadge = NSTextField(labelWithString: capturesSystemAudio ? "系统声音" : "无声音")
        soundBadge.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        soundBadge.textColor = .secondaryLabelColor
        let soundStack = NSStackView(views: [soundIcon, soundBadge])
        soundStack.orientation = .horizontal
        soundStack.alignment = .centerY
        soundStack.spacing = 5
        soundStack.toolTip = soundDescription
        stack.addArrangedSubview(soundStack)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        stack.addArrangedSubview(spacer)

        stopButton.title = "结束录制"
        stopButton.image = NSImage(systemSymbolName: "stop.fill", accessibilityDescription: "结束录制")
        stopButton.imagePosition = .imageLeading
        stopButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
        stopButton.bezelStyle = .rounded
        stopButton.controlSize = .regular
        stopButton.contentTintColor = .systemRed
        stopButton.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        stopButton.toolTip = "完成录制并保存文件"
        stopButton.target = self
        stopButton.action = #selector(stopClicked)
        stopButton.setAccessibilityLabel("结束录制并保存")
        stack.addArrangedSubview(stopButton)
    }

    public func startTimer() {
        timer?.invalidate()
        elapsedSeconds = 0
        startedAt = ProcessInfo.processInfo.systemUptime
        updateTimeDisplay()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.updateTimeDisplay()
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    public func stopTimer() {
        updateTimeDisplay()
        startedAt = nil
        timer?.invalidate()
        timer = nil
    }

    public func showFinishing() {
        stopTimer()
        stopButton.isEnabled = false
        stopButton.title = "正在保存"
        stopButton.image = NSImage(systemSymbolName: "hourglass", accessibilityDescription: "正在保存录屏")
        dotView.layer?.backgroundColor = NSColor.secondaryLabelColor.cgColor
        dotView.setAccessibilityLabel("正在保存录屏")
    }

    private func updateTimeDisplay() {
        if let startedAt = startedAt {
            elapsedSeconds = max(0, Int(ProcessInfo.processInfo.systemUptime - startedAt))
        }
        let hours = elapsedSeconds / 3600
        let minutes = (elapsedSeconds % 3600) / 60
        let seconds = elapsedSeconds % 60
        timeLabel.stringValue = hours > 0
            ? String(format: "%02d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%02d:%02d", minutes, seconds)
    }

    @objc private func stopClicked() {
        guard stopButton.isEnabled else { return }
        showFinishing()
        onStop?()
    }
}
