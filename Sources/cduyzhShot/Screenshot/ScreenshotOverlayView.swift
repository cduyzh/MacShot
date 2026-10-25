import AppKit
import CoreGraphics

public protocol ScreenshotOverlayDelegate: AnyObject {
    func overlayDidCancel()
    func overlayDidFinish(image: CGImage, rect: CGRect)
    func overlayDidRequestPin(image: CGImage, rect: CGRect)
    func overlayDidRequestStudio(image: CGImage, rect: CGRect)
    func overlayDidRequestScrollCapture(rect: CGRect)
    func overlayDidRequestRecord(rect: CGRect)
}

public final class ScreenshotOverlayView: NSView, ScreenshotToolbarDelegate, InPlaceTextEditorDelegate {
    public weak var delegate: ScreenshotOverlayDelegate?
    private var activeTextEditor: InPlaceTextEditor?
    private var isOptionPressed: Bool = false

    public var screenImage: CGImage? {
        didSet {
            magnifierView.sourceImage = screenImage
            needsDisplay = true
        }
    }

    public var isScrollMode: Bool = false {
        didSet {
            needsDisplay = true
        }
    }

    /// Converts local selectionRect (top-left flipped coordinates) to Cocoa screen coordinates (bottom-left)
    public var selectionCocoaScreenRect: CGRect {
        guard let win = window else { return selectionRect }
        let screenFrame = win.screen?.frame ?? NSScreen.main?.frame ?? bounds
        let cocoaX = screenFrame.origin.x + selectionRect.origin.x
        let cocoaY = screenFrame.origin.y + (screenFrame.height - (selectionRect.origin.y + selectionRect.height))
        return CGRect(x: cocoaX, y: cocoaY, width: selectionRect.width, height: selectionRect.height)
    }

    private var selectionRect: CGRect = .zero {
        didSet {
            magnifierView.selectionSize = selectionRect.size
            updateToolbarPosition()
            needsDisplay = true
        }
    }

    private var hoveredWindowRect: CGRect? {
        didSet { needsDisplay = true }
    }

    private var hoveredWindowInfo: DetectedWindow?
    private var candidateWindowRect: CGRect?

    private enum DragMode {
        case none
        case createSelection
        case moveSelection
        case resize(HandlePosition)
        case drawAnnotation
    }

    private enum HandlePosition {
        case topLeft, topCenter, topRight
        case middleLeft, middleRight
        case bottomLeft, bottomCenter, bottomRight
    }

    private var dragMode: DragMode = .none
    private var dragStartPoint: CGPoint = .zero
    private var selectionBeforeDrag: CGRect = .zero

    // Annotations
    private var annotations: [AnnotationItem] = []
    private var currentDraftAnnotation: AnnotationItem?
    private var nextBadgeNumber = 1

    // Subviews
    private let toolbar = ScreenshotToolbarView()
    private let magnifierView = MagnifierView()
    private var trackingAreaRef: NSTrackingArea?

    public override var isFlipped: Bool { true }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        wantsLayer = true
        toolbar.delegate = self
        toolbar.isHidden = true
        addSubview(toolbar)

        magnifierView.isHidden = !UserPreferences.shared.showMagnifier
        addSubview(magnifierView)
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingAreaRef {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    // MARK: - Drawing
    public override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // Draw screen image backdrop upright
        if let img = screenImage {
            let nsImg = NSImage(cgImage: img, size: bounds.size)
            nsImg.draw(in: bounds)
        }

        // Draw dimming mask outside selection
        context.saveGState()
        context.setFillColor(NSColor(calibratedWhite: 0, alpha: 0.45).cgColor)

        if selectionRect.isEmpty {
            // Entire screen dimmed
            context.fill(bounds)

            // Highlight hovered window if available
            if let hw = hoveredWindowRect {
                context.setStrokeColor(NSColor.systemBlue.cgColor)
                context.setLineWidth(2.5)
                context.stroke(hw)

                // Window title label badge
                if let win = hoveredWindowInfo, !win.windowTitle.isEmpty {
                    drawWindowBadge(title: win.windowTitle, rect: hw, in: context)
                }
            }
        } else {
            // Dim outside selection cutout
            let maskPath = CGMutablePath()
            maskPath.addRect(bounds)
            maskPath.addRect(selectionRect)
            context.addPath(maskPath)
            context.clip(using: .evenOdd)
            context.fill(bounds)
            context.restoreGState()

            // Draw selection border
            context.saveGState()
            context.setStrokeColor(NSColor.systemBlue.cgColor)
            context.setLineWidth(1.5)
            context.stroke(selectionRect)

            // Draw selection dimensions tag
            drawDimensionsTag(rect: selectionRect, in: context)

            // Draw 8 resize handles
            drawResizeHandles(for: selectionRect, in: context)
            context.restoreGState()

            // Draw annotations inside selection
            context.saveGState()
            context.clip(to: selectionRect)
            for item in annotations {
                AnnotationRenderer.render(item: item, in: context, baseImage: screenImage)
            }
            if let draft = currentDraftAnnotation {
                AnnotationRenderer.render(item: draft, in: context, baseImage: screenImage)
            }
            context.restoreGState()
        }

        // Draw mode guidance banner on top
        if isScrollMode {
            drawScrollModeBanner(in: context)
        }
    }

    private func drawScrollModeBanner(in context: CGContext) {
        let text = "📜 滚动长截图模式：框选需要滚动的区域（或单击窗口），松开即开始" as NSString
        let font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]
        let textSize = text.size(withAttributes: attrs)
        let bannerW = textSize.width + 36
        let bannerH: CGFloat = 34
        let bannerRect = CGRect(x: bounds.midX - bannerW / 2, y: 28, width: bannerW, height: bannerH)

        context.saveGState()
        let path = CGPath(roundedRect: bannerRect, cornerWidth: 17, cornerHeight: 17, transform: nil)
        context.addPath(path)
        context.setFillColor(NSColor(calibratedWhite: 0.12, alpha: 0.94).cgColor)
        context.fillPath()

        context.addPath(path)
        context.setStrokeColor(NSColor.systemIndigo.withAlphaComponent(0.85).cgColor)
        context.setLineWidth(1.5)
        context.strokePath()

        NSGraphicsContext.saveGraphicsState()
        let nsCtx = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.current = nsCtx
        text.draw(at: CGPoint(x: bannerRect.minX + 18, y: bannerRect.minY + 8), withAttributes: attrs)
        NSGraphicsContext.restoreGraphicsState()
        context.restoreGState()
    }

    private var dimensionsTagRect: CGRect = .zero

    private func drawDimensionsTag(rect: CGRect, in context: CGContext) {
        let text = "\(Int(rect.width)) × \(Int(rect.height))  ✎" as NSString
        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]
        let textSize = text.size(withAttributes: attrs)
        let tagW = textSize.width + 16
        let tagH: CGFloat = 22
        var tagY = rect.minY - tagH - 6
        if tagY < 10 {
            tagY = rect.minY + 6
        }
        let tagRect = CGRect(x: max(10, min(rect.minX, bounds.width - tagW - 10)), y: tagY, width: tagW, height: tagH)
        self.dimensionsTagRect = tagRect

        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: 1.5), blur: 4, color: NSColor.black.withAlphaComponent(0.45).cgColor)
        let path = CGPath(roundedRect: tagRect, cornerWidth: 6, cornerHeight: 6, transform: nil)
        context.addPath(path)
        context.setFillColor(NSColor(calibratedWhite: 0.12, alpha: 0.94).cgColor)
        context.fillPath()

        // Border around dimensions tag
        context.addPath(path)
        context.setStrokeColor(NSColor(white: 1.0, alpha: 0.25).cgColor)
        context.setLineWidth(1.0)
        context.strokePath()

        NSGraphicsContext.saveGraphicsState()
        let nsCtx = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.current = nsCtx
        text.draw(at: CGPoint(x: tagRect.minX + 8, y: tagRect.minY + 4), withAttributes: attrs)
        NSGraphicsContext.restoreGraphicsState()
        context.restoreGState()
    }

    private func promptForCustomDimensions() {
        let alert = NSAlert()
        alert.messageText = "自定义画布宽高 (像素)"
        alert.informativeText = "当前选区尺寸：\(Int(selectionRect.width)) × \(Int(selectionRect.height)) px\n输入新尺寸后回车即可应用"
        alert.addButton(withTitle: "应用尺寸")
        alert.addButton(withTitle: "取消")

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 60))

        let widthLabel = NSTextField(labelWithString: "宽度 (W):")
        widthLabel.frame = NSRect(x: 0, y: 32, width: 65, height: 20)
        let widthInput = NSTextField(frame: NSRect(x: 70, y: 30, width: 140, height: 24))
        widthInput.stringValue = "\(Int(selectionRect.width))"

        let heightLabel = NSTextField(labelWithString: "高度 (H):")
        heightLabel.frame = NSRect(x: 0, y: 4, width: 65, height: 20)
        let heightInput = NSTextField(frame: NSRect(x: 70, y: 2, width: 140, height: 24))
        heightInput.stringValue = "\(Int(selectionRect.height))"

        container.addSubview(widthLabel)
        container.addSubview(widthInput)
        container.addSubview(heightLabel)
        container.addSubview(heightInput)
        alert.accessoryView = container

        alert.beginSheetModal(for: window!) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self = self else { return }
            if let w = Double(widthInput.stringValue), let h = Double(heightInput.stringValue), w > 10, h > 10 {
                let clampedW = min(CGFloat(w), self.bounds.width)
                let clampedH = min(CGFloat(h), self.bounds.height)
                let newX = max(0, min(self.selectionRect.minX, self.bounds.width - clampedW))
                let newY = max(0, min(self.selectionRect.minY, self.bounds.height - clampedH))
                self.selectionRect = CGRect(x: newX, y: newY, width: clampedW, height: clampedH)
                self.needsDisplay = true
            }
        }
    }

    public override func flagsChanged(with event: NSEvent) {
        super.flagsChanged(with: event)
        let newOptionState = event.modifierFlags.contains(.option)
        if newOptionState != isOptionPressed {
            isOptionPressed = newOptionState
            needsDisplay = true
        }
    }

    private func drawWindowBadge(title: String, rect: CGRect, in context: CGContext) {
        let displayTitle = isOptionPressed ? "\(title)  •  [⌥ 带立体阴影]" : "\(title)  •  (按住 ⌥ 截立体阴影)"
        let str = displayTitle as NSString
        let font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let size = str.size(withAttributes: attrs)
        let badgeW = min(size.width + 16, 320.0)
        let badgeRect = CGRect(x: rect.minX + 8, y: rect.minY + 8, width: badgeW, height: 22)

        let path = CGPath(roundedRect: badgeRect, cornerWidth: 5, cornerHeight: 5, transform: nil)
        context.addPath(path)
        let bgColor = isOptionPressed ? NSColor.systemIndigo.withAlphaComponent(0.92) : NSColor.systemBlue.withAlphaComponent(0.9)
        context.setFillColor(bgColor.cgColor)
        context.fillPath()

        NSGraphicsContext.saveGraphicsState()
        let nsCtx = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.current = nsCtx
        str.draw(in: CGRect(x: badgeRect.minX + 8, y: badgeRect.minY + 4, width: badgeW - 16, height: 16), withAttributes: attrs)
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawResizeHandles(for rect: CGRect, in context: CGContext) {
        let handleSize: CGFloat = 8.0
        let positions: [CGPoint] = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.midX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.midY),
            CGPoint(x: rect.maxX, y: rect.midY),
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.midX, y: rect.maxY),
            CGPoint(x: rect.maxX, y: rect.maxY)
        ]

        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -1), blur: 3, color: NSColor.black.withAlphaComponent(0.35).cgColor)
        context.setFillColor(NSColor.white.cgColor)
        context.setStrokeColor(NSColor.systemBlue.cgColor)
        context.setLineWidth(1.8)

        for pt in positions {
            let hRect = CGRect(x: pt.x - handleSize / 2, y: pt.y - handleSize / 2, width: handleSize, height: handleSize)
            context.fillEllipse(in: hRect)
            context.strokeEllipse(in: hRect)
        }
        context.restoreGState()
    }

    // MARK: - Mouse Events
    public override func mouseMoved(with event: NSEvent) {
        let mouseScreenPt = NSEvent.mouseLocation
        let currentScreen = window?.screen ?? NSScreen.main
        if let s = currentScreen, !s.frame.contains(mouseScreenPt) {
            // Mouse is currently on another display! Hide magnifier & window hover on this display
            magnifierView.isHidden = true
            if hoveredWindowRect != nil {
                hoveredWindowRect = nil
                hoveredWindowInfo = nil
                needsDisplay = true
            }
            return
        }

        let pt = convert(event.locationInWindow, from: nil)
        updateMagnifier(at: pt)
        updateCursor(at: pt)

        if selectionRect.isEmpty {
            // Window hover detection with exact multi-display coordinate translation
            let screenPt = window?.convertToScreen(NSRect(origin: event.locationInWindow, size: .zero)).origin ?? pt
            if let detected = WindowDetector.findWindow(at: screenPt) {
                let screenFrame = currentScreen?.frame ?? bounds
                let localX = detected.cocoaFrame.origin.x - screenFrame.origin.x
                let localY = screenFrame.height - (detected.cocoaFrame.origin.y - screenFrame.origin.y + detected.cocoaFrame.height)
                self.hoveredWindowRect = CGRect(x: localX, y: localY, width: detected.cocoaFrame.width, height: detected.cocoaFrame.height)
                self.hoveredWindowInfo = detected
            } else {
                self.hoveredWindowRect = nil
                self.hoveredWindowInfo = nil
            }
        }
    }

    private func updateCursor(at pt: CGPoint) {
        if selectionRect.isEmpty {
            NSCursor.crosshair.set()
            return
        }

        if let handle = handleAtPoint(pt) {
            switch handle {
            case .topLeft, .bottomRight, .topRight, .bottomLeft:
                NSCursor.crosshair.set()
            case .topCenter, .bottomCenter:
                NSCursor.resizeUpDown.set()
            case .middleLeft, .middleRight:
                NSCursor.resizeLeftRight.set()
            }
            return
        }

        if selectionRect.contains(pt) {
            if toolbar.currentTool != .select {
                NSCursor.crosshair.set()
            } else {
                NSCursor.openHand.set()
            }
        } else {
            NSCursor.crosshair.set()
        }
    }

    public override func mouseDown(with event: NSEvent) {
        toolbar.hideTooltip(animated: false)
        let pt = convert(event.locationInWindow, from: nil)
        dragStartPoint = pt
        selectionBeforeDrag = selectionRect

        // Commit any in-place text editor if clicked outside
        if let editor = activeTextEditor {
            if !editor.frame.contains(pt) {
                editor.commitAndDismiss()
            }
        }

        if event.clickCount == 2 && !selectionRect.isEmpty && selectionRect.contains(pt) {
            // Double click inside selection -> Finish & Copy!
            finishAndCopy()
            return
        }

        // Click on dimensions tag -> Open custom size prompt
        if !selectionRect.isEmpty && dimensionsTagRect.contains(pt) {
            promptForCustomDimensions()
            return
        }

        if selectionRect.isEmpty {
            // Record candidate window for click-snapping, but remain in .createSelection to allow dragging!
            candidateWindowRect = hoveredWindowRect
            dragMode = .createSelection
            magnifierView.isHidden = !UserPreferences.shared.showMagnifier
            return
        }

        // Inside selection with an active annotation tool?
        if toolbar.currentTool != .select && selectionRect.contains(pt) {
            dragMode = .drawAnnotation
            startAnnotationDraft(at: pt)
            return
        }

        // Check resize handles
        if let handle = handleAtPoint(pt) {
            dragMode = .resize(handle)
            return
        }

        // Check inside selection for moving
        if selectionRect.contains(pt) {
            dragMode = .moveSelection
            return
        }

        // Click outside selection -> reset and start new selection
        selectionRect = .zero
        toolbar.isHidden = true
        magnifierView.isHidden = !UserPreferences.shared.showMagnifier
        candidateWindowRect = hoveredWindowRect
        dragMode = .createSelection
    }

    public override func mouseDragged(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        updateMagnifier(at: pt)

        switch dragMode {
        case .createSelection:
            let dx = abs(pt.x - dragStartPoint.x)
            let dy = abs(pt.y - dragStartPoint.y)
            if dx > 3 || dy > 3 {
                // User is actively dragging to draw a custom region! Drop window snap candidate
                candidateWindowRect = nil
                hoveredWindowRect = nil
            }
            let x = min(dragStartPoint.x, pt.x)
            let y = min(dragStartPoint.y, pt.y)
            selectionRect = CGRect(x: x, y: y, width: dx, height: dy)

        case .moveSelection:
            let dx = pt.x - dragStartPoint.x
            let dy = pt.y - dragStartPoint.y
            var newRect = selectionBeforeDrag.offsetBy(dx: dx, dy: dy)
            // Clamp to bounds
            newRect.origin.x = max(0, min(newRect.origin.x, bounds.width - newRect.width))
            newRect.origin.y = max(0, min(newRect.origin.y, bounds.height - newRect.height))
            selectionRect = newRect

        case .resize(let handle):
            selectionRect = computeResizedRect(from: selectionBeforeDrag, handle: handle, currentPoint: pt)

        case .drawAnnotation:
            updateAnnotationDraft(to: pt)

        case .none:
            break
        }
    }

    public override func mouseUp(with event: NSEvent) {
        switch dragMode {
        case .createSelection:
            let dx = abs(event.locationInWindow.x - convert(dragStartPoint, to: nil).x)
            let dy = abs(event.locationInWindow.y - convert(dragStartPoint, to: nil).y)
            let isClick = (dx <= 4 && dy <= 4)

            if isClick, let cand = candidateWindowRect {
                // User performed a single click on a detected window -> snap to that window!
                selectionRect = cand
                hoveredWindowRect = nil
            }
            candidateWindowRect = nil

            if selectionRect.width > 15 && selectionRect.height > 15 {
                if isScrollMode {
                    delegate?.overlayDidRequestScrollCapture(rect: selectionCocoaScreenRect)
                    return
                }
                toolbar.isHidden = false
                magnifierView.isHidden = true
                updateToolbarPosition()
            } else {
                selectionRect = .zero
                toolbar.isHidden = true
            }

        case .drawAnnotation:
            if let draft = currentDraftAnnotation {
                annotations.append(draft)
                if draft.tool == .stepBadge {
                    nextBadgeNumber += 1
                }
            }
            currentDraftAnnotation = nil

        default:
            break
        }

        dragMode = .none
        needsDisplay = true
    }

    public override func mouseExited(with event: NSEvent) {
        magnifierView.isHidden = true
        hoveredWindowRect = nil
        NSCursor.arrow.set()
        needsDisplay = true
    }

    public override func rightMouseUp(with event: NSEvent) {
        // Right click exits/cancels screenshot
        delegate?.overlayDidCancel()
    }

    // MARK: - Key Events
    @discardableResult
    public func handleEscape() -> Bool {
        // 0. If currently typing in-place text editor, cancel & dismiss it
        if let editor = activeTextEditor {
            editor.cancelAndDismiss()
            return true
        }

        // 1. If currently in middle of drafting an annotation, cancel draft
        if currentDraftAnnotation != nil {
            currentDraftAnnotation = nil
            needsDisplay = true
            return true
        }

        // 2. Undo last drawn annotation if available
        if !annotations.isEmpty {
            let removed = annotations.removeLast()
            if removed.tool == .stepBadge {
                nextBadgeNumber = max(1, nextBadgeNumber - 1)
            }
            needsDisplay = true
            return true
        }

        // 3. If there is a selection box without annotations, clear selection
        if !selectionRect.isEmpty {
            selectionRect = .zero
            toolbar.isHidden = true
            magnifierView.isHidden = !UserPreferences.shared.showMagnifier
            needsDisplay = true
            return true
        }

        // 4. Nothing left to undo/clear, return false to terminate/cancel overlay
        return false
    }

    public override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // Escape: Cascading undo then terminate
            if !handleEscape() {
                delegate?.overlayDidCancel()
            }

        case 36: // Enter / Return
            finishAndCopy()

        case 123: // Left Arrow: Fine-tune canvas width
            if !selectionRect.isEmpty {
                let delta: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
                let newW = max(20, selectionRect.width - delta)
                selectionRect = CGRect(origin: selectionRect.origin, size: CGSize(width: newW, height: selectionRect.height))
                return
            }
        case 124: // Right Arrow: Fine-tune canvas width
            if !selectionRect.isEmpty {
                let delta: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
                let newW = min(bounds.width - selectionRect.minX, selectionRect.width + delta)
                selectionRect = CGRect(origin: selectionRect.origin, size: CGSize(width: newW, height: selectionRect.height))
                return
            }
        case 125: // Down Arrow: Fine-tune canvas height
            if !selectionRect.isEmpty {
                let delta: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
                let newH = min(bounds.height - selectionRect.minY, selectionRect.height + delta)
                selectionRect = CGRect(origin: selectionRect.origin, size: CGSize(width: selectionRect.width, height: newH))
                return
            }
        case 126: // Up Arrow: Fine-tune canvas height
            if !selectionRect.isEmpty {
                let delta: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
                let newH = max(20, selectionRect.height - delta)
                selectionRect = CGRect(origin: selectionRect.origin, size: CGSize(width: selectionRect.width, height: newH))
                return
            }

        case 8: // 'C' key -> Copy color under crosshair
            if selectionRect.isEmpty && !magnifierView.isHidden {
                let hex = magnifierView.currentHexColor
                PasteboardHelper.copyString(hex)
                SoundManager.shared.playCameraShutterSound()
                NotificationHelper.notifyScreenshotSaved(url: URL(string: "color://\(hex)")!)
                return
            }

        case 14: // 'E' key -> Trigger studio beautify for selected region
            if !selectionRect.isEmpty {
                toolbarDidClickStudio()
                return
            }

        case 15: // 'R' key -> Trigger recording for selected region
            if !selectionRect.isEmpty {
                toolbarDidClickRecord()
                return
            }

        case 18, 19, 20, 22, 26, 28: // Physical number keys 1, 2, 3, 6, 7, 8
            let numbers: [UInt16: String] = [18: "1", 19: "2", 20: "3", 22: "6", 26: "7", 28: "8"]
            let num = numbers[event.keyCode]
            if let tool = AnnotationTool.allCases.first(where: { $0.shortcutNumber == num }) {
                toolbar.selectTool(tool)
            }

        case 6 where event.modifierFlags.contains(.command): // Cmd+Z
            toolbarDidClickUndo()

        case 1 where event.modifierFlags.contains(.command): // Cmd+S
            toolbarDidClickSave()

        default:
            super.keyDown(with: event)
        }
    }

    public override var acceptsFirstResponder: Bool { true }

    // MARK: - Annotations Handling
    private func startAnnotationDraft(at point: CGPoint) {
        let tool = toolbar.currentTool
        let color = toolbar.currentColor

        if tool == .text {
            promptForTextInput(at: point)
            return
        }

        currentDraftAnnotation = AnnotationItem(
            tool: tool,
            startPoint: point,
            endPoint: point,
            color: color,
            badgeNumber: nextBadgeNumber
        )
        needsDisplay = true
    }

    private func updateAnnotationDraft(to point: CGPoint) {
        guard var draft = currentDraftAnnotation else { return }
        draft.endPoint = point
        currentDraftAnnotation = draft
        needsDisplay = true
    }

    private func promptForTextInput(at point: CGPoint) {
        // Dismiss any existing active text editor first
        activeTextEditor?.commitAndDismiss()

        let editor = InPlaceTextEditor(
            origin: point,
            color: toolbar.currentColor,
            maxBounds: selectionRect
        )
        editor.editorDelegate = self
        addSubview(editor)
        self.activeTextEditor = editor
    }

    // MARK: - InPlaceTextEditorDelegate
    public func textEditorDidCommit(text: String, at point: CGPoint) {
        let item = AnnotationItem(
            tool: .text,
            startPoint: point,
            endPoint: point,
            color: toolbar.currentColor,
            text: text,
            fontSize: 16.0
        )
        annotations.append(item)
        activeTextEditor = nil
        needsDisplay = true
    }

    public func textEditorDidCancel() {
        activeTextEditor = nil
        needsDisplay = true
    }

    // MARK: - Toolbar Positioning & Helpers
    private func updateToolbarPosition() {
        toolbar.hideTooltip(animated: false)
        guard !selectionRect.isEmpty else {
            toolbar.isHidden = true
            return
        }

        let fittingSize = toolbar.fittingSize
        let toolbarWidth = max(fittingSize.width, 1)
        let toolbarHeight: CGFloat = 38
        toolbar.frame.size = CGSize(width: toolbarWidth, height: toolbarHeight)

        var tx = selectionRect.midX - toolbarWidth / 2

        let isFullScreen = selectionRect.height >= bounds.height - 40
        let isLargeNearTop = (selectionRect.minY < 80 && selectionRect.height > bounds.height * 0.6)

        var ty: CGFloat
        if isFullScreen || isLargeNearTop {
            // 用户明确需求：当用户选择全屏窗口时，状态栏置于底部往上 20% 的黄金操作位置，彻底避让 MacBook 顶部刘海屏遮挡
            ty = bounds.height * 0.8 - toolbarHeight / 2
        } else {
            // 局部选区：优先放在选区正下方
            ty = selectionRect.maxY + 12
            // 若下方超出屏幕底部
            if ty + toolbarHeight > bounds.height - 10 {
                // 翻转到选区上方
                ty = selectionRect.minY - toolbarHeight - 12
                // 若上方进入了 MacBook 顶部刘海屏危险区 (< 50)，下移至选区内部底部安全区，坚决不被刘海遮挡
                if ty < 50 {
                    ty = max(50, selectionRect.maxY - toolbarHeight - 16)
                }
            }
        }

        tx = max(16, min(tx, bounds.width - toolbarWidth - 16))
        ty = max(50, min(ty, bounds.height - toolbarHeight - 16))

        toolbar.frame.origin = CGPoint(x: tx, y: ty)
        toolbar.isHidden = false
    }

    private func updateMagnifier(at point: CGPoint) {
        guard UserPreferences.shared.showMagnifier && selectionRect.isEmpty else {
            magnifierView.isHidden = true
            return
        }
        magnifierView.screenScale = window?.backingScaleFactor ?? 2.0
        magnifierView.isHidden = false
        magnifierView.currentPoint = point

        var mx = point.x + 20
        var my = point.y + 20
        if mx + magnifierView.bounds.width > bounds.width - 10 {
            mx = point.x - magnifierView.bounds.width - 20
        }
        if my + magnifierView.bounds.height > bounds.height - 10 {
            my = point.y - magnifierView.bounds.height - 20
        }
        magnifierView.frame.origin = CGPoint(x: mx, y: my)
    }

    private func handleAtPoint(_ pt: CGPoint) -> HandlePosition? {
        let r = selectionRect
        let tolerance: CGFloat = 10.0

        if abs(pt.x - r.minX) < tolerance && abs(pt.y - r.minY) < tolerance { return .topLeft }
        if abs(pt.x - r.midX) < tolerance && abs(pt.y - r.minY) < tolerance { return .topCenter }
        if abs(pt.x - r.maxX) < tolerance && abs(pt.y - r.minY) < tolerance { return .topRight }
        if abs(pt.x - r.minX) < tolerance && abs(pt.y - r.midY) < tolerance { return .middleLeft }
        if abs(pt.x - r.maxX) < tolerance && abs(pt.y - r.midY) < tolerance { return .middleRight }
        if abs(pt.x - r.minX) < tolerance && abs(pt.y - r.maxY) < tolerance { return .bottomLeft }
        if abs(pt.x - r.midX) < tolerance && abs(pt.y - r.maxY) < tolerance { return .bottomCenter }
        if abs(pt.x - r.maxX) < tolerance && abs(pt.y - r.maxY) < tolerance { return .bottomRight }

        return nil
    }

    private func computeResizedRect(from initial: CGRect, handle: HandlePosition, currentPoint: CGPoint) -> CGRect {
        var minX = initial.minX
        var maxX = initial.maxX
        var minY = initial.minY
        var maxY = initial.maxY

        switch handle {
        case .topLeft:
            minX = min(currentPoint.x, maxX - 10)
            minY = min(currentPoint.y, maxY - 10)
        case .topCenter:
            minY = min(currentPoint.y, maxY - 10)
        case .topRight:
            maxX = max(currentPoint.x, minX + 10)
            minY = min(currentPoint.y, maxY - 10)
        case .middleLeft:
            minX = min(currentPoint.x, maxX - 10)
        case .middleRight:
            maxX = max(currentPoint.x, minX + 10)
        case .bottomLeft:
            minX = min(currentPoint.x, maxX - 10)
            maxY = max(currentPoint.y, minY + 10)
        case .bottomCenter:
            maxY = max(currentPoint.y, minY + 10)
        case .bottomRight:
            maxX = max(currentPoint.x, minX + 10)
            maxY = max(currentPoint.y, minY + 10)
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    public func generateRenderedImage() -> CGImage? {
        guard let screenImg = screenImage, !selectionRect.isEmpty else { return nil }

        let scale = window?.backingScaleFactor ?? 2.0
        let pixelRect = CGRect(
            x: selectionRect.origin.x * scale,
            y: selectionRect.origin.y * scale,
            width: selectionRect.width * scale,
            height: selectionRect.height * scale
        )

        // Crop base image upright
        guard let cropped = screenImg.cropping(to: pixelRect) else { return nil }

        if annotations.isEmpty {
            return cropped
        }

        let resultImage = NSImage(size: NSSize(width: selectionRect.width, height: selectionRect.height), flipped: true) { [weak self] rect in
            guard let self = self else { return false }
            NSImage(cgImage: cropped, size: rect.size).draw(in: rect)

            if let ctx = NSGraphicsContext.current?.cgContext {
                ctx.saveGState()
                ctx.translateBy(x: -self.selectionRect.origin.x, y: -self.selectionRect.origin.y)
                for item in self.annotations {
                    AnnotationRenderer.render(item: item, in: ctx, baseImage: screenImg, scale: scale)
                }
                ctx.restoreGState()
            }
            return true
        }

        return resultImage.cgImage(forProposedRect: nil, context: nil, hints: nil) ?? cropped
    }

    private func finishAndCopy() {
        guard let finalImg = generateRenderedImage() else { return }
        SoundManager.shared.playCameraShutterSound()

        // 1. 默认写到系统剪贴板
        _ = PasteboardHelper.copyImage(finalImg, alsoAsFile: false)

        // 2. 只有点“完成”时，才自动保存到预设设置的目录（默认 ~/Downloads）
        let saveDir = UserPreferences.shared.saveDirectoryURL
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH.mm.ss"
        let dateStr = formatter.string(from: Date())
        let ext = UserPreferences.shared.screenshotFormat.lowercased() == "jpeg" ? "jpg" : "png"
        let fileURL = saveDir.appendingPathComponent("cduyzhShot_\(dateStr).\(ext)")

        let rep = NSBitmapImageRep(cgImage: finalImg)
        let fileType: NSBitmapImageRep.FileType = ext == "jpg" ? .jpeg : .png
        if let data = rep.representation(using: fileType, properties: [:]) {
            try? data.write(to: fileURL)
            NotificationHelper.notifyScreenshotSaved(url: fileURL)
        }

        // 3. 浮窗提示剪贴板与保存，并提供钉在屏幕上的贴图入口
        FloatingThumbnailWindow.shared.show(
            image: finalImg,
            fileURL: fileURL,
            message: "已写入剪贴板并自动保存至下载目录"
        )

        delegate?.overlayDidFinish(image: finalImg, rect: selectionRect)
    }

    // MARK: - ScreenshotToolbarDelegate
    public func toolbarDidSelectTool(_ tool: AnnotationTool) {}
    public func toolbarDidSelectColor(_ color: NSColor) {}

    public func toolbarDidClickPin() {
        guard let finalImg = generateRenderedImage() else { return }
        SoundManager.shared.playCameraShutterSound()
        delegate?.overlayDidRequestPin(image: finalImg, rect: selectionCocoaScreenRect)
    }

    public func toolbarDidClickStudio() {
        guard let finalImg = generateRenderedImage() else { return }
        delegate?.overlayDidRequestStudio(image: finalImg, rect: selectionCocoaScreenRect)
    }

    public func toolbarDidClickScrollCapture() {
        delegate?.overlayDidRequestScrollCapture(rect: selectionCocoaScreenRect)
    }

    public func toolbarDidClickRecord() {
        guard !selectionRect.isEmpty else { return }
        delegate?.overlayDidRequestRecord(rect: selectionCocoaScreenRect)
    }

    public func toolbarDidClickUndo() {
        if !annotations.isEmpty {
            let removed = annotations.removeLast()
            if removed.tool == .stepBadge {
                nextBadgeNumber = max(1, nextBadgeNumber - 1)
            }
            needsDisplay = true
        }
    }

    public func toolbarDidClickSave() {
        // 用户点击下载保存图标后，绝不自动保存，而是弹出 NSSavePanel 让用户自由选择保存目录和文件名
        guard let finalImg = generateRenderedImage() else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH.mm.ss"
        let dateStr = formatter.string(from: Date())
        let ext = UserPreferences.shared.screenshotFormat.lowercased() == "jpeg" ? "jpg" : "png"

        let panel = NSSavePanel()
        panel.title = "另存为截图"
        panel.nameFieldStringValue = "cduyzhShot_\(dateStr).\(ext)"
        panel.directoryURL = UserPreferences.shared.saveDirectoryURL
        panel.canCreateDirectories = true

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self = self else { return }
            let rep = NSBitmapImageRep(cgImage: finalImg)
            let isJpg = url.pathExtension.lowercased() == "jpg" || url.pathExtension.lowercased() == "jpeg"
            let fileType: NSBitmapImageRep.FileType = isJpg ? .jpeg : .png
            if let data = rep.representation(using: fileType, properties: [:]) {
                try? data.write(to: url)
                SoundManager.shared.playCameraShutterSound()
                NotificationHelper.notifyScreenshotSaved(url: url)
                FloatingThumbnailWindow.shared.show(image: finalImg, fileURL: url, message: "已成功另存为文件")
                self.delegate?.overlayDidFinish(image: finalImg, rect: self.selectionRect)
            }
        }
    }

    public func toolbarDidClickCopy() {
        finishAndCopy()
    }

    public func toolbarDidClickCancel() {
        delegate?.overlayDidCancel()
    }
}
