import AppKit
import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins

public enum ScreenshotStudioRenderer {
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    public static func render(
        image: CGImage,
        model: ScreenshotStudioModel,
        targetScale: CGFloat = 2.0
    ) -> CGImage? {
        let imgWidth = CGFloat(image.width)
        let imgHeight = CGFloat(image.height)
        guard imgWidth > 0, imgHeight > 0 else { return nil }

        // 1. Compute Chrome Geometry
        let chromeHeight: CGFloat
        switch model.mockup {
        case .none:
            chromeHeight = 0
        case .macLight, .macDark:
            chromeHeight = max(38, imgHeight * 0.05)
        case .browserLight, .browserDark:
            chromeHeight = max(46, imgHeight * 0.065)
        }

        let cardWidth = imgWidth
        let cardHeight = imgHeight + chromeHeight

        // 2. Compute Canvas Geometry with Padding & Aspect Ratio
        let padding = model.padding
        var canvasWidth = cardWidth + padding * 2
        var canvasHeight = cardHeight + padding * 2

        if let targetRatio = model.aspectRatio.ratioMultiplier() {
            let currentRatio = canvasWidth / canvasHeight
            if currentRatio < targetRatio {
                // Too tall, expand width
                canvasWidth = canvasHeight * targetRatio
            } else {
                // Too wide, expand height
                canvasHeight = canvasWidth / targetRatio
            }
        }

        let pixelWidth = Int(canvasWidth * targetScale)
        let pixelHeight = Int(canvasHeight * targetScale)

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        guard let ctx = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Scale to logical point space
        ctx.scaleBy(x: targetScale, y: targetScale)

        let canvasRect = CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight)

        // 3. Render Background
        renderBackground(
            ctx: ctx,
            canvasRect: canvasRect,
            sourceImage: image,
            style: model.background
        )

        // 4. Center Card in Canvas
        let cardX = (canvasWidth - cardWidth) / 2
        let cardY = (canvasHeight - cardHeight) / 2
        let cardRect = CGRect(x: cardX, y: cardY, width: cardWidth, height: cardHeight)

        // 5. Render Drop Shadow
        if model.shadow != .none && model.background != .transparent {
            renderShadow(ctx: ctx, cardRect: cardRect, cornerRadius: model.cornerRadius, style: model.shadow)
        }

        // 6. Render Card with Mockup and Content
        renderCard(
            ctx: ctx,
            cardRect: cardRect,
            image: image,
            chromeHeight: chromeHeight,
            model: model
        )

        return ctx.makeImage()
    }

    // MARK: - Background Rendering
    private static func renderBackground(
        ctx: CGContext,
        canvasRect: CGRect,
        sourceImage: CGImage,
        style: StudioBackgroundStyle
    ) {
        switch style {
        case .transparent:
            ctx.clear(canvasRect)

        case .blur:
            renderBlurredBackground(ctx: ctx, canvasRect: canvasRect, sourceImage: sourceImage)

        case .gradientSonoma:
            drawLinearGradient(
                ctx: ctx,
                rect: canvasRect,
                colors: [
                    NSColor(red: 0.52, green: 0.24, blue: 0.78, alpha: 1.0),
                    NSColor(red: 0.95, green: 0.42, blue: 0.35, alpha: 1.0),
                    NSColor(red: 0.98, green: 0.72, blue: 0.38, alpha: 1.0)
                ]
            )

        case .gradientAurora:
            drawLinearGradient(
                ctx: ctx,
                rect: canvasRect,
                colors: [
                    NSColor(red: 0.06, green: 0.10, blue: 0.24, alpha: 1.0),
                    NSColor(red: 0.08, green: 0.35, blue: 0.45, alpha: 1.0),
                    NSColor(red: 0.15, green: 0.72, blue: 0.55, alpha: 1.0)
                ]
            )

        case .gradientGraphite:
            drawLinearGradient(
                ctx: ctx,
                rect: canvasRect,
                colors: [
                    NSColor(calibratedRed: 0.16, green: 0.17, blue: 0.20, alpha: 1.0),
                    NSColor(calibratedRed: 0.08, green: 0.08, blue: 0.10, alpha: 1.0)
                ]
            )

        case .gradientOcean:
            drawLinearGradient(
                ctx: ctx,
                rect: canvasRect,
                colors: [
                    NSColor(red: 0.08, green: 0.22, blue: 0.62, alpha: 1.0),
                    NSColor(red: 0.12, green: 0.52, blue: 0.88, alpha: 1.0)
                ]
            )

        case .solidDark:
            ctx.setFillColor(NSColor(calibratedWhite: 0.08, alpha: 1.0).cgColor)
            ctx.fill(canvasRect)

        case .solidWhite:
            ctx.setFillColor(NSColor(calibratedWhite: 0.98, alpha: 1.0).cgColor)
            ctx.fill(canvasRect)
        }
    }

    private static func renderBlurredBackground(
        ctx: CGContext,
        canvasRect: CGRect,
        sourceImage: CGImage
    ) {
        let ciImage = CIImage(cgImage: sourceImage)
        let blurFilter = CIFilter.gaussianBlur()
        blurFilter.inputImage = ciImage
        blurFilter.radius = 55.0

        if let blurred = blurFilter.outputImage {
            // Scale and crop to canvas rect
            let scaleX = canvasRect.width / CGFloat(sourceImage.width)
            let scaleY = canvasRect.height / CGFloat(sourceImage.height)
            let fillScale = max(scaleX, scaleY) * 1.25

            let scaled = blurred.transformed(by: CGAffineTransform(scaleX: fillScale, y: fillScale))
            let originX = (scaled.extent.width - canvasRect.width) / 2
            let originY = (scaled.extent.height - canvasRect.height) / 2
            let cropRect = CGRect(x: originX, y: originY, width: canvasRect.width, height: canvasRect.height)
            let cropped = scaled.cropped(to: cropRect)

            if let cgBlurred = ciContext.createCGImage(cropped, from: cropRect) {
                ctx.draw(cgBlurred, in: canvasRect)
            }
        }

        // Add soft dark vignette overlay for high contrast
        ctx.setFillColor(NSColor(white: 0.0, alpha: 0.32).cgColor)
        ctx.fill(canvasRect)
    }

    private static func drawLinearGradient(
        ctx: CGContext,
        rect: CGRect,
        colors: [NSColor]
    ) {
        let cgColors = colors.map { $0.cgColor } as CFArray
        guard let gradient = CGGradient(colorsSpace: ctx.colorSpace, colors: cgColors, locations: nil) else { return }

        ctx.saveGState()
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.minX, y: rect.maxY),
            end: CGPoint(x: rect.maxX, y: rect.minY),
            options: []
        )
        ctx.restoreGState()
    }

    // MARK: - Multi-Layer Shadow
    private static func renderShadow(
        ctx: CGContext,
        cardRect: CGRect,
        cornerRadius: CGFloat,
        style: StudioShadowStyle
    ) {
        ctx.saveGState()

        let path = CGPath(roundedRect: cardRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

        // 1. Soft Ambient Diffuse Shadow
        let ambientBlur: CGFloat = style == .deep ? 38.0 : 20.0
        let ambientAlpha: CGFloat = style == .deep ? 0.38 : 0.22
        ctx.setShadow(
            offset: CGSize(width: 0, height: -6),
            blur: ambientBlur,
            color: NSColor.black.withAlphaComponent(ambientAlpha).cgColor
        )
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.addPath(path)
        ctx.fillPath()

        // 2. Focused Key Shadow
        if style == .deep {
            ctx.setShadow(
                offset: CGSize(width: 0, height: -2),
                blur: 12.0,
                color: NSColor.black.withAlphaComponent(0.28).cgColor
            )
            ctx.addPath(path)
            ctx.fillPath()
        }

        ctx.restoreGState()
    }

    // MARK: - Card & Chrome Rendering
    private static func renderCard(
        ctx: CGContext,
        cardRect: CGRect,
        image: CGImage,
        chromeHeight: CGFloat,
        model: ScreenshotStudioModel
    ) {
        ctx.saveGState()

        let cardPath = CGPath(
            roundedRect: cardRect,
            cornerWidth: model.cornerRadius,
            cornerHeight: model.cornerRadius,
            transform: nil
        )

        // Clip entire card
        ctx.addPath(cardPath)
        ctx.clip()

        // Fill Card Base
        let isDark = (model.mockup == .macDark || model.mockup == .browserDark)
        let baseColor = isDark ? NSColor(calibratedWhite: 0.12, alpha: 1.0) : NSColor.white
        ctx.setFillColor(baseColor.cgColor)
        ctx.fill(cardRect)

        let contentRect = CGRect(
            x: cardRect.minX,
            y: cardRect.minY,
            width: cardRect.width,
            height: cardRect.height - chromeHeight
        )

        // Draw Content Image
        ctx.draw(image, in: contentRect)

        // Draw Chrome Toolbar if selected
        if chromeHeight > 0 {
            let toolbarRect = CGRect(
                x: cardRect.minX,
                y: cardRect.maxY - chromeHeight,
                width: cardRect.width,
                height: chromeHeight
            )
            renderChromeToolbar(ctx: ctx, toolbarRect: toolbarRect, model: model)
        }

        // Draw 1px subtle crisp border
        ctx.restoreGState()
        ctx.saveGState()
        let borderAlpha: CGFloat = isDark ? 0.18 : 0.12
        ctx.setStrokeColor(NSColor(white: isDark ? 1.0 : 0.0, alpha: borderAlpha).cgColor)
        ctx.setLineWidth(1.0)
        ctx.addPath(cardPath)
        ctx.strokePath()
        ctx.restoreGState()
    }

    private static func renderChromeToolbar(
        ctx: CGContext,
        toolbarRect: CGRect,
        model: ScreenshotStudioModel
    ) {
        ctx.saveGState()

        let isDark = (model.mockup == .macDark || model.mockup == .browserDark)

        // Toolbar Surface Fill
        let bgColor = isDark
            ? NSColor(calibratedRed: 0.12, green: 0.13, blue: 0.15, alpha: 1.0)
            : NSColor(calibratedRed: 0.96, green: 0.96, blue: 0.97, alpha: 1.0)
        ctx.setFillColor(bgColor.cgColor)
        ctx.fill(toolbarRect)

        // 1px Bottom Divider Line
        let divColor = isDark
            ? NSColor(white: 1.0, alpha: 0.08)
            : NSColor(white: 0.0, alpha: 0.10)
        ctx.setFillColor(divColor.cgColor)
        ctx.fill(CGRect(x: toolbarRect.minX, y: toolbarRect.minY, width: toolbarRect.width, height: 1.0))

        // Traffic Light Buttons
        let btnDiameter: CGFloat = max(11.0, min(toolbarRect.height * 0.32, 13.0))
        let btnMargin: CGFloat = 16.0
        let btnSpacing: CGFloat = btnDiameter * 1.6

        let btnColors = [
            NSColor(red: 1.0, green: 0.37, blue: 0.34, alpha: 1.0), // Red
            NSColor(red: 1.0, green: 0.74, blue: 0.18, alpha: 1.0), // Yellow
            NSColor(red: 0.16, green: 0.79, blue: 0.25, alpha: 1.0)  // Green
        ]

        for (i, c) in btnColors.enumerated() {
            let cx = toolbarRect.minX + btnMargin + CGFloat(i) * btnSpacing
            let cy = toolbarRect.midY - btnDiameter / 2
            let dotRect = CGRect(x: cx, y: cy, width: btnDiameter, height: btnDiameter)

            ctx.setFillColor(c.cgColor)
            ctx.fillEllipse(in: dotRect)

            // Inner border for traffic lights
            ctx.setStrokeColor(NSColor(white: 0.0, alpha: 0.15).cgColor)
            ctx.setLineWidth(0.5)
            ctx.strokeEllipse(in: dotRect)
        }

        // Window Title or Browser URL Bar
        let titleColor = isDark
            ? NSColor(white: 0.78, alpha: 1.0)
            : NSColor(white: 0.25, alpha: 1.0)

        if model.mockup == .browserLight || model.mockup == .browserDark {
            // Draw Browser URL Pill
            let barWidth = min(toolbarRect.width * 0.52, 420)
            let barHeight = toolbarRect.height * 0.62
            let barRect = CGRect(
                x: toolbarRect.midX - barWidth / 2,
                y: toolbarRect.midY - barHeight / 2,
                width: barWidth,
                height: barHeight
            )

            let barBg = isDark
                ? NSColor(calibratedRed: 0.18, green: 0.19, blue: 0.22, alpha: 1.0)
                : NSColor.white
            let barBorder = isDark
                ? NSColor(white: 1.0, alpha: 0.12)
                : NSColor(white: 0.0, alpha: 0.14)

            let barPath = CGPath(roundedRect: barRect, cornerWidth: barHeight / 2, cornerHeight: barHeight / 2, transform: nil)
            ctx.setFillColor(barBg.cgColor)
            ctx.addPath(barPath)
            ctx.fillPath()

            ctx.setStrokeColor(barBorder.cgColor)
            ctx.setLineWidth(1.0)
            ctx.addPath(barPath)
            ctx.strokePath()

            // Draw lock & URL text
            let urlText = "cduyzh.local" as NSString
            let font = NSFont.systemFont(ofSize: max(11, barHeight * 0.44), weight: .medium)
            let textAttrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: titleColor
            ]
            let textSize = urlText.size(withAttributes: textAttrs)
            let textOrigin = CGPoint(
                x: barRect.midX - textSize.width / 2,
                y: barRect.midY - textSize.height / 2 + 0.5
            )

            NSGraphicsContext.saveGraphicsState()
            let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
            NSGraphicsContext.current = nsCtx
            urlText.draw(at: textOrigin, withAttributes: textAttrs)
            NSGraphicsContext.restoreGraphicsState()

        } else {
            // Draw Window Title
            let titleText = (model.windowTitle.isEmpty ? "cduyzhShot" : model.windowTitle) as NSString
            let font = NSFont.systemFont(ofSize: max(11.5, toolbarRect.height * 0.34), weight: .semibold)
            let textAttrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: titleColor
            ]
            let textSize = titleText.size(withAttributes: textAttrs)
            let textOrigin = CGPoint(
                x: toolbarRect.midX - textSize.width / 2,
                y: toolbarRect.midY - textSize.height / 2 + 0.5
            )

            NSGraphicsContext.saveGraphicsState()
            let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
            NSGraphicsContext.current = nsCtx
            titleText.draw(at: textOrigin, withAttributes: textAttrs)
            NSGraphicsContext.restoreGraphicsState()
        }

        ctx.restoreGState()
    }
}
