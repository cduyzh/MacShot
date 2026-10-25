import AppKit

/// 仅生成测试像素，不读取屏幕、剪贴板或用户缓存。
enum ScrollCaptureTests {
    static func run() -> Bool {
        let tests: [(String, () -> Bool)] = [
            ("逐像素拼接与上下回看", testRetracing),
            ("从中间开始双向扩展且不重复", testBidirectional),
            ("向上捕获的固定栏与安全长度", testUpwardEdgesAndLimit),
            ("瞬时失配缓冲与恢复方向", testRecoveryPolicy),
            ("固定页头页尾只保留一次", testFixedEdges),
            ("大步滚动与失配恢复", testRecovery),
            ("静止、重复纹理与尺寸变化", testRejectedFrames),
            ("容量限制不产生损坏图片", testLimit),
            ("不同像素格式归一化", testPixelFormats),
            ("Retina视口双向像素与处理耗时", testRetinaViewport),
            ("会话失配与完成失配后继续恢复", testSessionRecovery),
            ("会话取消、防重入与最后一帧", testSessionLifecycle),
            ("完成期间补读最终帧与失配确认", testFinalFrame),
            ("完成期间焦点离开与恢复", testFinishTargetPause),
            ("首帧期间焦点离开与恢复", testPreparingTargetPause),
            ("触底需要持续有效自动滚动证据", testEndDetection)
        ]
        var passed = true
        for (name, test) in tests {
            let result = test()
            print("\(result ? "✓" : "✗") \(name)")
            passed = passed && result
        }
        return passed
    }

    private static let width = 128
    private static let viewport = 240

    private static func pixels(width: Int = width, height: Int, origin: Int = 0) -> [UInt8] {
        var values = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let row = UInt32(y + origin + 1)
                let column = UInt32(x / 3 + 7)
                var hash = row &* 2654435761 ^ column &* 2246822519
                hash = (hash ^ (hash >> 13)) &* 3266489917
                let offset = (y * width + x) * 4
                values[offset] = UInt8(truncatingIfNeeded: hash)
                values[offset + 1] = UInt8(truncatingIfNeeded: hash >> 8)
                values[offset + 2] = UInt8(truncatingIfNeeded: hash >> 16)
            }
        }
        return values
    }

    private static func image(_ bytes: [UInt8], width: Int = width, height: Int) -> CGImage {
        CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil,
                shouldInterpolate: false, intent: .defaultIntent)!
    }

    private static func frame(offset: Int, header: Int = 0, footer: Int = 0) -> CGImage {
        let body = pixels(height: viewport - header - footer, origin: offset)
        let head = pixels(height: header, origin: 7000)
        let foot = pixels(height: footer, origin: 9000)
        return image(head + body + foot, height: viewport)
    }

    private static func matches(_ result: CGImage?, width: Int = width, expected: [UInt8], height: Int) -> Bool {
        guard let result, result.width == width, result.height == height,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue),
              let pointer = context.data?.assumingMemoryBound(to: UInt8.self) else { return false }
        context.draw(result, in: CGRect(x: 0, y: 0, width: width, height: height))
        for index in expected.indices where pointer[index] != expected[index] {
            print("像素不一致：byte \(index)，实际 \(pointer[index])，预期 \(expected[index])")
            return false
        }
        return true
    }

    private static func testRetracing() -> Bool {
        let stitcher = ImageStitcher()
        stitcher.start(with: frame(offset: 0))
        for (offset, appended) in [(70, 70), (35, 0), (60, 0), (120, 50)] {
            let actual = stitcher.process(newFrame: frame(offset: offset))
            guard actual == appended else { print("offset \(offset): expected \(appended), got \(actual), \(stitcher.lastResult)"); return false }
        }
        return matches(stitcher.finish(), expected: pixels(height: viewport + 120), height: viewport + 120)
    }

    private static func testBidirectional() -> Bool {
        let stitcher = ImageStitcher()
        stitcher.start(with: frame(offset: 400))
        for (offset, added) in [(330, 70), (270, 60), (310, 0), (420, 20), (490, 70),
                                (400, 0), (270, 0), (200, 70), (140, 60)] {
            guard stitcher.process(newFrame: frame(offset: offset)) == added else {
                print("双向 offset \(offset): \(stitcher.lastResult)"); return false
            }
        }
        guard stitcher.earliestOffset == -260, stitcher.furthestOffset == 90,
              stitcher.totalStitchedHeight == viewport + 350 else { return false }
        return matches(stitcher.finish(), expected: pixels(height: viewport + 350, origin: 140), height: viewport + 350)
    }

    private static func testUpwardEdgesAndLimit() -> Bool {
        let stitcher = ImageStitcher()
        stitcher.start(with: frame(offset: 400, header: 24, footer: 20))
        for (offset, added) in [(330, 70), (260, 70), (330, 0), (460, 60), (520, 60)] {
            guard stitcher.process(newFrame: frame(offset: offset, header: 24, footer: 20)) == added else {
                print("向上固定栏：\(stitcher.lastResult)"); return false
            }
        }
        let expected = pixels(height: 24, origin: 7000) + pixels(height: viewport - 44 + 260, origin: 260) + pixels(height: 20, origin: 9000)
        guard stitcher.fixedTopHeight == 24, stitcher.fixedBottomHeight == 20,
              matches(stitcher.finish(), expected: expected, height: viewport + 260) else { return false }
        stitcher.maximumHeight = viewport + 30
        stitcher.start(with: frame(offset: 400))
        guard stitcher.process(newFrame: frame(offset: 370)) == 30,
              stitcher.process(newFrame: frame(offset: 330)) == 0,
              stitcher.lastResult == .limitReached else { return false }
        return matches(stitcher.finish(), expected: pixels(height: viewport + 30, origin: 370), height: viewport + 30)
    }

    private static func testRecoveryPolicy() -> Bool {
        var recovery = ScrollCaptureRecoveryState()
        guard !recovery.observeMiss(now: 10, travelDirection: .down), recovery.direction == .up,
              !recovery.observeMiss(now: 10.1, travelDirection: .up), recovery.direction == .up,
              !recovery.observeMiss(now: 10.3, travelDirection: .down),
              recovery.observeMiss(now: 10.6, travelDirection: .down) else { return false }
        recovery.reset()
        guard !recovery.hasGap, !recovery.observeMiss(now: 11, travelDirection: .up),
              recovery.direction == .down else { return false }
        // 动画的一帧失配不能污染已确认的基准帧或插入错误像素。
        let stitcher = ImageStitcher()
        stitcher.start(with: frame(offset: 400))
        guard stitcher.process(newFrame: frame(offset: 900)) == 0, stitcher.lastResult == .unmatched,
              stitcher.process(newFrame: frame(offset: 350)) == 50 else { return false }
        return matches(stitcher.finish(), expected: pixels(height: viewport + 50, origin: 350), height: viewport + 50)
    }

    private static func testFixedEdges() -> Bool {
        let stitcher = ImageStitcher()
        stitcher.start(with: frame(offset: 0, header: 24, footer: 20))
        for (offset, appended) in [(60, 60), (120, 60), (90, 0), (180, 60)] {
            guard stitcher.process(newFrame: frame(offset: offset, header: 24, footer: 20)) == appended else {
                print("固定栏匹配失败：\(stitcher.lastResult)"); return false
            }
        }
        guard stitcher.fixedTopHeight == 24, stitcher.fixedBottomHeight == 20 else {
            print("固定栏高度错误：\(stitcher.fixedTopHeight)/\(stitcher.fixedBottomHeight)"); return false
        }
        let expected = pixels(height: 24, origin: 7000) + pixels(height: viewport - 44 + 180) + pixels(height: 20, origin: 9000)
        return matches(stitcher.finish(), expected: expected, height: viewport + 180)
    }

    private static func testRecovery() -> Bool {
        let stitcher = ImageStitcher()
        stitcher.start(with: frame(offset: 0))
        guard stitcher.process(newFrame: frame(offset: 165)) == 165 else {
            print("大步匹配：\(stitcher.lastResult)"); return false
        }
        guard stitcher.process(newFrame: frame(offset: 600)) == 0, stitcher.lastResult == .unmatched,
              !stitcher.hasReachedEnd else { return false }
        guard stitcher.process(newFrame: frame(offset: 210)) == 45 else { return false }
        return matches(stitcher.finish(), expected: pixels(height: viewport + 210), height: viewport + 210)
    }

    private static func testRejectedFrames() -> Bool {
        let stitcher = ImageStitcher()
        stitcher.start(with: frame(offset: 0))
        for _ in 0..<4 { guard stitcher.process(newFrame: frame(offset: 0)) == 0 else { return false } }
        guard stitcher.hasReachedEnd else { return false }
        let wrongSize = image(pixels(width: 64, height: viewport), width: 64, height: viewport)
        guard stitcher.process(newFrame: wrongSize) == 0, stitcher.lastResult == .incompatibleFrame,
              !stitcher.hasReachedEnd else { return false }
        let repeated = ImageStitcher()
        func stripes(_ shift: Int) -> CGImage {
            var data = [UInt8](repeating: 255, count: width * viewport * 4)
            for y in 0..<viewport {
                for x in 0..<width {
                    let value: UInt8 = ((y + shift) % 32) < 16 ? 20 : 240
                    for channel in 0..<3 { data[(y * width + x) * 4 + channel] = value }
                }
            }
            return image(data, height: viewport)
        }
        repeated.start(with: stripes(0))
        let added = repeated.process(newFrame: stripes(7))
        guard added == 0, repeated.lastResult == .unmatched else {
            print("重复条纹不能猜位移：\(added), \(repeated.lastResult)")
            return false
        }
        return true
    }

    private static func testLimit() -> Bool {
        let stitcher = ImageStitcher()
        stitcher.maximumHeight = viewport + 50
        stitcher.start(with: frame(offset: 0))
        guard stitcher.process(newFrame: frame(offset: 30)) == 30,
              stitcher.process(newFrame: frame(offset: 70)) == 0,
              stitcher.lastResult == .limitReached else { return false }
        return matches(stitcher.finish(), expected: pixels(height: viewport + 30), height: viewport + 30)
    }

    private static func testPixelFormats() -> Bool {
        let stitcher = ImageStitcher()
        let source = pixels(height: viewport + 80)
        func rgbFrame(_ offset: Int) -> CGImage {
            var rgb: [UInt8] = []
            for pixel in 0..<(width * viewport) {
                let index = (pixel + offset * width) * 4
                rgb.append(contentsOf: source[index..<(index + 3)])
            }
            return CGImage(width: width, height: viewport, bitsPerComponent: 8, bitsPerPixel: 24,
                           bytesPerRow: width * 3, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: [],
                           provider: CGDataProvider(data: Data(rgb) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        }
        stitcher.start(with: rgbFrame(0))
        guard stitcher.process(newFrame: rgbFrame(80)) == 80 else { return false }
        return matches(stitcher.finish(), expected: source, height: viewport + 80)
    }
    private static func testRetinaViewport() -> Bool {
        let largeWidth = 1200
        let largeHeight = 840
        func largeFrame(_ offset: Int) -> CGImage {
            image(pixels(width: largeWidth, height: largeHeight, origin: offset), width: largeWidth, height: largeHeight)
        }
        let stitcher = ImageStitcher()
        stitcher.start(with: largeFrame(400))
        var processingTime: TimeInterval = 0
        for (offset, added) in [(300, 100), (500, 100), (450, 0), (650, 150)] {
            let next = largeFrame(offset)
            let started = ProcessInfo.processInfo.systemUptime
            let actual = stitcher.process(newFrame: next)
            processingTime += ProcessInfo.processInfo.systemUptime - started
            guard actual == added else { print("Retina视口：\(stitcher.lastResult)"); return false }
        }
        print(String(format: "  1200 × 840 px 匹配均值 %.1f ms", processingTime / 4 * 1000))
        return matches(stitcher.finish(), width: largeWidth, expected: pixels(width: largeWidth, height: largeHeight + 350, origin: 300), height: largeHeight + 350)
    }

    private final class FakeSource: ScrollCaptureFrameProviding {
        var image = frame(offset: 0)
        var hold = false
        var pending: ((Result<CGImage, Error>) -> Void)?
        var count = 0
        func capture(completion: @escaping (Result<CGImage, Error>) -> Void) {
            count += 1
            if hold { pending = completion } else { completion(.success(image)) }
        }
    }

    private static func wait(_ predicate: () -> Bool, timeout: TimeInterval = 2) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !predicate(), Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.005))
        }
        return predicate()
    }

    private static func testSessionRecovery() -> Bool {
        guard let screen = NSScreen.screens.first else { return false }
        let rect = CGRect(x: screen.frame.minX + 30, y: screen.frame.minY + 30,
                          width: CGFloat(width), height: CGFloat(viewport))
        let source = FakeSource()
        source.image = frame(offset: 400)
        let manager = ScrollCaptureManager(presentControls: false, makeSource: { _, _, _, _, completion in
            completion(.success(source))
        })
        defer { manager.cancel() }
        var output: CGImage?
        var deliveries = 0
        manager.start(in: rect) { output = $0; deliveries += 1 }
        guard wait({ manager.capturedPixelHeight == viewport }) else { return false }
        source.image = frame(offset: 470)
        manager.tick()
        guard wait({ manager.capturedPixelHeight == viewport + 70 }) else { return false }
        source.image = frame(offset: 1000)
        for _ in 0..<3 {
            manager.tick()
            guard wait({ !manager.isProcessingFrame }), manager.isWaitingForOverlap,
                  manager.capturedPixelHeight == viewport + 70, deliveries == 0 else { return false }
        }
        source.image = frame(offset: 520)
        manager.tick()
        guard wait({ manager.capturedPixelHeight == viewport + 120 }), !manager.isWaitingForOverlap else {
            print("失配期间保持基准帧，找回重叠后必须可继续累加"); return false
        }
        source.image = frame(offset: 1000)
        manager.finish()
        guard wait({ manager.lastError != nil }), manager.isRunning, manager.isWaitingForOverlap, deliveries == 0 else { return false }
        source.image = frame(offset: 570)
        manager.tick()
        guard wait({ manager.capturedPixelHeight == viewport + 170 }), !manager.isWaitingForOverlap, manager.lastError == nil else {
            print("完成时失配不能永久终止采集；找回后必须恢复完成操作"); return false
        }
        manager.finish()
        return wait({ deliveries == 1 }) && !manager.isRunning &&
            matches(output, expected: pixels(height: viewport + 170, origin: 400), height: viewport + 170)
    }

    private static func testSessionLifecycle() -> Bool {
        guard let screen = NSScreen.screens.first else { print("测试需要可用显示器，但不会读取屏幕"); return false }
        let rect = CGRect(x: screen.frame.minX + 30, y: screen.frame.minY + 30, width: CGFloat(width), height: CGFloat(viewport))
        var factories: [(Result<ScrollCaptureFrameProviding, Error>) -> Void] = []
        let manager = ScrollCaptureManager(presentControls: false, makeSource: { _, _, _, _, completion in factories.append(completion) })
        defer { manager.cancel() }
        var cancelled = 0
        manager.start(in: .zero) { image in if image == nil { cancelled += 1 } }
        guard cancelled == 1, !manager.isRunning, factories.isEmpty else { return false }
        manager.start(in: rect) { image in if image == nil { cancelled += 1 } }
        let oldFactory = factories.removeFirst()
        manager.cancel()
        manager.start(in: rect) { image in if image == nil { cancelled += 1 } }
        let source = FakeSource()
        oldFactory(.success(source))
        guard source.count == 0, manager.isRunning else { print("过期准备回调不应污染新会话"); return false }
        factories.removeFirst()(.success(source))
        guard wait({ manager.capturedPixelHeight == viewport }) else { return false }
        manager.cancel()
        guard cancelled == 3 else { print("取消回调应恰好一次"); return false }
        var output: CGImage?
        var finished = 0
        manager.start(in: rect) { image in output = image; finished += 1 }
        factories.removeFirst()(.success(source))
        guard wait({ manager.capturedPixelHeight == viewport }) else { return false }
        source.image = frame(offset: 70)
        manager.finish()
        manager.finish()
        guard wait({ finished == 1 }), !manager.isRunning,
              matches(output, expected: pixels(height: viewport + 70), height: viewport + 70) else {
            print("完成必须等待最后一帧，且只交付一次"); return false
        }
        var abandoned = 0
        source.image = frame(offset: 0)
        manager.start(in: rect) { _ in abandoned += 1 }
        factories.removeFirst()(.success(source))
        guard wait({ manager.capturedPixelHeight == viewport }) else { return false }
        source.hold = true
        manager.finish()
        guard wait({ source.pending != nil }) else { return false }
        manager.cancel()
        source.pending?(.success(frame(offset: 60)))
        source.pending = nil
        guard abandoned == 1, !manager.isRunning else { return false }
        var partial: CGImage?
        var partialDeliveries = 0
        source.hold = false
        manager.start(in: rect) { image in partial = image; partialDeliveries += 1 }
        factories.removeFirst()(.success(source))
        guard wait({ manager.capturedPixelHeight == viewport }) else { return false }
        source.hold = true
        manager.finish()
        guard wait({ source.pending != nil }) else { return false }
        source.pending?(.failure(CocoaError(.fileReadNoPermission)))
        source.pending = nil
        guard manager.isRunning, partialDeliveries == 0, manager.lastError != nil else {
            print("最后一帧失败不能静默交付不完整结果"); return false
        }
        manager.finish() // 明确再次确认，保存已经捕获的部分。
        guard wait({ partialDeliveries == 1 }), partial?.height == viewport, !manager.isRunning else { return false }
        var errors = 0
        manager.start(in: rect, onError: { _ in errors += 1 }) { _ in abandoned += 1 }
        factories.removeFirst()(.failure(CocoaError(.fileReadNoPermission)))
        return errors == 1 && abandoned == 2 && !manager.isRunning && manager.lastError != nil
    }

    private static func testFinalFrame() -> Bool {
        guard let screen = NSScreen.screens.first else { return false }
        let rect = CGRect(x: screen.frame.minX + 30, y: screen.frame.minY + 30,
                          width: CGFloat(width), height: CGFloat(viewport))
        let source = FakeSource()
        let manager = ScrollCaptureManager(presentControls: false, makeSource: { _, _, _, _, completion in
            completion(.success(source))
        })
        defer { manager.cancel() }
        var output: CGImage?
        var deliveries = 0
        manager.start(in: rect) { output = $0; deliveries += 1 }
        guard wait({ manager.capturedPixelHeight == viewport }) else { return false }
        source.hold = true
        manager.tick()
        guard wait({ source.pending != nil }), let ordinaryFrame = source.pending else { return false }
        source.pending = nil
        manager.finish()
        source.image = frame(offset: 140)
        source.hold = false
        ordinaryFrame(.success(frame(offset: 70)))
        guard wait({ deliveries == 1 }), source.count == 3,
              matches(output, expected: pixels(height: viewport + 140), height: viewport + 140) else {
            print("完成前已在处理的帧结束后，必须补读请求之后的最终画面"); return false
        }

        output = nil
        deliveries = 0
        source.image = frame(offset: 0)
        manager.start(in: rect) { output = $0; deliveries += 1 }
        guard wait({ manager.capturedPixelHeight == viewport }) else { return false }
        source.image = frame(offset: 600)
        manager.finish()
        guard wait({ manager.lastError != nil }), manager.isRunning, deliveries == 0 else {
            print("最终帧配准失败必须等待用户明确保存当前，不能静默交付"); return false
        }
        manager.finish()
        return wait({ deliveries == 1 }) && !manager.isRunning &&
            matches(output, expected: pixels(height: viewport), height: viewport)
    }

    private static func testPreparingTargetPause() -> Bool {
        guard let screen = NSScreen.screens.first else { return false }
        let rect = CGRect(x: screen.frame.minX + 30, y: screen.frame.minY + 30,
                          width: CGFloat(width), height: CGFloat(viewport))
        var targetActive = true
        let source = FakeSource()
        source.hold = true
        let manager = ScrollCaptureManager(presentControls: false, targetActivity: { _ in targetActive }) {
            _, _, _, _, completion in completion(.success(source))
        }
        defer { manager.cancel() }
        manager.start(in: rect) { _ in }
        guard wait({ source.pending != nil }), let firstFrame = source.pending else { return false }
        source.pending = nil
        targetActive = false
        firstFrame(.success(frame(offset: 0)))
        guard manager.isRunning, manager.capturedPixelHeight == 0 else { return false }
        targetActive = true
        source.hold = false
        manager.tick()
        guard wait({ manager.capturedPixelHeight == viewport }) else {
            print("首帧暂时离焦后应能继续初始化捕获")
            return false
        }
        return true
    }

    private static func testFinishTargetPause() -> Bool {
        guard let screen = NSScreen.screens.first else { return false }
        let rect = CGRect(x: screen.frame.minX + 30, y: screen.frame.minY + 30,
                          width: CGFloat(width), height: CGFloat(viewport))
        var targetActive = true
        let source = FakeSource()
        let manager = ScrollCaptureManager(presentControls: false, targetActivity: { _ in targetActive }) {
            _, _, _, _, completion in completion(.success(source))
        }
        defer { manager.cancel() }
        var output: CGImage?
        var deliveries = 0
        manager.start(in: rect) { output = $0; deliveries += 1 }
        guard wait({ manager.capturedPixelHeight == viewport }) else { return false }
        source.hold = true
        manager.finish()
        guard wait({ source.pending != nil }), let finalFrame = source.pending else { return false }
        source.pending = nil
        targetActive = false
        finalFrame(.success(frame(offset: 60)))
        guard manager.isRunning, deliveries == 0 else {
            print("完成期间切换应用必须保留会话"); return false
        }
        targetActive = true
        source.hold = false
        source.image = frame(offset: 60)
        manager.tick()
        guard wait({ manager.capturedPixelHeight == viewport + 60 }) else {
            print("返回目标应用后必须能够继续采样"); return false
        }
        manager.finish()
        return wait({ deliveries == 1 }) && !manager.isRunning &&
            matches(output, expected: pixels(height: viewport + 60), height: viewport + 60)
    }

    private static func testEndDetection() -> Bool {
        var detector = ScrollCaptureEndDetector()
        for index in 0..<20 {
            guard !detector.observe(.unmatched, attemptedAutoScroll: true, now: Double(index)),
                  !detector.observe(.unchanged, attemptedAutoScroll: false, now: Double(index)) else { return false }
        }
        for index in 0..<5 {
            guard !detector.observe(.unchanged, attemptedAutoScroll: true, now: Double(index) * 0.25) else { return false }
        }
        guard detector.observe(.unchanged, attemptedAutoScroll: true, now: 1.25) else { return false }
        guard !detector.observe(.backtracked(-20), attemptedAutoScroll: true, now: 2),
              !detector.observe(.unchanged, attemptedAutoScroll: true, now: 3) else { return false }
        return true
    }

}
