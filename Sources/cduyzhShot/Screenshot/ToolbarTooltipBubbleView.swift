import AppKit

public struct ToolbarTooltipItem: Equatable {
    public let title: String
    public let shortcut: String?
    public let detail: String?

    public init(title: String, shortcut: String? = nil, detail: String? = nil) {
        self.title = title
        self.shortcut = shortcut
        self.detail = detail
    }
}

/// 与系统深色 HUD 保持一致的轻量快捷键提示。
public final class ToolbarTooltipBubbleView: NSView {
    public enum ArrowDirection {
        case down // 气泡位于按钮上方，箭头朝下指向按钮
        case up   // 气泡位于按钮下方，箭头朝上指向按钮
    }

    public private(set) var currentItem: ToolbarTooltipItem?
    public private(set) var arrowDirection: ArrowDirection = .down
    private var arrowOffset: CGFloat = 0 // 箭头相对于气泡中心的水平偏移

    private var hideWorkItem: DispatchWorkItem?
    private var presentationRevision = 0

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.24
        layer?.shadowRadius = 5.0
        layer?.shadowOffset = CGSize(width: 0, height: -2)
        isHidden = true
        setAccessibilityElement(false)
    }

    public override var isFlipped: Bool {
        return false // 使用传统坐标系方便计算箭头与几何图形
    }

    // 鼠标点击事件完全穿透，不拦截任何截图或选区交互
    public override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    // MARK: - 尺寸测量
    public static func calculateSize(for item: ToolbarTooltipItem) -> CGSize {
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium)
        ]
        let titleSize = (item.title as NSString).size(withAttributes: titleAttrs)

        var totalWidth: CGFloat = 8 + titleSize.width // 左边距 + 标题宽

        if let shortcut = item.shortcut, !shortcut.isEmpty {
            let scAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 9.5, weight: .medium)
            ]
            let scSize = (shortcut as NSString).size(withAttributes: scAttrs)
            let badgeWidth = scSize.width + 8 // 左右内边距
            totalWidth += 6 + badgeWidth // 间距 + 徽章宽
        }

        totalWidth += 8 // 右边距
        let bubbleHeight: CGFloat = 22 + 4 // 气泡主体 22px + 尖角 4px = 26px
        return CGSize(width: ceil(max(totalWidth, 36)), height: bubbleHeight)
    }

    // MARK: - 显示与更新
    public func show(
        item: ToolbarTooltipItem,
        for button: NSView,
        in container: NSView
    ) {
        presentationRevision += 1
        hideWorkItem?.cancel()
        hideWorkItem = nil

        let size = ToolbarTooltipBubbleView.calculateSize(for: item)
        let btnRect = button.convert(button.bounds, to: container)

        // 判断放在按钮上方还是下方（如果在 container 顶部空间少于 32px，翻转到下方）
        let arrowDir: ArrowDirection
        let bubbleY: CGFloat

        if container.isFlipped {
            // container y=0 在顶部
            if btnRect.minY - size.height - 6 >= 0 {
                // 上方有充足空间：显示在按钮上方，箭头朝下
                arrowDir = .down
                bubbleY = btnRect.minY - size.height - 6
            } else {
                // 上方空间不足：翻转到按钮下方，箭头朝上
                arrowDir = .up
                bubbleY = btnRect.maxY + 6
            }
        } else {
            // container y=0 在底部
            if btnRect.maxY + size.height + 6 <= container.bounds.height {
                arrowDir = .down
                bubbleY = btnRect.maxY + 6
            } else {
                arrowDir = .up
                bubbleY = btnRect.minY - size.height - 6
            }
        }

        // 计算居中 X，并进行左右安全边界限制 (至少留 8px)
        let targetCenterX = btnRect.midX
        var bubbleX = targetCenterX - size.width / 2
        let minX = container.bounds.minX + 8
        let maxX = max(minX, container.bounds.maxX - size.width - 8)
        bubbleX = max(minX, min(bubbleX, maxX))

        // 箭头指向按钮中心，计算相对于气泡中心的位置偏移
        let actualBubbleCenterX = bubbleX + size.width / 2
        let offset = targetCenterX - actualBubbleCenterX
        let maxAllowedOffset = (size.width / 2) - 8
        let clampedOffset = max(-maxAllowedOffset, min(offset, maxAllowedOffset))

        let clampedY = max(container.bounds.minY + 4, min(bubbleY, container.bounds.maxY - size.height - 4))
        let targetFrame = CGRect(x: bubbleX, y: clampedY, width: size.width, height: size.height)

        let wasHidden = isHidden || alphaValue < 0.05
        self.currentItem = item
        self.arrowDirection = arrowDir
        self.arrowOffset = clampedOffset
        self.needsDisplay = true

        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            frame = targetFrame
            alphaValue = 1
            isHidden = false
        } else if wasHidden {
            // 首次展示：极轻微从下至上浮现 + 0.12s 极速淡入
            self.frame = targetFrame.offsetBy(dx: 0, dy: (container.isFlipped ? 3 : -3))
            self.alphaValue = 0
            self.isHidden = false

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.animator().frame = targetFrame
                self.animator().alphaValue = 1.0
            }
        } else {
            // 快速划过切换：平滑滑动过渡到新按钮上方，无闪烁
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.10
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.animator().frame = targetFrame
                self.animator().alphaValue = 1.0
            }
        }
    }

    public func hide(animated: Bool = true) {
        presentationRevision += 1
        let revision = presentationRevision
        hideWorkItem?.cancel()
        hideWorkItem = nil

        if !animated || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            alphaValue = 0
            isHidden = true
            currentItem = nil
            return
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self, self.presentationRevision == revision else { return }
            self.hideWorkItem = nil
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.10
                self.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                guard let self, self.presentationRevision == revision else { return }
                self.isHidden = true
                self.currentItem = nil
            })
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
    }

    // MARK: - 绘制气泡与快捷键
    public override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext, let item = currentItem else { return }

        ctx.saveGState()

        let arrowWidth: CGFloat = 8.0
        let arrowHeight: CGFloat = 4.0
        let cornerRadius: CGFloat = 6.0

        let bodyRect: CGRect
        let tipPoint: CGPoint
        let arrowBaseLeft: CGPoint
        let arrowBaseRight: CGPoint

        let centerX = bounds.midX + arrowOffset

        if arrowDirection == .down {
            // 箭头在底部指向下，主体在上方
            bodyRect = CGRect(x: 0.5, y: arrowHeight + 0.5, width: bounds.width - 1.0, height: bounds.height - arrowHeight - 1.0)
            tipPoint = CGPoint(x: centerX, y: 0.5)
            arrowBaseLeft = CGPoint(x: centerX - arrowWidth / 2, y: arrowHeight + 0.5)
            arrowBaseRight = CGPoint(x: centerX + arrowWidth / 2, y: arrowHeight + 0.5)
        } else {
            // 箭头在顶部指向上，主体在下方
            bodyRect = CGRect(x: 0.5, y: 0.5, width: bounds.width - 1.0, height: bounds.height - arrowHeight - 1.0)
            tipPoint = CGPoint(x: centerX, y: bounds.height - 0.5)
            arrowBaseLeft = CGPoint(x: centerX - arrowWidth / 2, y: bounds.height - arrowHeight - 0.5)
            arrowBaseRight = CGPoint(x: centerX + arrowWidth / 2, y: bounds.height - arrowHeight - 0.5)
        }

        // 构建带小三角的复合路径
        let path = CGMutablePath()
        if arrowDirection == .down {
            path.move(to: CGPoint(x: bodyRect.minX + cornerRadius, y: bodyRect.minY))
            // 底部边框走到底部箭头
            path.addLine(to: arrowBaseLeft)
            path.addLine(to: tipPoint)
            path.addLine(to: arrowBaseRight)
            path.addLine(to: CGPoint(x: bodyRect.maxX - cornerRadius, y: bodyRect.minY))
            path.addArc(tangent1End: CGPoint(x: bodyRect.maxX, y: bodyRect.minY), tangent2End: CGPoint(x: bodyRect.maxX, y: bodyRect.maxY), radius: cornerRadius)
            path.addArc(tangent1End: CGPoint(x: bodyRect.maxX, y: bodyRect.maxY), tangent2End: CGPoint(x: bodyRect.minX, y: bodyRect.maxY), radius: cornerRadius)
            path.addArc(tangent1End: CGPoint(x: bodyRect.minX, y: bodyRect.maxY), tangent2End: CGPoint(x: bodyRect.minX, y: bodyRect.minY), radius: cornerRadius)
            path.addArc(tangent1End: CGPoint(x: bodyRect.minX, y: bodyRect.minY), tangent2End: arrowBaseLeft, radius: cornerRadius)
            path.closeSubpath()
        } else {
            path.move(to: CGPoint(x: bodyRect.minX, y: bodyRect.minY + cornerRadius))
            path.addArc(tangent1End: CGPoint(x: bodyRect.minX, y: bodyRect.maxY), tangent2End: CGPoint(x: bodyRect.maxX, y: bodyRect.maxY), radius: cornerRadius)
            // 顶部边框走顶部箭头
            path.addLine(to: arrowBaseLeft)
            path.addLine(to: tipPoint)
            path.addLine(to: arrowBaseRight)
            path.addArc(tangent1End: CGPoint(x: bodyRect.maxX, y: bodyRect.maxY), tangent2End: CGPoint(x: bodyRect.maxX, y: bodyRect.minY), radius: cornerRadius)
            path.addArc(tangent1End: CGPoint(x: bodyRect.maxX, y: bodyRect.minY), tangent2End: CGPoint(x: bodyRect.minX, y: bodyRect.minY), radius: cornerRadius)
            path.addArc(tangent1End: CGPoint(x: bodyRect.minX, y: bodyRect.minY), tangent2End: CGPoint(x: bodyRect.minX, y: bodyRect.maxY), radius: cornerRadius)
            path.closeSubpath()
        }

        // 深色背景在截图画面上保持稳定对比。
        ctx.addPath(path)
        ctx.setFillColor(NSColor(calibratedWhite: 0.13, alpha: 0.97).cgColor)
        ctx.fillPath()

        // 细边缘只用于分离明亮的底图。
        ctx.addPath(path)
        ctx.setStrokeColor(NSColor(white: 1.0, alpha: 0.14).cgColor)
        ctx.setLineWidth(0.5)
        ctx.strokePath()

        // 3. 绘制文字与快捷键胶囊徽章
        let textY: CGFloat = (arrowDirection == .down) ? (arrowHeight + 4) : 4

        var curX: CGFloat = 8

        // 标题文字
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let titleSize = (item.title as NSString).size(withAttributes: titleAttrs)
        let titleRect = CGRect(x: curX, y: textY, width: titleSize.width, height: 14)
        (item.title as NSString).draw(in: titleRect, withAttributes: titleAttrs)
        curX += titleSize.width

        // 快捷键徽章胶囊
        if let shortcut = item.shortcut, !shortcut.isEmpty {
            curX += 6
            let scAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 9.5, weight: .medium),
                .foregroundColor: NSColor(white: 0.92, alpha: 1.0)
            ]
            let scSize = (shortcut as NSString).size(withAttributes: scAttrs)
            let badgeWidth = scSize.width + 8
            let badgeHeight: CGFloat = 14
            let badgeRect = CGRect(x: curX, y: textY - 0.5, width: badgeWidth, height: badgeHeight)

            let badgePath = CGPath(roundedRect: badgeRect, cornerWidth: 3.5, cornerHeight: 3.5, transform: nil)
            ctx.addPath(badgePath)
            ctx.setFillColor(NSColor(white: 1.0, alpha: 0.16).cgColor)
            ctx.fillPath()

            let scTextRect = CGRect(x: curX + 4, y: textY, width: scSize.width, height: 14)
            (shortcut as NSString).draw(in: scTextRect, withAttributes: scAttrs)
        }

        ctx.restoreGState()
    }
}
