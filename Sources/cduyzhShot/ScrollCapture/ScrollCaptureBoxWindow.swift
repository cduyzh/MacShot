import AppKit

public final class ScrollCaptureBoxWindow: NSPanel {
    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }

    public init(rect: CGRect) {
        // 将外框向外扩大 3 像素，确保线框完全在 captureRect 外侧，避免被 ScreenCapture 截入画面
        let outerRect = rect.insetBy(dx: -3, dy: -3)
        super.init(
            contentRect: outerRect,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        // 这是纯装饰边框，不应作为空弹窗出现在辅助功能窗口列表中。
        setAccessibilityElement(false)
        isFloatingPanel = true
        level = .floating
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true // 关键：所有滚轮与触控手势 100% 穿透至底层目标应用
        collectionBehavior = [.canJoinAllSpaces, .transient]

        let container = BoxOutlineView(frame: NSRect(origin: .zero, size: outerRect.size))
        container.setAccessibilityElement(false)
        contentView = container
    }
}

private final class BoxOutlineView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        // 绘制外发光双色边框
        let borderPath = CGPath(roundedRect: bounds.insetBy(dx: 1.5, dy: 1.5), cornerWidth: 5, cornerHeight: 5, transform: nil)
        ctx.addPath(borderPath)
        ctx.setStrokeColor(NSColor.systemIndigo.withAlphaComponent(0.9).cgColor)
        ctx.setLineWidth(2.5)
        ctx.setLineDash(phase: 0, lengths: [8, 4])
        ctx.strokePath()
        ctx.restoreGState()
    }
}
