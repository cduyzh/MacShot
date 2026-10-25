import AppKit
import CoreGraphics

public final class MagnifierView: NSView {
    public var currentPoint: CGPoint = .zero {
        didSet { needsDisplay = true }
    }
    public var selectionSize: CGSize = .zero {
        didSet { needsDisplay = true }
    }
    public var sourceImage: CGImage? {
        didSet { needsDisplay = true }
    }
    public var screenScale: CGFloat = 2.0
    public private(set) var currentHexColor: String = "#FFFFFF"

    private let sampleRadius: Int = 4 // 9x9 crystal grid
    private let loupeSize: CGFloat = 120.0

    public override var isFlipped: Bool { true }

    public override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: 134, height: 174))
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = false
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.4
        layer?.shadowRadius = 10
        layer?.shadowOffset = CGSize(width: 0, height: -3)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // Background container with frosted dark styling
        let bgPath = CGPath(roundedRect: bounds, cornerWidth: 10, cornerHeight: 10, transform: nil)
        context.addPath(bgPath)
        context.setFillColor(NSColor(calibratedWhite: 0.10, alpha: 0.94).cgColor)
        context.fillPath()

        // Card border
        context.addPath(bgPath)
        context.setStrokeColor(NSColor(white: 1.0, alpha: 0.18).cgColor)
        context.setLineWidth(0.8)
        context.strokePath()

        // Loupe image area (114 x 114)
        let loupeRect = CGRect(x: 10, y: 10, width: bounds.width - 20, height: bounds.width - 20)
        let loupePath = CGPath(roundedRect: loupeRect, cornerWidth: 7, cornerHeight: 7, transform: nil)

        var centerColor = NSColor.white

        if let image = sourceImage {
            context.saveGState()
            context.addPath(loupePath)
            context.clip()

            // Calculate pixel crop
            let pixelX = currentPoint.x * screenScale
            let pixelY = currentPoint.y * screenScale
            let cropW = CGFloat(sampleRadius * 2 + 1)
            let cropH = CGFloat(sampleRadius * 2 + 1)
            let cropRect = CGRect(
                x: pixelX - CGFloat(sampleRadius),
                y: pixelY - CGFloat(sampleRadius),
                width: cropW,
                height: cropH
            )

            if let cropped = image.cropping(to: cropRect) {
                NSImage(cgImage: cropped, size: loupeRect.size).draw(in: loupeRect)
            }

            // Sample center pixel color
            centerColor = samplePixelColor(from: image, at: CGPoint(x: pixelX, y: pixelY))

            // Draw pixel grid lines
            context.setStrokeColor(NSColor(white: 1.0, alpha: 0.12).cgColor)
            context.setLineWidth(0.5)
            let cellW = loupeRect.width / cropW
            let cellH = loupeRect.height / cropH
            for i in 0...Int(cropW) {
                let x = loupeRect.minX + CGFloat(i) * cellW
                context.move(to: CGPoint(x: x, y: loupeRect.minY))
                context.addLine(to: CGPoint(x: x, y: loupeRect.maxY))
            }
            for j in 0...Int(cropH) {
                let y = loupeRect.minY + CGFloat(j) * cellH
                context.move(to: CGPoint(x: loupeRect.minX, y: y))
                context.addLine(to: CGPoint(x: loupeRect.maxX, y: y))
            }
            context.strokePath()

            // Center target indicator box (High-contrast blue/white crosshair)
            let centerX = loupeRect.midX
            let centerY = loupeRect.midY
            let targetRect = CGRect(x: centerX - cellW / 2, y: centerY - cellH / 2, width: cellW, height: cellH)

            context.setStrokeColor(NSColor.systemBlue.cgColor)
            context.setLineWidth(1.8)
            context.stroke(targetRect)

            context.restoreGState()
        }

        // Loupe inner border
        context.addPath(loupePath)
        context.setStrokeColor(NSColor(white: 1.0, alpha: 0.25).cgColor)
        context.setLineWidth(1.0)
        context.strokePath()

        // Text Info (Color Hex, Coordinates, Size)
        let hexString = String(
            format: "#%02X%02X%02X",
            Int(centerColor.redComponent * 255),
            Int(centerColor.greenComponent * 255),
            Int(centerColor.blueComponent * 255)
        )
        self.currentHexColor = hexString

        // Small color swatch circle
        let swatchRect = CGRect(x: 12, y: loupeRect.maxY + 8, width: 12, height: 12)
        context.setFillColor(centerColor.cgColor)
        context.fillEllipse(in: swatchRect)
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(1.0)
        context.strokeEllipse(in: swatchRect)

        let hexAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        (hexString as NSString).draw(at: CGPoint(x: swatchRect.maxX + 6, y: loupeRect.maxY + 6), withAttributes: hexAttrs)

        let infoText: String
        if selectionSize.width > 0 && selectionSize.height > 0 {
            infoText = "\(Int(selectionSize.width)) × \(Int(selectionSize.height))"
        } else {
            infoText = "X:\(Int(currentPoint.x)) Y:\(Int(currentPoint.y)) · 按C复制"
        }

        let coordAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9.5, weight: .medium),
            .foregroundColor: NSColor(white: 0.72, alpha: 1.0)
        ]
        (infoText as NSString).draw(at: CGPoint(x: 12, y: loupeRect.maxY + 24), withAttributes: coordAttrs)
    }

    private func samplePixelColor(from image: CGImage, at point: CGPoint) -> NSColor {
        guard let dataProvider = image.dataProvider,
              let data = dataProvider.data,
              let ptr = CFDataGetBytePtr(data) else {
            return .white
        }

        let x = max(0, min(Int(point.x), image.width - 1))
        let y = max(0, min(Int(point.y), image.height - 1))
        let bytesPerRow = image.bytesPerRow
        let offset = y * bytesPerRow + x * 4

        let b = CGFloat(ptr[offset]) / 255.0
        let g = CGFloat(ptr[offset + 1]) / 255.0
        let r = CGFloat(ptr[offset + 2]) / 255.0
        let a = CGFloat(ptr[offset + 3]) / 255.0

        return NSColor(red: r, green: g, blue: b, alpha: a)
    }
}
