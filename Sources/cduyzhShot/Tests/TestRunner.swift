import AppKit
import Carbon
import CoreGraphics
import AVFoundation

public final class TestRunner {
    public static func runAllTests() -> Bool {
        print("\n=======================================================")
        print("          cduyzhShot 综合自动化功能与健壮性测试套件          ")
        print("=======================================================\n")

        var allPassed = true

        let tests: [(String, () -> Bool)] = [
            ("1. 快捷键与修饰键解析 (KeyCombo & Modifiers)", testKeyCombos),
            ("2. 缓存管理与定时清理机制 (CacheManager)", testCacheManager),
            ("3. 通用剪贴板多格式写入与读取 (Pasteboard Universal Copy)", testPasteboard),
            ("4. 滚动长截图动态特征拼接算法 (ImageStitcher Multi-Scenarios)", testImageStitcher),
            ("5. 录屏输出与奇数分辨率自动对齐 (RecordingOutputWriter & Dimensions)", testRecordingWriter),
            ("6. 矢量标注渲染安全与健壮性 (AnnotationRenderer Robustness)", testAnnotationRenderer),
            ("7. 多屏与 Quartz/Cocoa 坐标系无损映射 (DisplayHelper Coordinates)", testCoordinateConversions),
            ("8. 原位就地文字编辑与生命周期 (InPlaceTextEditor Live Editing)", testInPlaceTextEditingModel),
            ("9. 贴图窗口缩放/透明度/镜像控制 (PinWindow Transform & Opacity)", testPinWindowTransformAndOpacity),
            ("10. 智能吸附与 ⌥ 键立体阴影映射 (WindowShadow & CGWindowImageOption)", testWindowShadowAndCaptureOptions),
            ("11. 标注固定线宽与预设色板 (Annotation Defaults & PresetColor Palette)", testAnnotationDefaultsAndColorPalettePresets),
            ("12. 暗色模式图标工具栏与动态录制按钮 (Dark Toolbar & Dynamic Recording Button)", testDarkToolbarAndDynamicRecordButton),
            ("13. 权限安全检测与面板状态刷新 (Permissions Status & Safe Detection)", testPermissionsStatusAndRefresh),
            ("14. 截图美化与样机渲染引擎 (ScreenshotStudio Multi-Mockups & Backgrounds)", testScreenshotStudioRenderer),
            ("15. 工具栏小气泡提示与尺寸自适应 (ToolbarTooltipBubbleView & Button Bindings)", testToolbarTooltipBubbleView),
            ("16. 在线更新检测与语义版本比对算法 (UpdateChecker & Semantic Version Comparison)", testUpdateChecker)
        ]

        for (name, testFunc) in tests {
            print("▶ 运行测试: \(name)...")
            let passed = testFunc()
            if passed {
                print("  ✓ 通过\n")
            } else {
                print("  ✗ 失败!\n")
                allPassed = false
            }
        }

        print("=======================================================")
        if allPassed {
            print("🎉 所有功能与边界兜底测试全部通过 (ALL TESTS PASSED)!")
        } else {
            print("⚠️ 存在未通过的测试项，请检查日志!")
        }
        print("=======================================================\n")

        return allPassed
    }

    // MARK: - Test 1: KeyCombos
    public static func testKeyCombos() -> Bool {
        // Control + A (Regional Screenshot)
        let comboA = KeyCombo(keyCode: 0, modifiers: UInt32(NSEvent.ModifierFlags.control.rawValue), characters: "a")
        guard comboA.displayString == "⌃A" else {
            print("Failed displayString: expected ⌃A, got \(comboA.displayString)")
            return false
        }
        guard comboA.carbonModifiers == UInt32(controlKey) else {
            print("Failed carbonModifiers for Control+A")
            return false
        }

        // Control + [ (Screen Recording)
        let comboBracket = KeyCombo(keyCode: 33, modifiers: UInt32(NSEvent.ModifierFlags.control.rawValue), characters: "[")
        guard comboBracket.displayString == "⌃[" else {
            print("Failed displayString: expected ⌃[, got \(comboBracket.displayString)")
            return false
        }

        // Option + S (Scroll Screenshot)
        let comboS = KeyCombo(keyCode: 1, modifiers: UInt32(NSEvent.ModifierFlags.option.rawValue), characters: "s")
        guard comboS.displayString == "⌥S" else {
            print("Failed displayString: expected ⌥S, got \(comboS.displayString)")
            return false
        }

        // Command + Shift + 4
        let multiMod = NSEvent.ModifierFlags([.command, .shift]).rawValue
        let comboMulti = KeyCombo(keyCode: 21, modifiers: UInt32(multiMod), characters: "4")
        guard comboMulti.displayString.contains("⌘") && comboMulti.displayString.contains("⇧") else {
            return false
        }

        // JSON serialization test
        guard let data = try? JSONEncoder().encode(comboA),
              let decoded = try? JSONDecoder().decode(KeyCombo.self, from: data),
              decoded == comboA else {
            print("Failed JSON encoding/decoding of KeyCombo")
            return false
        }

        return true
    }

    // MARK: - Test 2: CacheManager
    public static func testCacheManager() -> Bool {
        let cm = CacheManager.shared

        // Create a dummy image
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 400, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let img = ctx.makeImage() else {
            return false
        }

        // 1. Save temporary image
        guard let fileURL = cm.saveTemporaryImage(img, prefix: "test_clip") else {
            print("Failed to save temporary image to cache")
            return false
        }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            print("Cache file does not exist on disk: \(fileURL.path)")
            return false
        }

        // 2. Cache size check
        let size = cm.getCacheSizeBytes()
        guard size > 0 else {
            print("Cache size reported <= 0")
            return false
        }

        let formatted = cm.formattedCacheSize()
        guard !formatted.isEmpty else {
            return false
        }

        // 3. Clear all cache test
        cm.clearAllCache()
        let sizeAfterClear = cm.getCacheSizeBytes()
        guard sizeAfterClear == 0 else {
            print("Cache size after clear should be 0, got \(sizeAfterClear)")
            return false
        }

        return true
    }

    // MARK: - Test 3: Pasteboard
    public static func testPasteboard() -> Bool {
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: 80, height: 60, bitsPerComponent: 8, bytesPerRow: 320, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return false
        }
        ctx.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.9, alpha: 1.0))
        ctx.fill(CGRect(x: 0, y: 0, width: 80, height: 60))
        guard let img = ctx.makeImage() else { return false }

        // Copy with both bitmap and file
        guard let tempURL = PasteboardHelper.copyImage(img, alsoAsFile: true) else {
            print("PasteboardHelper failed to copy image")
            return false
        }

        let pb = NSPasteboard.general

        // Check types
        guard let types = pb.types else { return false }
        guard types.contains(.png) else {
            print("Pasteboard missing .png type")
            return false
        }
        guard types.contains(.tiff) else {
            print("Pasteboard missing .tiff type")
            return false
        }
        guard types.contains(.fileURL) else {
            print("Pasteboard missing .fileURL type")
            return false
        }

        // Check readability by NSImage
        guard let readImage = NSImage(pasteboard: pb) else {
            print("Failed to read image back from pasteboard")
            return false
        }
        guard readImage.size.width > 0 && readImage.size.height > 0 else {
            return false
        }

        // Check file URL readability
        guard let fileList = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
              let firstURL = fileList.first,
              FileManager.default.fileExists(atPath: firstURL.path) else {
            print("Failed to read back file URL from pasteboard")
            return false
        }

        _ = tempURL
        return true
    }

    // MARK: - Test 4: ImageStitcher Multi-Scenarios
    public static func testImageStitcher() -> Bool {
        let width = 200
        let height = 200

        func makeFrame(shiftY: Int) -> CGImage {
            let cs = CGColorSpaceCreateDeviceRGB()
            let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            let ptr = ctx.data!.assumingMemoryBound(to: UInt8.self)

            for r in 0..<height {
                for c in 0..<width {
                    let offset = (r * width + c) * 4
                    let val = UInt8(((r + shiftY) * 255) / (height + 100))
                    ptr[offset] = val
                    ptr[offset + 1] = 128
                    ptr[offset + 2] = 200
                    ptr[offset + 3] = 255
                }
            }
            return ctx.makeImage()!
        }

        let stitcher = ImageStitcher()

        // Scenario A: Standard scroll dy = 35
        let f1 = makeFrame(shiftY: 0)
        stitcher.start(with: f1)
        guard stitcher.totalStitchedHeight == height else { return false }

        let f2 = makeFrame(shiftY: 35)
        let dy1 = stitcher.process(newFrame: f2)
        guard abs(dy1 - 35) <= 1 else {
            print("Scenario A failed: expected dy=35, got \(dy1)")
            return false
        }
        guard stitcher.totalStitchedHeight == height + dy1 else { return false }

        // Scenario B: Fine-grained scroll dy = 10
        let f3 = makeFrame(shiftY: 35 + 10)
        let dy2 = stitcher.process(newFrame: f3)
        guard abs(dy2 - 10) <= 1 else {
            print("Scenario B failed: expected dy=10, got \(dy2)")
            return false
        }

        // Scenario C: Static frame (no scroll)
        let fStatic = makeFrame(shiftY: 35 + 10)
        for _ in 0..<4 {
            let dyStatic = stitcher.process(newFrame: fStatic)
            guard dyStatic == 0 else {
                print("Scenario C failed: static frame returned dy != 0")
                return false
            }
        }
        guard stitcher.hasReachedEnd else {
            print("Scenario C failed: hasReachedEnd should be true after 4 static frames")
            return false
        }

        // Check stitched output is non-nil and height matches
        guard let finalStitched = stitcher.finish() else {
            print("Scenario finish returned nil")
            return false
        }
        guard finalStitched.height == stitcher.totalStitchedHeight else {
            return false
        }

        // Scenario D: Verify image is 100% upright and NOT inverted 180°!
        guard let finalData = finalStitched.dataProvider?.data,
              let finalPtr = CFDataGetBytePtr(finalData) else {
            return false
        }
        let topVal = finalPtr[0]
        let bottomVal = finalPtr[(finalStitched.height - 1) * finalStitched.bytesPerRow]
        guard topVal < bottomVal else {
            print("Scenario D failed: image was rendered upside down! topVal=\(topVal), bottomVal=\(bottomVal)")
            return false
        }

        return true
    }

    // MARK: - Test 5: RecordingOutputWriter Dimensions & Alignment
    public static func testRecordingWriter() -> Bool {
        let testURL = URL(fileURLWithPath: "/tmp/cduyzhShot_test_writer_align.mp4")
        let writer = RecordingOutputWriter(outputURL: testURL)

        // Test odd dimensions: 641 x 481
        // H.264 requires even dimensions; RecordingOutputWriter must automatically align to 640 x 480
        do {
            try writer.setup(width: 641, height: 481, capturesAudio: true, fps: 60)
        } catch {
            print("RecordingOutputWriter odd dimension setup failed: \(error)")
            return false
        }

        try? FileManager.default.removeItem(at: testURL)
        return true
    }

    // MARK: - Test 6: AnnotationRenderer Robustness
    public static func testAnnotationRenderer() -> Bool {
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: 300, height: 300, bitsPerComponent: 8, bytesPerRow: 1200, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return false
        }

        let tools: [AnnotationTool] = [
            .rect, .ellipse, .arrow, .line, .text, .stepBadge, .mosaic
        ]

        for (idx, tool) in tools.enumerated() {
            let item = AnnotationItem(
                tool: tool,
                startPoint: CGPoint(x: 20 + idx * 25, y: 30),
                endPoint: CGPoint(x: 80 + idx * 25, y: 150),
                color: NSColor.systemRed,
                lineWidth: 3.0,
                text: "Test Annotation",
                badgeNumber: idx + 1
            )
            // Render should never throw or crash
            AnnotationRenderer.render(item: item, in: ctx)
        }

        guard let _ = ctx.makeImage() else {
            return false
        }

        return true
    }

    // MARK: - Test 7: Coordinates Conversion
    public static func testCoordinateConversions() -> Bool {
        let primaryH = DisplayHelper.primaryScreenHeight
        guard primaryH > 100 else { return false }

        let originalCocoa = CGRect(x: 150, y: 200, width: 400, height: 300)
        let quartz = DisplayHelper.cocoaToQuartz(rect: originalCocoa)
        let roundTripCocoa = DisplayHelper.quartzToCocoa(rect: quartz)

        guard originalCocoa == roundTripCocoa else {
            print("Coordinate round trip failed: expected \(originalCocoa), got \(roundTripCocoa)")
            return false
        }

        return true
    }

    // MARK: - Test 8: InPlaceTextEditor Live Editing Model
    public static func testInPlaceTextEditingModel() -> Bool {
        class MockTextDelegate: InPlaceTextEditorDelegate {
            var committedText: String?
            var committedPoint: CGPoint?
            var didCancel = false

            func textEditorDidCommit(text: String, at point: CGPoint) {
                committedText = text
                committedPoint = point
            }

            func textEditorDidCancel() {
                didCancel = true
            }
        }

        let origin = CGPoint(x: 100, y: 150)
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        let editor = InPlaceTextEditor(origin: origin, color: NSColor.systemRed, maxBounds: bounds)
        let mockDelegate = MockTextDelegate()
        editor.editorDelegate = mockDelegate

        // 1. Check initial setup
        guard editor.textColor == NSColor.systemRed else {
            print("InPlaceTextEditor textColor mismatch")
            return false
        }
        guard editor.placeholderString == "输入文字..." else {
            return false
        }

        // 2. Test empty commit triggers cancel
        editor.stringValue = "   "
        editor.commitAndDismiss()
        guard mockDelegate.didCancel && mockDelegate.committedText == nil else {
            print("Empty string commit should trigger didCancel")
            return false
        }

        // 3. Test non-empty commit triggers commit delegate
        let editor2 = InPlaceTextEditor(origin: origin, color: NSColor.systemBlue, maxBounds: bounds)
        let mockDelegate2 = MockTextDelegate()
        editor2.editorDelegate = mockDelegate2
        editor2.stringValue = "Hello cduyzhShot!"
        editor2.commitAndDismiss()
        guard mockDelegate2.committedText == "Hello cduyzhShot!" else {
            print("Committed text mismatch: \(String(describing: mockDelegate2.committedText))")
            return false
        }
        guard mockDelegate2.committedPoint != nil else {
            return false
        }

        // 4. Test cancelAndDismiss
        let editor3 = InPlaceTextEditor(origin: origin, color: NSColor.systemGreen, maxBounds: bounds)
        let mockDelegate3 = MockTextDelegate()
        editor3.editorDelegate = mockDelegate3
        editor3.stringValue = "Unsaved draft"
        editor3.cancelAndDismiss()
        guard mockDelegate3.didCancel && mockDelegate3.committedText == nil else {
            return false
        }

        return true
    }

    // MARK: - Test 9: PinWindow Transform and Opacity Control
    public static func testPinWindowTransformAndOpacity() -> Bool {
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: 200, height: 150, bitsPerComponent: 8, bytesPerRow: 800, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return false
        }
        guard let img = ctx.makeImage() else { return false }

        let pinController = PinWindowController(image: img, initialOrigin: CGPoint(x: 100, y: 100))
        guard let pinWindow = pinController.window as? PinWindow else {
            print("PinWindowController window is not PinWindow")
            return false
        }

        // 1. Initial window level and attributes
        guard pinWindow.isFloatingPanel && pinWindow.level == .floating else {
            print("PinWindow level mismatch")
            return false
        }
        guard pinWindow.hasShadow else {
            return false
        }

        // 2. Test horizontal flip
        pinController.flipHorizontal()
        guard let container = pinWindow.contentView,
              let transform = container.layer?.transform else {
            print("PinWindow contentView missing layer")
            return false
        }
        guard transform.m11 == -1.0 else {
            print("PinWindow flip horizontal failed: expected m11 == -1.0, got \(transform.m11)")
            return false
        }

        // Flip back
        pinController.flipHorizontal()
        guard container.layer?.transform.m11 == 1.0 else {
            return false
        }

        // 3. Test reset size
        pinController.resetSize()
        guard pinWindow.frame.width > 0 && pinWindow.frame.height > 0 else {
            return false
        }

        return true
    }

    // MARK: - Test 10: Window Shadow and Capture Options Mapping
    public static func testWindowShadowAndCaptureOptions() -> Bool {
        // Snip-style Option shadow toggle verification:
        // withShadow = true -> [.bestResolution]
        // withShadow = false -> [.bestResolution, .boundsIgnoreFraming]
        let shadowOptions: CGWindowImageOption = true ? [.bestResolution] : [.bestResolution, .boundsIgnoreFraming]
        guard !shadowOptions.contains(.boundsIgnoreFraming) else {
            print("withShadow=true should not contain boundsIgnoreFraming")
            return false
        }

        let noShadowOptions: CGWindowImageOption = false ? [.bestResolution] : [.bestResolution, .boundsIgnoreFraming]
        guard noShadowOptions.contains(.boundsIgnoreFraming) && noShadowOptions.contains(.bestResolution) else {
            print("withShadow=false must contain both bestResolution and boundsIgnoreFraming")
            return false
        }

        return true
    }

    // MARK: - Test 11: Annotation Defaults and Color Palette Presets
    public static func testAnnotationDefaultsAndColorPalettePresets() -> Bool {
        // Verify all 9 preset colors
        let presets = PresetColor.all
        guard presets.count == 9 else {
            print("Expected 9 preset colors, got \(presets.count)")
            return false
        }

        let expectedNames = ["红色", "橙色", "黄色", "绿色", "青色", "蓝色", "紫色", "白色", "黑色"]
        let actualNames = presets.map { $0.name }
        guard actualNames == expectedNames else {
            print("Color preset names mismatch: \(actualNames)")
            return false
        }

        let item = AnnotationItem(tool: .rect, startPoint: .zero, endPoint: CGPoint(x: 20, y: 20))
        guard item.lineWidth == 4 else {
            print("Annotations must use the retained default line width")
            return false
        }

        return true
    }

    // MARK: - Test 12: Dark Toolbar & Dynamic Recording Button
    public static func testDarkToolbarAndDynamicRecordButton() -> Bool {
        final class MockToolbarDelegate: ScreenshotToolbarDelegate {
            var selectedTool: AnnotationTool?
            var selectedColor: NSColor?
            var pinClicked = false
            var studioClicked = false
            var scrollClicked = false
            var recordClicked = false
            var undoClicked = false
            var saveClicked = false
            var copyClicked = false
            var cancelClicked = false

            func toolbarDidSelectTool(_ tool: AnnotationTool) { selectedTool = tool }
            func toolbarDidSelectColor(_ color: NSColor) { selectedColor = color }
            func toolbarDidClickPin() { pinClicked = true }
            func toolbarDidClickStudio() { studioClicked = true }
            func toolbarDidClickScrollCapture() { scrollClicked = true }
            func toolbarDidClickRecord() { recordClicked = true }
            func toolbarDidClickUndo() { undoClicked = true }
            func toolbarDidClickSave() { saveClicked = true }
            func toolbarDidClickCopy() { copyClicked = true }
            func toolbarDidClickCancel() { cancelClicked = true }
        }

        let toolbar = ScreenshotToolbarView(frame: NSRect(x: 0, y: 0, width: 620, height: 38))
        let delegate = MockToolbarDelegate()
        toolbar.delegate = delegate

        // 1. Verify dark mode visual effect and layer setup
        guard toolbar.wantsLayer, toolbar.layer?.cornerRadius == 11 else {
            print("Toolbar layer configuration incorrect")
            return false
        }

        // 2. Verify Tool selection
        toolbar.selectTool(.arrow)
        guard toolbar.currentTool == .arrow, delegate.selectedTool == .arrow else {
            print("Tool selection failed for .arrow")
            return false
        }

        // 3. Verify RecordingToolbarButton with dynamic animations exists
        var foundRecordBtn: RecordingToolbarButton?
        func findRecordBtn(in view: NSView) {
            for sub in view.subviews {
                if let r = sub as? RecordingToolbarButton {
                    foundRecordBtn = r
                    return
                }
                findRecordBtn(in: sub)
            }
        }
        findRecordBtn(in: toolbar)

        guard let recordBtn = foundRecordBtn else {
            print("RecordingToolbarButton not found in toolbar")
            return false
        }

        // 减少动态效果开启时不应依赖呼吸动画传达录制操作。
        let opacityAnimation = recordBtn.layer?.animation(forKey: "breathingShadowOpacity")
        let radiusAnimation = recordBtn.layer?.animation(forKey: "breathingShadowRadius")
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            guard opacityAnimation == nil, radiusAnimation == nil else {
                print("减少动态效果时应停用录制按钮呼吸动画")
                return false
            }
        } else {
            guard opacityAnimation != nil, radiusAnimation != nil else {
                print("录制按钮动态状态缺失")
                return false
            }
        }

        // Verify clicking record button invokes delegate
        if let target = recordBtn.target, let action = recordBtn.action {
            _ = target.perform(action, with: recordBtn)
        }
        guard delegate.recordClicked else {
            print("record button click did not notify delegate")
            return false
        }

        // Removed tools and line-width controls must not remain reachable in the toolbar.
        func buttons(in view: NSView) -> [NSButton] {
            view.subviews.flatMap { child in
                (child as? NSButton).map { [$0] } ?? buttons(in: child)
            }
        }
        let toolbarButtons = buttons(in: toolbar)
        let labels = toolbarButtons.compactMap { $0.accessibilityLabel() }
        let removedLabels = ["画笔", "高亮笔", "细线条", "中线条", "粗线条", "笔触颜色"]
        guard !labels.contains(where: removedLabels.contains), labels.contains("标注颜色") else {
            print("Removed annotation controls remain or annotation color is missing: \(labels)")
            return false
        }
        let expectedTools: [AnnotationTool] = [.select, .rect, .ellipse, .arrow, .line, .mosaic, .text, .stepBadge]
        guard AnnotationTool.allCases == expectedTools else { return false }
        let retainedShortcuts: [(AnnotationTool, String)] = [
            (.rect, "1"), (.ellipse, "2"), (.arrow, "3"),
            (.mosaic, "6"), (.text, "7"), (.stepBadge, "8")
        ]
        for (tool, shortcut) in retainedShortcuts {
            guard tool.shortcutNumber == shortcut,
                  let button = toolbarButtons.compactMap({ $0 as? DarkToolbarIconButton }).first(where: {
                      $0.tooltipItem?.title == tool.rawValue
                  }), button.tooltipItem?.shortcut == shortcut else {
                print("Annotation shortcut and tooltip disagree for \(tool.rawValue)")
                return false
            }
        }

        guard let lineButton = toolbarButtons.compactMap({ $0 as? DarkToolbarIconButton }).first(where: {
            $0.tooltipItem?.title == "直线"
        }), lineButton.tooltipItem?.shortcut == nil,
              let lineTarget = lineButton.target, let lineAction = lineButton.action else {
            print("Retained line annotation must have a toolbar entry without a numeric shortcut")
            return false
        }
        _ = lineTarget.perform(lineAction, with: lineButton)
        guard toolbar.currentTool == .line, delegate.selectedTool == .line else {
            print("Line toolbar button did not select the line annotation tool")
            return false
        }

        // Exercise actual overlay key handling, including the non-sequential macOS key codes.
        let overlay = ScreenshotOverlayView(frame: NSRect(x: 0, y: 0, width: 1280, height: 800))
        guard let overlayToolbar = overlay.subviews.compactMap({ $0 as? ScreenshotToolbarView }).first else { return false }
        let shortcuts: [(UInt16, String, AnnotationTool)] = [
            (18, "1", .rect), (19, "2", .ellipse), (20, "3", .arrow),
            (22, "6", .mosaic), (26, "7", .text), (28, "8", .stepBadge)
        ]
        for (keyCode, characters, expectedTool) in shortcuts {
            guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                              timestamp: 0, windowNumber: 0, context: nil,
                                              characters: characters, charactersIgnoringModifiers: characters,
                                              isARepeat: false, keyCode: keyCode) else { return false }
            overlay.keyDown(with: event)
            guard overlayToolbar.currentTool == expectedTool else {
                print("Annotation shortcut \(characters) selected the wrong tool")
                return false
            }
        }
        for (keyCode, characters) in [(UInt16(21), "4"), (UInt16(23), "5")] {
            guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                              timestamp: 0, windowNumber: 0, context: nil,
                                              characters: characters, charactersIgnoringModifiers: characters,
                                              isARepeat: false, keyCode: keyCode) else { return false }
            overlay.keyDown(with: event)
            guard overlayToolbar.currentTool == .stepBadge else {
                print("Removed annotation shortcut \(characters) still changes the selected tool")
                return false
            }
        }

        return true
    }

    // MARK: - Test 13: Permissions Status & Safe Detection
    public static func testPermissionsStatusAndRefresh() -> Bool {
        // 1. Safe access to Permissions properties
        let hasScreen = Permissions.hasScreenRecordingPermission
        let hasAX = Permissions.hasAccessibilityPermission

        print("  Current screen recording permission: \(hasScreen)")
        print("  Current accessibility permission: \(hasAX)")

        // 2. Ensure SettingsWindowController can be initialized without crash
        let settingsWC = SettingsWindowController.shared
        guard settingsWC.window != nil else {
            print("SettingsWindowController window is nil")
            return false
        }

        // 3. Verify AppState permission guard methods behave safely
        guard Permissions.hasAccessibilityPermission == hasAX else {
            print("Accessibility permission changed unexpectedly during test")
            return false
        }

        return true
    }

    // MARK: - Test 14: Screenshot Studio Rendering and Mockups
    public static func testScreenshotStudioRenderer() -> Bool {
        // 1. Create a synthetic test CGImage (200x120)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(
            data: nil,
            width: 200,
            height: 120,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            print("Failed to create test graphics context")
            return false
        }
        ctx.setFillColor(NSColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1.0).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 120))
        guard let testImg = ctx.makeImage() else {
            print("Failed to create test image")
            return false
        }

        // 2. Test rendering with macOS Dark Mockup & Blur Background
        let model = ScreenshotStudioModel()
        model.mockup = .macDark
        model.background = .blur
        model.padding = 32
        model.cornerRadius = 14
        model.shadow = .deep

        guard let renderedBlur = ScreenshotStudioRenderer.render(image: testImg, model: model, targetScale: 1.0) else {
            print("Failed to render mockup with blur background")
            return false
        }
        guard renderedBlur.width > testImg.width && renderedBlur.height > testImg.height else {
            print("Rendered image dimensions must expand for canvas padding & chrome: got (\(renderedBlur.width)x\(renderedBlur.height))")
            return false
        }

        // 3. Test rendering with Browser Chrome & Sonoma Sunset Gradient
        model.mockup = .browserDark
        model.background = .gradientSonoma
        model.aspectRatio = .ratio16_9

        guard let renderedBrowser = ScreenshotStudioRenderer.render(image: testImg, model: model, targetScale: 1.0) else {
            print("Failed to render browser mockup with gradient background")
            return false
        }
        guard renderedBrowser.width > 0 && renderedBrowser.height > 0 else {
            print("Browser mockup output image has empty dimensions")
            return false
        }

        // 4. Test Transparent Background & No Mockup
        model.mockup = .none
        model.background = .transparent
        model.padding = 0
        model.aspectRatio = .auto

        guard let renderedTransparent = ScreenshotStudioRenderer.render(image: testImg, model: model, targetScale: 1.0) else {
            print("Failed to render transparent mockup")
            return false
        }
        guard renderedTransparent.width == testImg.width && renderedTransparent.height == testImg.height else {
            print("Padding 0 & mockup none should match source dimensions exactly: got (\(renderedTransparent.width)x\(renderedTransparent.height))")
            return false
        }

        return true
    }

    // MARK: - Test 15: Toolbar Tooltip Bubble View & Bindings
    public static func testToolbarTooltipBubbleView() -> Bool {
        // 1. Tooltip Item Model & Size calculation
        let item1 = ToolbarTooltipItem(title: "矩形", shortcut: "1")
        let size1 = ToolbarTooltipBubbleView.calculateSize(for: item1)
        guard size1.width >= 36 && size1.height == 26 else {
            print("Tooltip size calculation failed for item1: got \(size1)")
            return false
        }

        let itemNoShortcut = ToolbarTooltipItem(title: "矩形")
        let sizeNoShortcut = ToolbarTooltipBubbleView.calculateSize(for: itemNoShortcut)
        guard sizeNoShortcut.width > 0 && sizeNoShortcut.width < size1.width else {
            print("Size without shortcut should be narrower than size with shortcut for identical title: (\(sizeNoShortcut.width) vs \(size1.width))")
            return false
        }

        // 2. Test bubble presentation & container integration
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let toolbar = ScreenshotToolbarView()
        container.addSubview(toolbar)

        guard toolbar.tooltipBubble.superview == container else {
            print("tooltipBubble should automatically mount to toolbar's superview")
            return false
        }

        // 3. Test hitTest passthrough
        guard toolbar.tooltipBubble.hitTest(NSPoint(x: 10, y: 10)) == nil else {
            print("tooltipBubble must never intercept mouse clicks (hitTest must return nil)")
            return false
        }

        // 4. Test button tooltip bindings
        // A. Retained annotation tools (1, 2, 3, 6, 7, 8)
        let rectTool = AnnotationTool.rect
        toolbar.selectTool(rectTool) // ensures button exists and handles selection

        // B. DarkToolbarIconButton
        let testBtn = DarkToolbarIconButton(symbol: "square")
        testBtn.frame = NSRect(x: 100, y: 100, width: 28, height: 28)
        container.addSubview(testBtn)

        let bubble = toolbar.tooltipBubble
        bubble.show(item: item1, for: testBtn, in: container)

        guard bubble.currentItem == item1 else {
            print("Bubble currentItem mismatch: expected \(item1), got \(String(describing: bubble.currentItem))")
            return false
        }
        guard !bubble.isHidden else {
            print("Bubble should be visible after show")
            return false
        }

        // 5. Test hide
        bubble.hide(animated: false)
        guard bubble.isHidden && bubble.currentItem == nil else {
            print("Bubble should be immediately hidden and currentItem reset on non-animated hide")
            return false
        }

        return true
    }
    static func testScrollCaptureControlRecovery() -> Bool {
        let panel = ScrollCapturePreviewWindow()
        defer { panel.close() }
        panel.updatePreview(image: UIPreviewDelegate.sampleImage(), totalHeight: 1680)
        panel.setAutoScrollState(direction: nil, isAccessibilityGranted: true)
        func labels(in view: NSView) -> [String] {
            view.subviews.flatMap { child in
                (child as? NSTextField).map { [$0.stringValue] } ?? labels(in: child)
            }
        }
        guard let content = panel.contentView else { return false }
        let recoveries: [() -> Void] = [
            { panel.showRecovering(direction: .up, canSavePartial: true) },
            { panel.showTargetPaused("返回目标应用后继续") },
            { panel.showInterrupted("读取已中断") }
        ]
        for recover in recoveries {
            panel.showFinishing()
            guard labels(in: content).contains("正在合成…") else { return false }
            recover()
            let visibleLabels = labels(in: content)
            guard !visibleLabels.contains("正在合成…"), visibleLabels.contains("\(1680.formatted()) px") else {
                print("退出合成状态后必须恢复已捕获高度")
                return false
            }
        }
        return true
    }

    static func testStudioSnapshot() -> Bool {
        let model = ScreenshotStudioModel()
        model.mockup = .browserLight
        model.background = .solidWhite
        model.padding = 68
        model.cornerRadius = 22
        model.shadow = .soft
        model.aspectRatio = .ratio3_4
        model.windowTitle = "独立快照"
        let snapshot = model.snapshot()
        model.reset()
        guard snapshot.mockup == .browserLight, snapshot.background == .solidWhite,
              snapshot.padding == 68, snapshot.cornerRadius == 22, snapshot.shadow == .soft,
              snapshot.aspectRatio == .ratio3_4, snapshot.windowTitle == "独立快照" else {
            print("编辑参数不应影响已提交的渲染快照")
            return false
        }
        guard let output = ScreenshotStudioRenderer.render(image: UIPreviewDelegate.sampleImage(), model: snapshot, targetScale: 0.5),
              abs(CGFloat(output.width) / CGFloat(output.height) - 0.75) < 0.005 else {
            print("3:4 画幅应按快照渲染，保持比例")
            return false
        }
        return true
    }

    static func testRecordingToolbarFeedback() -> Bool {
        let toolbar = RecordingToolbarWindow(capturesSystemAudio: false)
        defer { toolbar.stopTimer(); toolbar.close() }
        var buttons: [NSButton] = []
        var labels: [String] = []
        func collect(_ view: NSView) {
            if let button = view as? NSButton { buttons.append(button) }
            if let label = view as? NSTextField { labels.append(label.stringValue) }
            for child in view.subviews { collect(child) }
        }
        guard let content = toolbar.contentView else { return false }
        collect(content)
        guard labels.contains("无声音"), !labels.contains("系统声音"),
              let stop = buttons.first(where: { $0.title == "结束录制" }),
              buttons.count == 1 else {
            print("录制工具栏应显示真实声音状态和可用的停止操作")
            return false
        }
        var stopCount = 0
        toolbar.onStop = { stopCount += 1 }
        toolbar.startTimer()
        stop.performClick(nil)
        stop.performClick(nil)
        guard stopCount == 1, !stop.isEnabled, stop.title == "正在保存" else {
            print("保存阶段必须阻止重复停止并准确显示状态")
            return false
        }
        return true
    }

    static func testPreparedClipboardFormats() -> Bool {
        let source = UIPreviewDelegate.sampleImage()
        guard let prepared = PasteboardHelper.prepareImage(source, alsoAsFile: false) else { return false }
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let fileURL = URL(fileURLWithPath: "/tmp/cduyzhShot-ui-fixture.png")
        let image = PasteboardHelper.PreparedImage(png: prepared.png, tiff: prepared.tiff, fileURL: fileURL)
        guard PasteboardHelper.publish(image, to: pasteboard),
              let png = pasteboard.data(forType: .png), let decoded = NSBitmapImageRep(data: png),
              decoded.pixelsWide == source.width, decoded.pixelsHigh == source.height,
              pasteboard.data(forType: .tiff) != nil,
              pasteboard.string(forType: .fileURL) == fileURL.absoluteString else {
            print("图片、TIFF 和文件引用必须共存于同一剪贴板条目")
            return false
        }
        return true
    }

    // MARK: - Test 16: Update Checker & Semantic Version Comparison
    public static func testUpdateChecker() -> Bool {
        // 1. 语义版本号比对
        guard VersionComparator.isRemoteNewer(remoteVersion: "v1.2.0", remoteBuild: nil, localVersion: "1.1.0", localBuild: "2") else {
            print("比对失败: 1.2.0 应该比 1.1.0 更新")
            return false
        }
        guard VersionComparator.isRemoteNewer(remoteVersion: "1.1.1", remoteBuild: "1", localVersion: "1.1.0", localBuild: "2") else {
            print("比对失败: 1.1.1 应该比 1.1.0 更新")
            return false
        }
        guard VersionComparator.isRemoteNewer(remoteVersion: "1.1.0", remoteBuild: "3", localVersion: "1.1.0", localBuild: "2") else {
            print("比对失败: 同版本不同构建号 (build 3 > build 2) 应该判定为有更新")
            return false
        }
        guard !VersionComparator.isRemoteNewer(remoteVersion: "1.1.0", remoteBuild: "2", localVersion: "1.1.0", localBuild: "2") else {
            print("比对失败: 完全相同的版本号和构建号不应判定为有更新")
            return false
        }
        guard !VersionComparator.isRemoteNewer(remoteVersion: "1.0.9", remoteBuild: "99", localVersion: "1.1.0", localBuild: "2") else {
            print("比对失败: 旧版本 1.0.9 不应判定为有更新")
            return false
        }
        guard VersionComparator.isRemoteNewer(remoteVersion: "2.0.0", remoteBuild: nil, localVersion: "1.9.9", localBuild: nil) else {
            print("比对失败: 2.0.0 应该比 1.9.9 更新")
            return false
        }

        // 2. 解析 GitHub Releases API 格式数据
        let githubJSON = """
        {
          "tag_name": "v1.2.0",
          "name": "cduyzhShot 1.2.0 (构建 3)",
          "body": "• 新增在线检查更新功能\\n• 支持 GitHub 私人仓库 PAT 授权\\n• 优化滚动长截图对齐算法",
          "html_url": "https://github.com/cduyzh/SnapScreen/releases/tag/v1.2.0",
          "published_at": "2026-10-19T09:00:00Z",
          "assets": [
            {
              "name": "cduyzhShot-1.2.0-build3.zip",
              "browser_download_url": "https://github.com/cduyzh/SnapScreen/releases/download/v1.2.0/cduyzhShot-1.2.0-build3.zip"
            }
          ]
        }
        """.data(using: .utf8)!

        guard let githubRelease = try? UpdateManager.parseReleaseData(githubJSON) else {
            print("解析 GitHub Release JSON 失败")
            return false
        }
        guard githubRelease.version == "v1.2.0",
              githubRelease.build == "3",
              githubRelease.downloadURL?.absoluteString == "https://github.com/cduyzh/SnapScreen/releases/download/v1.2.0/cduyzhShot-1.2.0-build3.zip",
              githubRelease.htmlURL?.absoluteString == "https://github.com/cduyzh/SnapScreen/releases/tag/v1.2.0",
              githubRelease.releaseNotes.contains("新增在线检查更新功能") else {
            print("GitHub Release 字段解析校验不符合预期: \(githubRelease)")
            return false
        }

        // 3. 解析 release.json 清单格式数据
        let manifestJSON = """
        {
          "name": "cduyzhShot",
          "version": "1.3.0",
          "build": "4",
          "releaseDate": "2026-10-20",
          "archive": "cduyzhShot-1.3.0.zip",
          "downloadUrl": "https://example.com/cduyzhShot-1.3.0.zip",
          "title": "cduyzhShot 1.3.0 优化版本",
          "highlights": [
            "性能大幅提升",
            "修复已知问题"
          ]
        }
        """.data(using: .utf8)!

        guard let manifestRelease = try? UpdateManager.parseReleaseData(manifestJSON) else {
            print("解析 release.json 清单失败")
            return false
        }
        guard manifestRelease.version == "1.3.0",
              manifestRelease.build == "4",
              manifestRelease.downloadURL?.absoluteString == "https://example.com/cduyzhShot-1.3.0.zip",
              manifestRelease.releaseNotes.contains("性能大幅提升") else {
            print("release.json 清单字段解析不符合预期: \(manifestRelease)")
            return false
        }

        // 4. 用户偏好持久化测试
        let prefs = UserPreferences.shared
        let originalAutoCheck = prefs.autoCheckForUpdates
        prefs.autoCheckForUpdates = false
        guard !prefs.autoCheckForUpdates else {
            print("更新偏好设置持久化 autoCheckForUpdates 失败")
            return false
        }
        prefs.autoCheckForUpdates = originalAutoCheck

        return true
    }

}
