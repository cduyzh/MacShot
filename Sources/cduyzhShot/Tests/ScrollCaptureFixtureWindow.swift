import AppKit

/// 随正式应用提供的本地使用示例，也用于验证真实屏幕捕获。
final class ScrollCaptureFixtureWindow: NSWindowController {
    static let shared = ScrollCaptureFixtureWindow()
    private let scrollView = NSScrollView()
    private let status = NSTextField(wrappingLabelWithString: "就绪：可从中间开始，再选“向上捕获 / 向下捕获”。快滚后可点“帮我接回”。")
    private let sourceImage: CGImage
    private let logicalSize = NSSize(width: 600, height: 1800)
    private let step: CGFloat = 100
    private var progressTimer: Timer?
    private var resultURL: URL {
        CacheManager.shared.cacheDirectory.appendingPathComponent("Examples", isDirectory: true).appendingPathComponent("scroll-example-result.png")
    }

    private init() {
        sourceImage = Self.makeDocument()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 650),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "长截图使用示例"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildUI(window)
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildUI(_ window: NSWindow) {
        let root = NSView()
        window.contentView = root
        let doc = FixtureImageView(image: sourceImage, size: logicalSize)
        scrollView.documentView = doc
        scrollView.hasVerticalScroller = true
        scrollView.scrollerStyle = .legacy
        scrollView.drawsBackground = true
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(scrollView)
        let controls = NSStackView()
        controls.orientation = .horizontal
        controls.spacing = 8
        controls.translatesAutoresizingMaskIntoConstraints = false
        for (title, selector) in [
            ("开始长截图", #selector(start)), ("下一段", #selector(down)),
            ("上一段", #selector(up)), ("完成", #selector(finish)),
            ("取消", #selector(cancel)), ("回到顶部", #selector(reset))
        ] {
            let button = NSButton(title: title, target: self, action: selector)
            button.bezelStyle = .rounded
            controls.addArrangedSubview(button)
        }
        root.addSubview(controls)
        let jumps = NSStackView()
        jumps.orientation = .horizontal
        jumps.spacing = 8
        jumps.translatesAutoresizingMaskIntoConstraints = false
        for (title, selector) in [("快滚一屏", #selector(jump)), ("到中间", #selector(middle)), ("到底部", #selector(bottom)),
                                  ("向上捕获", #selector(autoUp)), ("向下捕获", #selector(autoDown)), ("帮我接回", #selector(recover))] {
            let button = NSButton(title: title, target: self, action: selector)
            button.bezelStyle = .rounded
            jumps.addArrangedSubview(button)
        }
        root.addSubview(jumps)
        status.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        status.translatesAutoresizingMaskIntoConstraints = false
        status.setAccessibilityLabel("示例状态")
        root.addSubview(status)
        NSLayoutConstraint.activate([
            controls.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            controls.topAnchor.constraint(equalTo: root.topAnchor, constant: 18),
            controls.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -20),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            jumps.leadingAnchor.constraint(equalTo: controls.leadingAnchor),
            jumps.topAnchor.constraint(equalTo: controls.bottomAnchor, constant: 8),
            scrollView.topAnchor.constraint(equalTo: jumps.bottomAnchor, constant: 16),
            scrollView.widthAnchor.constraint(equalToConstant: 615),
            scrollView.heightAnchor.constraint(equalToConstant: 420),
            status.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            status.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 16),
            status.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            status.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -12)
        ])
        root.layoutSubtreeIfNeeded()
        scrollView.contentView.scroll(to: .zero)
    }

    @objc private func start() {
        guard let window else { return }
        let clip = scrollView.contentView
        let content = clip.convert(clip.bounds, to: nil)
        let rect = window.convertToScreen(content)
        // 排除右侧原生滚动条，仅捕获 600 点宽的文档。
        let region = CGRect(x: rect.minX, y: rect.minY, width: logicalSize.width, height: rect.height)
        do {
            try FileManager.default.createDirectory(at: resultURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            status.stringValue = "无法保存示例：\(error.localizedDescription)"
            return
        }
        let reference = resultURL.deletingLastPathComponent().appendingPathComponent("scroll-example-reference.png")
        if let data = NSBitmapImageRep(cgImage: sourceImage).representation(using: .png, properties: [:]) {
            try? data.write(to: reference, options: .atomic)
        }
        status.stringValue = "捕获中 · 视口 \(Int(region.width)) × \(Int(region.height)) 点"
        ScrollCaptureManager.shared.start(in: region, targetApp: NSRunningApplication.current, onError: { [weak self] message in
            self?.status.stringValue = "失败：\(message)"
        }) { [weak self] image in
            guard let self else { return }
            self.progressTimer?.invalidate()
            self.progressTimer = nil
            guard let image else { self.status.stringValue = "已取消；未导出图片。"; return }
            do {
                guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
                try data.write(to: self.resultURL, options: .atomic)
                self.status.stringValue = "完成：\(image.width) × \(image.height) px\n\(self.resultURL.path)"
            } catch { self.status.stringValue = "导出失败：\(error.localizedDescription)" }
        }
        progressTimer?.invalidate()
        if ScrollCaptureManager.shared.isRunning {
            let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
                self?.status.stringValue = "捕获中 · 已拼接 \(ScrollCaptureManager.shared.capturedPixelHeight.formatted()) px；选择方向后会自动滚动，到边缘后可换方向。"
            }
            RunLoop.main.add(timer, forMode: .common)
            progressTimer = timer
        }
    }

    @objc private func down() { move(step) }
    @objc private func up() { move(-step) }
    @objc private func finish() { ScrollCaptureManager.shared.finish() }
    @objc private func cancel() { ScrollCaptureManager.shared.cancel() }
    @objc private func reset() { move(-logicalSize.height) }
    @objc private func autoUp() { ScrollCaptureManager.shared.setAutoScroll(.up) }
    @objc private func autoDown() { ScrollCaptureManager.shared.setAutoScroll(.down) }
    @objc private func recover() { ScrollCaptureManager.shared.recoverOverlap() }
    @objc private func jump() { move(scrollView.contentView.bounds.height * 1.1) }
    @objc private func middle() {
        let clip = scrollView.contentView
        move((logicalSize.height - clip.bounds.height) / 2 - clip.bounds.minY)
    }
    @objc private func bottom() { move(logicalSize.height) }

    private func move(_ delta: CGFloat) {
        let clip = scrollView.contentView
        let y = min(max(0, clip.bounds.minY + delta), logicalSize.height - clip.bounds.height)
        clip.scroll(to: NSPoint(x: 0, y: y))
        scrollView.reflectScrolledClipView(clip)
    }

    private static func makeDocument() -> CGImage {
        let width = 1200
        let height = 3600
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        for row in 0..<18 {
            let top = height - row * 200
            NSColor(calibratedRed: CGFloat((row * 37) % 130 + 110) / 255,
                    green: CGFloat((row * 61) % 130 + 110) / 255,
                    blue: CGFloat((row * 83) % 130 + 110) / 255, alpha: 1).setFill()
            NSRect(x: 0, y: top - 200, width: width, height: 200).fill()
            let title = String(format: "%02d", row + 1) + "   滚动长截图 · 测试文档"
            (title as NSString).draw(at: NSPoint(x: 42, y: top - 75), withAttributes: [
                .font: NSFont.systemFont(ofSize: 30, weight: .semibold), .foregroundColor: NSColor.black
            ])
            ("每一段只应出现一次；文字方向应保持正确。" as NSString).draw(at: NSPoint(x: 42, y: top - 125), withAttributes: [
                .font: NSFont.systemFont(ofSize: 22), .foregroundColor: NSColor.darkGray
            ])
            // 非周期的细节帮助定位到像素，避免纯色区域导致不可辨识的位移。
            for column in 0..<30 {
                NSColor.black.withAlphaComponent(0.2).setFill()
                let bar = (row * 17 + column * 13) % 45 + 4
                NSRect(x: column * 40, y: top - 190, width: 3, height: bar).fill()
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.cgImage!
    }
}

private final class FixtureImageView: NSView {
    private let image: NSImage
    override var isFlipped: Bool { true }
    init(image: CGImage, size: NSSize) {
        self.image = NSImage(cgImage: image, size: size)
        super.init(frame: NSRect(origin: .zero, size: size))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ dirtyRect: NSRect) {
        image.draw(in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true,
                   hints: [.interpolation: NSImageInterpolation.none])
    }
}
