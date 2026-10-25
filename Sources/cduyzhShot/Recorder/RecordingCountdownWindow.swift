import AppKit

/// 录屏开始前的三秒倒计时；监听器与计时器只属于本次倒计时。
public final class RecordingCountdownWindow: NSPanel {
    private let numberLabel = NSTextField(labelWithString: "3")
    private var countdownValue = 3
    private var timer: Timer?
    private var onFinished: (() -> Void)?
    private var onCancelled: (() -> Void)?
    private var localEscMonitor: Any?
    private var isRunning = false
    private var deadline: TimeInterval = 0

    public override var canBecomeKey: Bool { true }

    public init(screen: NSScreen? = NSScreen.main) {
        let screenFrame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        super.init(
            contentRect: screenFrame,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        isReleasedWhenClosed = false
        level = .screenSaver
        backgroundColor = NSColor.black.withAlphaComponent(0.14)
        isOpaque = false
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        setupUI()
    }

    deinit {
        timer?.invalidate()
        if let monitor = localEscMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    private func setupUI() {
        let container = NSView(frame: NSRect(origin: .zero, size: frame.size))
        contentView = container

        let card = NSVisualEffectView()
        card.material = .hudWindow
        card.blendingMode = .behindWindow
        card.state = .active
        card.wantsLayer = true
        card.layer?.cornerRadius = 24
        card.layer?.masksToBounds = true
        card.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(card)

        let title = NSTextField(labelWithString: "即将开始录制")
        title.font = .systemFont(ofSize: 13, weight: .medium)
        title.textColor = .secondaryLabelColor
        title.alignment = .center
        title.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(title)

        numberLabel.font = .monospacedDigitSystemFont(ofSize: 64, weight: .medium)
        numberLabel.textColor = .labelColor
        numberLabel.alignment = .center
        numberLabel.translatesAutoresizingMaskIntoConstraints = false
        numberLabel.setAccessibilityLabel("录制倒计时")
        card.addSubview(numberLabel)

        let hint = NSTextField(labelWithString: "按 Esc 取消")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.alignment = .center
        hint.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(hint)

        NSLayoutConstraint.activate([
            card.widthAnchor.constraint(equalToConstant: 204),
            card.heightAnchor.constraint(equalToConstant: 204),
            card.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            title.topAnchor.constraint(equalTo: card.topAnchor, constant: 26),
            title.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            numberLabel.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            numberLabel.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            hint.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -25),
            hint.centerXAnchor.constraint(equalTo: card.centerXAnchor)
        ])
    }

    public func startCountdown(onFinished: @escaping () -> Void, onCancelled: @escaping () -> Void) {
        cleanup()
        self.onFinished = onFinished
        self.onCancelled = onCancelled
        isRunning = true
        countdownValue = 3
        deadline = ProcessInfo.processInfo.systemUptime + 3
        updateNumber()

        localEscMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.isRunning, event.keyCode == 53 else { return event }
            self.cancelCountdown()
            return nil
        }
        makeKeyAndOrderFront(nil)

        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, self.isRunning else { return }
            let remaining = Int(ceil(self.deadline - ProcessInfo.processInfo.systemUptime))
            if remaining <= 0 {
                let callback = self.onFinished
                self.cleanup()
                callback?()
            } else if remaining != self.countdownValue {
                self.countdownValue = remaining
                self.updateNumber()
            }
        }
        timer.tolerance = 0.02
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    public func cancelCountdown() {
        guard isRunning else { return }
        let callback = onCancelled
        cleanup()
        callback?()
    }

    public override func close() {
        cancelCountdown()
        super.close()
    }

    private func updateNumber() {
        numberLabel.stringValue = "\(countdownValue)"
        SoundManager.shared.playCameraShutterSound()
    }

    private func cleanup() {
        isRunning = false
        timer?.invalidate()
        timer = nil
        if let monitor = localEscMonitor {
            NSEvent.removeMonitor(monitor)
            localEscMonitor = nil
        }
        onFinished = nil
        onCancelled = nil
        orderOut(nil)
    }
}
