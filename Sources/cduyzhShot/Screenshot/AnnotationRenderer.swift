import AppKit
import CoreGraphics
import CoreImage

public final class AnnotationRenderer {
    public static func render(
        item: AnnotationItem,
        in context: CGContext,
        baseImage: CGImage? = nil,
        scale: CGFloat = 1.0
    ) {
        context.saveGState()

        switch item.tool {
        case .rect:
            renderRect(item: item, in: context)
        case .ellipse:
            renderEllipse(item: item, in: context)
        case .arrow:
            renderArrow(item: item, in: context)
        case .line:
            renderLine(item: item, in: context)
        case .text:
            renderText(item: item, in: context)
        case .stepBadge:
            renderStepBadge(item: item, in: context)
        case .mosaic:
            renderMosaic(item: item, in: context, baseImage: baseImage, scale: scale)
        case .select:
            break
        }

        context.restoreGState()
    }

    private static func renderRect(item: AnnotationItem, in context: CGContext) {
        let rect = item.boundingRect
        let path = CGPath(roundedRect: rect, cornerWidth: 4, cornerHeight: 4, transform: nil)
        context.addPath(path)
        if item.isFilled {
            context.setFillColor(item.color.cgColor)
            context.fillPath()
        } else {
            context.setStrokeColor(item.color.cgColor)
            context.setLineWidth(item.lineWidth)
            context.setLineJoin(.round)
            context.strokePath()
        }
    }

    private static func renderEllipse(item: AnnotationItem, in context: CGContext) {
        let rect = item.boundingRect
        context.addEllipse(in: rect)
        if item.isFilled {
            context.setFillColor(item.color.cgColor)
            context.fillPath()
        } else {
            context.setStrokeColor(item.color.cgColor)
            context.setLineWidth(item.lineWidth)
            context.strokePath()
        }
    }

    private static func renderLine(item: AnnotationItem, in context: CGContext) {
        context.setStrokeColor(item.color.cgColor)
        context.setLineWidth(item.lineWidth)
        context.setLineCap(.round)
        context.beginPath()
        context.move(to: item.startPoint)
        context.addLine(to: item.endPoint)
        context.strokePath()
    }

    private static func renderArrow(item: AnnotationItem, in context: CGContext) {
        let start = item.startPoint
        let end = item.endPoint
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length > 4 else { return }

        let angle = atan2(dy, dx)
        let arrowHeadLength = max(item.lineWidth * 4, 16.0)
        let arrowHeadWidth = max(item.lineWidth * 2.5, 12.0)

        // Line body
        context.setStrokeColor(item.color.cgColor)
        context.setLineWidth(item.lineWidth)
        context.setLineCap(.round)

        let bodyEnd = CGPoint(
            x: end.x - arrowHeadLength * 0.7 * cos(angle),
            y: end.y - arrowHeadLength * 0.7 * sin(angle)
        )
        context.beginPath()
        context.move(to: start)
        context.addLine(to: bodyEnd)
        context.strokePath()

        // Arrow head triangle
        context.setFillColor(item.color.cgColor)
        let p1 = end
        let p2 = CGPoint(
            x: end.x - arrowHeadLength * cos(angle) + arrowHeadWidth * sin(angle),
            y: end.y - arrowHeadLength * sin(angle) - arrowHeadWidth * cos(angle)
        )
        let p3 = CGPoint(
            x: end.x - arrowHeadLength * cos(angle) - arrowHeadWidth * sin(angle),
            y: end.y - arrowHeadLength * sin(angle) + arrowHeadWidth * cos(angle)
        )

        let headPath = CGMutablePath()
        headPath.move(to: p1)
        headPath.addLine(to: p2)
        headPath.addLine(to: p3)
        headPath.closeSubpath()

        context.addPath(headPath)
        context.fillPath()
    }

    private static func renderText(item: AnnotationItem, in context: CGContext) {
        guard !item.text.isEmpty else { return }
        let text = item.text as NSString
        let font = NSFont.systemFont(ofSize: item.fontSize, weight: .bold)

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: item.color
        ]

        let size = text.size(withAttributes: attributes)
        let padding: CGFloat = 6.0
        let bgRect = CGRect(
            x: item.startPoint.x - padding,
            y: item.startPoint.y - padding,
            width: size.width + padding * 2,
            height: size.height + padding * 2
        )

        // Draw translucent dark background pill
        let bgPath = CGPath(roundedRect: bgRect, cornerWidth: 5, cornerHeight: 5, transform: nil)
        context.addPath(bgPath)
        context.setFillColor(NSColor(white: 0.12, alpha: 0.85).cgColor)
        context.fillPath()

        // Border around text pill
        context.addPath(bgPath)
        context.setStrokeColor(NSColor(white: 0.35, alpha: 0.5).cgColor)
        context.setLineWidth(1.0)
        context.strokePath()

        // Render text via NSGraphicsContext with flipped: true (matching overlay coordinate system)
        NSGraphicsContext.saveGraphicsState()
        let nsContext = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.current = nsContext
        text.draw(at: item.startPoint, withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func renderStepBadge(item: AnnotationItem, in context: CGContext) {
        let radius: CGFloat = max(item.lineWidth * 3.5, 14.0)
        let center = item.startPoint
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)

        // Badge circle with shadow
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: 1.5), blur: 3, color: NSColor.black.withAlphaComponent(0.45).cgColor)
        context.setFillColor(item.color.cgColor)
        context.fillEllipse(in: rect)
        context.restoreGState()

        // White border
        context.saveGState()
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(2.0)
        context.strokeEllipse(in: rect)
        context.restoreGState()

        // Badge number string (drawn upright via flipped: true)
        let str = "\(item.badgeNumber)" as NSString
        let font = NSFont.boldSystemFont(ofSize: radius * 1.15)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]
        let strSize = str.size(withAttributes: attrs)
        let strOrigin = CGPoint(x: center.x - strSize.width / 2, y: center.y - strSize.height / 2)

        NSGraphicsContext.saveGraphicsState()
        let nsContext = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.current = nsContext
        str.draw(at: strOrigin, withAttributes: attrs)
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func renderMosaic(item: AnnotationItem, in context: CGContext, baseImage: CGImage?, scale: CGFloat = 2.0) {
        let rect = item.boundingRect
        guard rect.width > 2 && rect.height > 2 else { return }

        context.saveGState()

        // Clip to the selected rounded rectangle
        let clipPath = CGPath(roundedRect: rect, cornerWidth: 3, cornerHeight: 3, transform: nil)
        context.addPath(clipPath)
        context.clip()

        var didDrawPixelatedImage = false

        if let base = baseImage {
            let actualScale: CGFloat = scale > 0 ? scale : (CGFloat(base.width) / max(1.0, NSScreen.main?.frame.width ?? 1920))
            let pixelRect = CGRect(
                x: rect.origin.x * actualScale,
                y: rect.origin.y * actualScale,
                width: rect.width * actualScale,
                height: rect.height * actualScale
            )

            // Crop corresponding base region
            if let cropped = base.cropping(to: pixelRect) {
                // Downsample to create chunky pixel blocks (block size ~12pt)
                let blockSize: CGFloat = 12.0 * actualScale
                let miniW = max(1, Int(pixelRect.width / blockSize))
                let miniH = max(1, Int(pixelRect.height / blockSize))

                let colorSpace = CGColorSpaceCreateDeviceRGB()
                if let miniCtx = CGContext(
                    data: nil,
                    width: miniW,
                    height: miniH,
                    bitsPerComponent: 8,
                    bytesPerRow: 0,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) {
                    miniCtx.interpolationQuality = .medium
                    miniCtx.draw(cropped, in: CGRect(x: 0, y: 0, width: miniW, height: miniH))

                    if let miniCG = miniCtx.makeImage() {
                        // Draw back into NSGraphicsContext upright with nearest-neighbor interpolation
                        NSGraphicsContext.saveGraphicsState()
                        let nsContext = NSGraphicsContext(cgContext: context, flipped: true)
                        NSGraphicsContext.current = nsContext
                        NSGraphicsContext.current?.imageInterpolation = .none

                        let nsImg = NSImage(cgImage: miniCG, size: rect.size)
                        nsImg.draw(in: rect)
                        NSGraphicsContext.restoreGraphicsState()
                        didDrawPixelatedImage = true
                    }
                }
            }
        }

        if !didDrawPixelatedImage {
            // Elegant fallback crystal frosted mosaic pattern
            context.setFillColor(NSColor(calibratedWhite: 0.35, alpha: 0.95).cgColor)
            context.fill(rect)

            let gridSize: CGFloat = 10.0
            context.setStrokeColor(NSColor(white: 0.5, alpha: 0.4).cgColor)
            context.setLineWidth(1.0)
            var x = rect.minX
            while x < rect.maxX {
                context.move(to: CGPoint(x: x, y: rect.minY))
                context.addLine(to: CGPoint(x: x, y: rect.maxY))
                x += gridSize
            }
            var y = rect.minY
            while y < rect.maxY {
                context.move(to: CGPoint(x: rect.minX, y: y))
                context.addLine(to: CGPoint(x: rect.maxX, y: y))
                y += gridSize
            }
            context.strokePath()
        }

        // Draw delicate subtle outer border
        context.setStrokeColor(NSColor(white: 0.6, alpha: 0.35).cgColor)
        context.setLineWidth(1.0)
        context.stroke(rect)

        context.restoreGState()
    }
}
