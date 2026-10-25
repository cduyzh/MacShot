import AppKit

public protocol InPlaceTextEditorDelegate: AnyObject {
    func textEditorDidCommit(text: String, at point: CGPoint)
    func textEditorDidCancel()
}

/// Canvas in-place live text editor inspired by Tencent Snip's ShadowTextView
public final class InPlaceTextEditor: NSTextField, NSTextFieldDelegate {
    public weak var editorDelegate: InPlaceTextEditorDelegate?
    private let originPoint: CGPoint
    private let maxCanvasBounds: CGRect
    private var isCommitting = false

    public init(origin: CGPoint, color: NSColor, maxBounds: CGRect) {
        self.originPoint = origin
        self.maxCanvasBounds = maxBounds
        super.init(frame: NSRect(x: origin.x, y: origin.y, width: 140, height: 32))

        self.delegate = self
        setupEditor(color: color)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupEditor(color: NSColor) {
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.backgroundColor = NSColor(calibratedWhite: 0.10, alpha: 0.88).cgColor
        layer?.borderColor = NSColor(white: 1.0, alpha: 0.4).cgColor
        layer?.borderWidth = 1.0
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.4
        layer?.shadowRadius = 4
        layer?.shadowOffset = CGSize(width: 0, height: 1)

        isBordered = false
        drawsBackground = false
        focusRingType = .none
        isEditable = true
        isSelectable = true

        font = NSFont.systemFont(ofSize: 16.0, weight: .bold)
        textColor = color
        placeholderString = "输入文字..."

        // Adjust initial frame based on text
        updateFrameForContent()
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            becomeFirstResponder()
        }
    }

    private func updateFrameForContent() {
        let text = stringValue.isEmpty ? (placeholderString ?? "输入文字...") : stringValue
        let font = self.font ?? NSFont.systemFont(ofSize: 16.0, weight: .bold)
        let attr: [NSAttributedString.Key: Any] = [.font: font]
        let size = (text as NSString).size(withAttributes: attr)

        let targetW = max(120, size.width + 24)
        let targetH: CGFloat = 32

        // Clamp inside canvas bounds
        let maxX = maxCanvasBounds.maxX > 0 ? maxCanvasBounds.maxX : bounds.width
        let maxY = maxCanvasBounds.maxY > 0 ? maxCanvasBounds.maxY : bounds.height

        let clampedX = min(originPoint.x, maxX - targetW)
        let clampedY = min(originPoint.y, maxY - targetH)

        self.frame = NSRect(x: max(maxCanvasBounds.minX, clampedX), y: max(maxCanvasBounds.minY, clampedY), width: targetW, height: targetH)
    }

    // MARK: - NSTextFieldDelegate
    public func controlTextDidChange(_ obj: Notification) {
        updateFrameForContent()
    }

    public func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            // Return / Enter committed
            commitAndDismiss()
            return true
        } else if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            // Escape pressed
            cancelAndDismiss()
            return true
        }
        return false
    }

    public func controlTextDidEndEditing(_ obj: Notification) {
        if !isCommitting {
            commitAndDismiss()
        }
    }

    public func commitAndDismiss() {
        guard !isCommitting else { return }
        isCommitting = true

        let text = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            editorDelegate?.textEditorDidCommit(text: text, at: frame.origin)
        } else {
            editorDelegate?.textEditorDidCancel()
        }
        removeFromSuperview()
    }

    public func cancelAndDismiss() {
        guard !isCommitting else { return }
        isCommitting = true
        editorDelegate?.textEditorDidCancel()
        removeFromSuperview()
    }
}
