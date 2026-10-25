import AppKit
import CoreGraphics

/// 会话状态与界面只在主线程变更；像素匹配/最终合成只在后台串行队列执行。
public final class ScrollCaptureManager {
    public static let shared = ScrollCaptureManager()
    private enum Phase { case preparing, capturing, finishing }
    private final class Session {
        let id = UUID()
        let rect: CGRect
        let screen: NSScreen
        let targetApp: NSRunningApplication?
        let stitcher = ImageStitcher()
        var phase: Phase = .preparing
        var source: ScrollCaptureFrameProviding?
        var inFlight = false
        var finishRequested = false
        var needsFinalFrame = false
        var autoScroll: ScrollCaptureDirection?
        var lastAutoDirection: ScrollCaptureDirection = .down
        var lastTravelDirection: ScrollCaptureDirection = .down
        var recovery = ScrollCaptureRecoveryState()
        var searchingForOverlap = false
        var recoverySearchSteps = 0
        var partialSaveOffered = false
        var lastManualScroll: TimeInterval = 0
        var endDetector = ScrollCaptureEndDetector()
        var captureFailures = 0
        var captureUnavailable = false
        var lastFrame: CGImage?
        var pixels = 0
        var onError: ((String) -> Void)?
        var completion: ((CGImage?) -> Void)?
        init(rect: CGRect, screen: NSScreen, targetApp: NSRunningApplication?, onError: ((String) -> Void)?, completion: @escaping (CGImage?) -> Void) {
            self.rect = rect
            self.screen = screen
            self.targetApp = targetApp
            self.onError = onError
            self.completion = completion
        }
    }
    private var session: Session?
    private var boxWindow: ScrollCaptureBoxWindow?
    private var previewWindow: ScrollCapturePreviewWindow?
    private var timer: Timer?
    private var localKeyMonitor: Any?
    private var globalKeyMonitor: Any?
    private var localScrollMonitor: Any?
    private var globalScrollMonitor: Any?
    private var keyTap: CFMachPort?
    private var keyTapSource: CFRunLoopSource?
    private let processingQueue = DispatchQueue(label: "com.cduyzh.shot.scroll-stitch", qos: .userInitiated)
    private static let scrollEventTag: Int64 = 0x4353484F54
    public var isRunning: Bool { session != nil }
    public var capturedPixelHeight: Int { session?.pixels ?? 0 }
    var isProcessingFrame: Bool { session?.inFlight ?? false }
    var isWaitingForOverlap: Bool { session?.recovery.hasGap ?? false }
    public private(set) var lastError: String?
    typealias SourceFactory = (CGRect, NSScreen, Set<CGWindowID>, pid_t?, @escaping (Result<ScrollCaptureFrameProviding, Error>) -> Void) -> Void
    private let makeSource: SourceFactory
    private let presentControls: Bool
    private let targetActivity: ((NSRunningApplication?) -> Bool)?

    init(presentControls: Bool = true, targetActivity: ((NSRunningApplication?) -> Bool)? = nil,
         makeSource: @escaping SourceFactory = { rect, screen, excluded, pid, completion in
        ScrollCaptureFrameSource.prepare(rect: rect, screen: screen, excludingWindowIDs: excluded, targetPID: pid) { result in
            completion(result.map { $0 as ScrollCaptureFrameProviding })
        }
    }) {
        self.presentControls = presentControls
        self.targetActivity = targetActivity
        self.makeSource = makeSource
    }

    /// 只清理本管理器拥有的资源，避免异步扫窗误关下一轮新窗口。
    public static func cleanupAllScrollWindows() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { cleanupAllScrollWindows() }
            return
        }
        if !shared.isRunning { shared.closePanels() }
    }

    public func start(in rect: CGRect, targetApp: NSRunningApplication? = nil,
                      onError: ((String) -> Void)? = nil, completion: @escaping (CGImage?) -> Void) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.start(in: rect, targetApp: targetApp, onError: onError, completion: completion) }
            return
        }
        cancel()
        lastError = nil
        guard rect.width.isFinite, rect.height.isFinite, rect.origin.x.isFinite, rect.origin.y.isFinite,
              rect.width >= 64, rect.height >= 80,
              let screen = NSScreen.screens.first(where: { $0.frame.insetBy(dx: -0.5, dy: -0.5).contains(rect) }) else {
            lastError = "请选择同一显示器内至少 64 × 80 点的滚动内容区域，避免包含侧栏或滚动条。"
            onError?(lastError!)
            completion(nil)
            return
        }
        let rect = rect.integral.intersection(screen.frame)
        let active = targetApp ?? NSWorkspace.shared.frontmostApplication
        let current = Session(rect: rect, screen: screen, targetApp: active, onError: onError, completion: completion)
        session = current
        var ownedIDs = Set<CGWindowID>()
        if presentControls {
            let box = ScrollCaptureBoxWindow(rect: rect)
            box.orderFrontRegardless()
            boxWindow = box
            let panel = ScrollCapturePreviewWindow()
            position(panel, around: rect, screen: screen)
            panel.onDone = { [weak self] in self?.finish() }
            panel.onCancel = { [weak self] in self?.cancel() }
            panel.onAutoScrollDirection = { [weak self] direction in self?.setAutoScroll(direction) }
            panel.onRecover = { [weak self] in self?.recoverOverlap() }
            panel.orderFrontRegardless()
            previewWindow = panel
            active?.activate()
            ownedIDs = Set([box.windowNumber, panel.windowNumber].filter { $0 > 0 }.map { CGWindowID($0) })
        }
        makeSource(rect, screen, ownedIDs, active?.processIdentifier) { [weak self, weak current] result in
            guard let self, let current, self.session === current else { return }
            switch result {
            case .failure(let error): self.fail(current, message: "无法开始长截图：\(error.localizedDescription)")
            case .success(let source):
                current.source = source
                self.sample(current, advance: false)
            }
        }
    }

    private func position(_ panel: NSPanel, around rect: CGRect, screen: NSScreen) {
        let area = screen.visibleFrame.insetBy(dx: 12, dy: 12)
        let size = panel.frame.size
        let candidates = [
            CGRect(x: rect.maxX + 12, y: rect.midY - size.height / 2, width: size.width, height: size.height),
            CGRect(x: rect.minX - size.width - 12, y: rect.midY - size.height / 2, width: size.width, height: size.height),
            CGRect(x: rect.midX - size.width / 2, y: rect.minY - size.height - 12, width: size.width, height: size.height),
            CGRect(x: rect.midX - size.width / 2, y: rect.maxY + 12, width: size.width, height: size.height)
        ]
        let origin = candidates.first(where: { area.contains($0) })?.origin
            ?? CGPoint(x: max(area.minX, area.maxX - size.width), y: max(area.minY, area.maxY - size.height))
        panel.setFrameOrigin(origin)
    }

    private func startTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in self?.tick() }
        timer.tolerance = 0.008
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func isTargetActive(_ current: Session) -> Bool {
        if let targetActivity { return targetActivity(current.targetApp) }
        guard presentControls, let target = current.targetApp else { return true }
        return NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier
    }

    func tick() {
        guard let current = session, current.phase != .finishing, current.source != nil,
              !current.inFlight, !current.finishRequested, !current.captureUnavailable else { return }
        guard current.targetApp?.isTerminated != true else { fail(current, message: "目标应用已退出，本次长截图已取消。"); return }
        guard isTargetActive(current) else {
            current.autoScroll = nil
            current.searchingForOverlap = false
            current.endDetector.reset()
            previewWindow?.setAutoScrollState(direction: nil, isAccessibilityGranted: Permissions.hasAccessibilityPermission)
            previewWindow?.setStatus("已暂停，请返回选区所在应用。", isWarning: true)
            return
        }
        sample(current, advance: current.searchingForOverlap || (current.autoScroll != nil && !current.recovery.hasGap))
    }

    private func pauseForTarget(_ current: Session) {
        current.inFlight = false
        let wasFinishing = current.finishRequested
        current.finishRequested = false
        current.needsFinalFrame = false
        current.autoScroll = nil
        current.endDetector.reset()
        current.searchingForOverlap = false
        previewWindow?.setAutoScrollState(direction: nil, isAccessibilityGranted: Permissions.hasAccessibilityPermission)
        if wasFinishing {
            previewWindow?.showTargetPaused("已切换到其他窗口。请返回选区所在应用后再完成。")
        } else {
            previewWindow?.setStatus("已暂停，请返回选区所在应用。", isWarning: true)
        }
        if presentControls && current.phase != .finishing && !current.captureUnavailable { startTimer() }
    }

    private func sample(_ current: Session, advance: Bool) {
        guard session === current, !current.inFlight, let source = current.source else { return }
        current.inFlight = true
        // 已在处理的普通帧不能替代“完成”请求之后读取的最终帧。
        let isFinalFrame = current.finishRequested && current.needsFinalFrame
        if isFinalFrame { current.needsFinalFrame = false }
        let scrollDirection = current.searchingForOverlap ? current.recovery.direction : current.autoScroll
        let shouldScroll = advance && scrollDirection != nil && ProcessInfo.processInfo.systemUptime - current.lastManualScroll > 0.5
        if shouldScroll, let scrollDirection {
            if current.searchingForOverlap { current.recoverySearchSteps += 1 }
            else { current.lastTravelDirection = scrollDirection }
            postScroll(in: current.rect, direction: scrollDirection, recovering: current.searchingForOverlap)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (shouldScroll || current.finishRequested ? 0.18 : 0)) { [weak self, weak current] in
            guard let self, let current, self.session === current else { return }
            if !self.isTargetActive(current) {
                self.pauseForTarget(current)
                return
            }
            source.capture { [weak self, weak current] result in
                guard let self, let current, self.session === current else { return }
                if !self.isTargetActive(current) {
                    self.pauseForTarget(current)
                    return
                }
                switch result {
                case .failure(let error):
                    current.inFlight = false
                    current.captureFailures += 1
                    if current.pixels == 0 {
                        self.fail(current, message: error.localizedDescription)
                    } else if current.captureFailures >= 3 || current.finishRequested {
                        current.captureUnavailable = true
                        current.finishRequested = false
                        current.needsFinalFrame = false
                        current.autoScroll = nil
                        current.searchingForOverlap = false
                        self.timer?.invalidate()
                        self.timer = nil
                        if let lastFrame = current.lastFrame {
                            self.previewWindow?.updatePreview(image: lastFrame, totalHeight: current.pixels)
                        }
                        self.previewWindow?.setAutoScrollState(direction: nil, isAccessibilityGranted: Permissions.hasAccessibilityPermission)
                        self.previewWindow?.showInterrupted("读取中断。可保存已捕获部分，或取消后重选区域。")
                        self.lastError = error.localizedDescription
                    } else {
                        self.previewWindow?.setStatus("画面暂时无法读取，正在重试…", isWarning: true)
                    }
                case .success(let image):
                    let preparing = current.phase == .preparing
                    self.processingQueue.async {
                        autoreleasepool {
                            if preparing { current.stitcher.start(with: image) }
                            else { current.stitcher.process(newFrame: image) }
                            let outcome = current.stitcher.lastResult
                            let height = current.stitcher.totalStitchedHeight
                            DispatchQueue.main.async {
                                guard self.session === current else { return }
                                current.inFlight = false
                                current.captureFailures = 0
                                current.pixels = height
                                if preparing && height == 0 { self.fail(current, message: "选区像素超出内存限制，请缩小区域。"); return }
                                switch outcome {
                                case .appended, .backtracked, .unchanged:
                                    current.lastFrame = image
                                    self.previewWindow?.updatePreview(image: image, totalHeight: height)
                                default: break // 保留最后成功的画面，供用户找回位置时对照。
                                }
                                if current.finishRequested { self.previewWindow?.showFinishing() }
                                if preparing {
                                    current.phase = .capturing
                                    if self.presentControls { self.installMonitors() }
                                    self.previewWindow?.setAutoScrollState(direction: nil, isAccessibilityGranted: Permissions.hasAccessibilityPermission)
                                    if self.presentControls { self.startTimer() }
                                } else if isFinalFrame && outcome == .unmatched {
                                    current.finishRequested = false
                                    current.needsFinalFrame = false
                                    current.autoScroll = nil
                                    current.searchingForOverlap = false
                                    current.partialSaveOffered = true
                                    _ = current.recovery.observeMiss(now: ProcessInfo.processInfo.systemUptime, travelDirection: current.lastTravelDirection)
                                    self.lastError = "最后一段尚未接上。可找回位置后继续，或保存已捕获部分。"
                                    self.previewWindow?.setAutoScrollState(direction: nil, isAccessibilityGranted: Permissions.hasAccessibilityPermission)
                                    self.previewWindow?.showRecovering(direction: current.recovery.direction, canSavePartial: true)
                                    if self.presentControls { self.startTimer() }
                                    return
                                } else { self.handle(outcome, current: current, attemptedScroll: shouldScroll) }
                                if self.session === current, current.finishRequested, !current.inFlight {
                                    if current.needsFinalFrame { self.sample(current, advance: false) }
                                    else { self.finalize(current) }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func handle(_ outcome: ImageStitcher.FrameResult, current: Session, attemptedScroll: Bool) {
        if current.endDetector.observe(outcome, attemptedAutoScroll: attemptedScroll && current.autoScroll != nil && !current.searchingForOverlap,
                                       now: ProcessInfo.processInfo.systemUptime) {
            let edge = current.autoScroll == .up ? "顶部" : "底部"
            setAutoScroll(nil)
            previewWindow?.setStatus("已到\(edge)。可换个方向继续捕获，或点击完成。")
            return
        }
        switch outcome {
        case .appended, .backtracked, .unchanged:
            let recovered = current.recovery.hasGap
            if recovered {
                current.recovery.reset()
                current.searchingForOverlap = false
                current.partialSaveOffered = false
                lastError = nil
                previewWindow?.setAutoScrollState(direction: current.autoScroll, isAccessibilityGranted: Permissions.hasAccessibilityPermission)
            }
            if recovered {
                previewWindow?.setStatus(current.autoScroll == nil
                    ? "已重新接上。可继续手动滚动，或选择自动捕获方向。"
                    : "已重新接上，继续自动\(current.autoScroll!.title)捕获。")
            } else if case .appended = outcome {
                previewWindow?.setStatus(current.autoScroll.map { "正在\($0.title)捕获；手动滚动可接管。空格暂停。" }
                    ?? "已拼接。可上下滚动，建议每次半屏；Enter 完成。")
            } else if case .backtracked = outcome {
                previewWindow?.setStatus("正在回看已捕获内容；越过两端后会继续拼接。")
            }
        case .unmatched:
            let persistent = current.recovery.observeMiss(now: ProcessInfo.processInfo.systemUptime,
                                                         travelDirection: current.lastTravelDirection)
            if current.searchingForOverlap {
                if current.recoverySearchSteps >= 10 {
                    current.searchingForOverlap = false
                    previewWindow?.showRecovering(direction: current.recovery.direction, canSavePartial: current.partialSaveOffered)
                    previewWindow?.setStatus("还未接上，请\(current.recovery.direction.title)小滚半屏，对照左图找回内容。", isWarning: true)
                }
            } else if persistent {
                current.autoScroll = nil
                previewWindow?.showRecovering(direction: current.recovery.direction, canSavePartial: current.partialSaveOffered)
            } else {
                // 暂停发出下一次自动滚动，继续采样等待动画稳定，成功后自动接着走。
                previewWindow?.setStatus("正在对齐画面，先停一下即可…")
            }
        case .incompatibleFrame:
            fail(current, message: "选区像素尺寸发生变化，请重新选择区域。")
        case .limitReached:
            current.autoScroll = nil
            current.searchingForOverlap = false
            current.captureUnavailable = true
            current.finishRequested = false
            current.needsFinalFrame = false
            timer?.invalidate()
            timer = nil
            previewWindow?.showInterrupted("已达安全长度上限，可保存已捕获内容。")
        }
    }

    func setAutoScroll(_ direction: ScrollCaptureDirection?) {
        guard let current = session, current.phase == .capturing, !current.finishRequested, !current.captureUnavailable else { return }
        if direction != nil && !Permissions.hasAccessibilityPermission {
            previewWindow?.setStatus("自动捕获需要辅助功能权限；仍可在选区内手动滚动，建议每次半屏。", isWarning: true)
            return
        }
        if direction != nil && current.recovery.hasGap {
            previewWindow?.showRecovering(direction: current.recovery.direction, canSavePartial: current.partialSaveOffered)
            return
        }
        current.autoScroll = direction
        if let direction { current.lastAutoDirection = direction }
        current.searchingForOverlap = false
        current.endDetector.reset()
        previewWindow?.setAutoScrollState(direction: direction, isAccessibilityGranted: Permissions.hasAccessibilityPermission)
    }

    func recoverOverlap() {
        guard let current = session, current.phase == .capturing, !current.finishRequested,
              !current.captureUnavailable, current.recovery.hasGap else { return }
        guard Permissions.hasAccessibilityPermission else {
            previewWindow?.showRecovering(direction: current.recovery.direction, canSavePartial: current.partialSaveOffered)
            return
        }
        current.autoScroll = nil
        current.searchingForOverlap = true
        current.recoverySearchSteps = 0
        current.endDetector.reset()
        previewWindow?.showRecovering(direction: current.recovery.direction, isSearching: true, canSavePartial: current.partialSaveOffered)
    }

    private func postScroll(in rect: CGRect, direction: ScrollCaptureDirection, recovering: Bool) {
        let distance = Int32(recovering ? max(12, min(60, rect.height * 0.1)) : min(110, max(18, rect.height * 0.16)))
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                                  wheel1: direction == .down ? -distance : distance, wheel2: 0, wheel3: 0) else { return }
        event.location = DisplayHelper.cocoaToQuartz(rect: CGRect(x: rect.midX, y: rect.midY, width: 0, height: 0)).origin
        event.setIntegerValueField(.eventSourceUserData, value: Self.scrollEventTag)
        event.post(tap: .cghidEventTap)
    }

    public func finish() {
        guard Thread.isMainThread else { DispatchQueue.main.async { self.finish() }; return }
        guard let current = session, current.phase == .capturing, !current.finishRequested else { return }
        current.finishRequested = true
        current.needsFinalFrame = !current.captureUnavailable && !current.partialSaveOffered
        current.autoScroll = nil
        current.searchingForOverlap = false
        timer?.invalidate()
        timer = nil
        previewWindow?.showFinishing()
        if current.captureUnavailable || current.partialSaveOffered { finalize(current) }
        else if !current.inFlight { sample(current, advance: false) }
    }

    private func finalize(_ current: Session) {
        guard session === current, current.phase != .finishing else { return }
        current.phase = .finishing
        previewWindow?.showFinishing()
        processingQueue.async {
            let image = autoreleasepool { current.stitcher.finish() }
            current.stitcher.reset()
            DispatchQueue.main.async {
                guard self.session === current else { return }
                let completion = current.completion
                current.completion = nil
                self.teardown()
                completion?(image)
            }
        }
    }

    public func cancel() {
        guard Thread.isMainThread else { DispatchQueue.main.async { self.cancel() }; return }
        guard let current = session else { closePanels(); return }
        let completion = current.completion
        current.completion = nil
        teardown()
        processingQueue.async { current.stitcher.reset() }
        completion?(nil)
    }

    private func fail(_ current: Session, message: String) {
        guard session === current else { return }
        lastError = message
        let handler = current.onError
        cancel()
        handler?(message)
    }

    private func closePanels() {
        boxWindow?.orderOut(nil)
        boxWindow?.close()
        boxWindow = nil
        previewWindow?.orderOut(nil)
        previewWindow?.close()
        previewWindow = nil
    }

    private func teardown() {
        session = nil
        timer?.invalidate()
        timer = nil
        for monitor in [localKeyMonitor, globalKeyMonitor, localScrollMonitor, globalScrollMonitor].compactMap({ $0 }) { NSEvent.removeMonitor(monitor) }
        localKeyMonitor = nil
        globalKeyMonitor = nil
        localScrollMonitor = nil
        globalScrollMonitor = nil
        if let source = keyTapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap = keyTap { CFMachPortInvalidate(tap) }
        keyTapSource = nil
        keyTap = nil
        closePanels()
    }

    private func receiveScroll(_ event: NSEvent) {
        guard let current = session, !current.finishRequested, isTargetActive(current),
              current.rect.contains(NSEvent.mouseLocation),
              event.cgEvent?.getIntegerValueField(.eventSourceUserData) != Self.scrollEventTag else { return }
        current.lastManualScroll = ProcessInfo.processInfo.systemUptime
        if abs(event.scrollingDeltaY) > 0.01 { current.lastTravelDirection = event.scrollingDeltaY < 0 ? .down : .up }
        if current.autoScroll != nil || current.searchingForOverlap {
            setAutoScroll(nil)
            if current.recovery.hasGap {
                previewWindow?.showRecovering(direction: current.recovery.direction, canSavePartial: current.partialSaveOffered)
            }
        }
        // 滚动事件后尽早取帧；并发门禁仍确保同一时刻只处理一帧。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.025) { [weak self, weak current] in
            guard let self, let current, self.session === current else { return }
            self.tick()
        }
    }

    private func receiveKey(_ code: UInt16) {
        switch code {
        case 36, 76: finish()
        case 53: cancel()
        case 49: if let current = session { setAutoScroll(current.autoScroll == nil ? current.lastAutoDirection : nil) }
        default: break
        }
    }

    private func installMonitors() {
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let current = self.session, self.isTargetActive(current),
                  event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
                  [36, 76, 53, 49].contains(Int(event.keyCode)) else { return event }
            if !event.isARepeat { self.receiveKey(event.keyCode) }
            return nil
        }
        localScrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in self?.receiveScroll(event); return event }
        globalScrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in self?.receiveScroll(event) }
        // 事件 tap 可吞掉控制键，避免“空格开自动”同时让网页翻页。无辅助功能时保留面板操作。
        if Permissions.hasAccessibilityPermission {
            let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
            keyTap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                      eventsOfInterest: mask, callback: { proxy, type, event, info in
                guard let info else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<ScrollCaptureManager>.fromOpaque(info).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = manager.keyTap { CGEvent.tapEnable(tap: tap, enable: true) }
                    return Unmanaged.passUnretained(event)
                }
                let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
                guard let current = manager.session, manager.isTargetActive(current),
                      event.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty,
                      [36, 76, 53, 49].contains(Int(code)) else { return Unmanaged.passUnretained(event) }
                if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                    DispatchQueue.main.async { if manager.session === current { manager.receiveKey(code) } }
                }
                return nil
            }, userInfo: Unmanaged.passUnretained(self).toOpaque())
            if let tap = keyTap {
                keyTapSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
                if let source = keyTapSource { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        }
        if keyTap == nil {
            globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard event.keyCode == 53, let self, let current = self.session, self.isTargetActive(current) else { return }
                self.cancel()
            }
        }
    }
}
