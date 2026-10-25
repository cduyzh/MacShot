import AppKit
import Carbon

let args = CommandLine.arguments

if args.contains("--version") {
    print("cduyzhShot \(AppVersion.current.displayString)")
    if let date = AppVersion.current.buildDateDisplayString { print("构建时间：\(date)") }
    exit(0)
}

if args.contains("--test") || args.contains("--test-all") {
    let success = TestRunner.runAllTests()
    exit(success ? 0 : 1)
}

if args.contains("--test-hotkeys") {
    print("Testing KeyCombo...")
    let comboA = KeyCombo(keyCode: 0, modifiers: UInt32(NSEvent.ModifierFlags.control.rawValue), characters: "a")
    assert(comboA.displayString == "⌃A", "Display string mismatch: \(comboA.displayString)")
    assert(comboA.carbonModifiers == UInt32(controlKey), "Carbon modifiers mismatch")

    let comboBracket = KeyCombo(keyCode: 33, modifiers: UInt32(NSEvent.ModifierFlags.control.rawValue), characters: "[")
    assert(comboBracket.displayString == "⌃[", "Display string mismatch: \(comboBracket.displayString)")

    let comboScroll = KeyCombo(keyCode: 1, modifiers: UInt32(NSEvent.ModifierFlags.option.rawValue), characters: "s")
    assert(comboScroll.displayString == "⌥S", "Display string mismatch: \(comboScroll.displayString)")
    print("✓ KeyCombo test PASSED!")
    exit(0)
}

if args.contains("--test-scroll") {
    exit(ScrollCaptureTests.run() ? 0 : 1)
}

if args.contains("--test-stitcher") {
    print("Testing ImageStitcher...")
    let width = 400
    let height = 300
    let scrollDy = 45

    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx1 = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let ctx2 = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

    let ptr1 = ctx1.data!.assumingMemoryBound(to: UInt8.self)
    let ptr2 = ctx2.data!.assumingMemoryBound(to: UInt8.self)

    // Visual row r: 0 is top, height-1 is bottom
    for r in 0..<height {
        for c in 0..<width {
            let offset = (r * width + c) * 4
            let val = UInt8((r * 255) / (height + scrollDy))
            ptr1[offset] = val
            ptr1[offset + 1] = 128
            ptr1[offset + 2] = 200
            ptr1[offset + 3] = 255
        }
    }

    for r in 0..<height {
        for c in 0..<width {
            let offset = (r * width + c) * 4
            let val = UInt8(((r + scrollDy) * 255) / (height + scrollDy))
            ptr2[offset] = val
            ptr2[offset + 1] = 128
            ptr2[offset + 2] = 200
            ptr2[offset + 3] = 255
        }
    }

    let frame1 = ctx1.makeImage()!
    let frame2 = ctx2.makeImage()!

    let stitcher = ImageStitcher()
    stitcher.start(with: frame1)
    assert(stitcher.totalStitchedHeight == height, "Initial height should match frame1")

    let detectedDy = stitcher.process(newFrame: frame2)
    print("Stitcher detected dy: \(detectedDy) (expected around \(scrollDy))")
    assert(abs(detectedDy - scrollDy) <= 2, "Stitcher offset detection failed! Expected \(scrollDy), got \(detectedDy)")

    let stitchedResult = stitcher.finish()
    assert(stitchedResult != nil, "Stitched result must not be nil")
    assert(stitcher.totalStitchedHeight == height + detectedDy, "Total height mismatch")
    print("✓ ImageStitcher test PASSED! Stitched height: \(stitcher.totalStitchedHeight)px")
    exit(0)
}

if args.contains("--test-writer") {
    print("Testing RecordingOutputWriter...")
    let testURL = URL(fileURLWithPath: "/tmp/cduyzhShot_test_writer.mp4")
    let writer = RecordingOutputWriter(outputURL: testURL)
    do {
        try writer.setup(width: 640, height: 480, capturesAudio: true, fps: 30)
        print("✓ RecordingOutputWriter setup with H.264 video and AAC system audio succeeded!")
    } catch {
        print("Writer test error: \(error)")
        exit(1)
    }
    exit(0)
}

if args.contains("--test-capture") {
    print("Testing ScreenCaptureEngine...")
    if NSScreen.main != nil {
        let rect = CGRect(x: 100, y: 100, width: 200, height: 200)
        if let img = ScreenCaptureEngine.shared.capture(rect: rect) {
            print("✓ ScreenCaptureEngine successfully captured \(img.width)x\(img.height) pixels")
        } else {
            print("Note: Screen capture returned nil (permission prompt might be required if headless)")
        }
    }
    exit(0)
}

if args.contains("--render-toolbar-preview") {
    let toolbar = ScreenshotToolbarView()
    let neededWidth = max(toolbar.fittingSize.width + 16, 570)
    toolbar.frame = NSRect(x: 0, y: 0, width: neededWidth, height: 38)

    let window = NSWindow(contentRect: toolbar.bounds, styleMask: .borderless, backing: .buffered, defer: false)
    window.contentView = toolbar
    window.isOpaque = false
    window.backgroundColor = .clear
    toolbar.layoutSubtreeIfNeeded()

    if let rep = toolbar.bitmapImageRepForCachingDisplay(in: toolbar.bounds) {
        toolbar.cacheDisplay(in: toolbar.bounds, to: rep)
        if let pngData = rep.representation(using: .png, properties: [:]) {
            let outPath = "/tmp/macshot_toolbar_preview.png"
            try? pngData.write(to: URL(fileURLWithPath: outPath))
            print("✓ Toolbar rendered to \(outPath) (\(pngData.count) bytes)")
        }
    }
    exit(0)
}

if args.contains("--preview-ui") || Bundle.main.object(forInfoDictionaryKey: "cduyzhUIPreview") as? Bool == true {
    let app = NSApplication.shared
    let previewDelegate = UIPreviewDelegate()
    app.delegate = previewDelegate
    app.run()
    exit(0)
}

if args.contains("--test-ui") {
    _ = NSApplication.shared
    let tests: [(String, () -> Bool)] = [
        ("快捷键", TestRunner.testKeyCombos),
        ("标注与色板", TestRunner.testAnnotationDefaultsAndColorPalettePresets),
        ("工具栏交互", TestRunner.testDarkToolbarAndDynamicRecordButton),
        ("美化渲染", TestRunner.testScreenshotStudioRenderer),
        ("提示气泡", TestRunner.testToolbarTooltipBubbleView),
        ("长截图恢复状态", TestRunner.testScrollCaptureControlRecovery),
        ("美化参数快照", TestRunner.testStudioSnapshot),
        ("录屏状态反馈", TestRunner.testRecordingToolbarFeedback),
        ("剪贴板格式兼容", TestRunner.testPreparedClipboardFormats)
    ]
    var passed = true
    for (name, test) in tests {
        let result = test()
        print("\(result ? "✓" : "✗") \(name)")
        passed = passed && result
    }
    exit(passed ? 0 : 1)
}

// Normal GUI Launch
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
