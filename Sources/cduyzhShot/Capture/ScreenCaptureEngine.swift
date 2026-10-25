import AppKit
import CoreGraphics

public final class ScreenCaptureEngine {
    public static let shared = ScreenCaptureEngine()

    private init() {}

    /// Captures a screen in native resolution
    public func capture(screen: NSScreen) -> CGImage? {
        let displayID = DisplayHelper.displayID(for: screen)
        return CGDisplayCreateImage(displayID)
    }

    /// Captures a specific rect in Cocoa screen coordinates
    public func capture(rect: CGRect) -> CGImage? {
        guard rect.width > 0, rect.height > 0 else { return nil }

        // Convert to Quartz rect
        let quartzRect = DisplayHelper.cocoaToQuartz(rect: rect)

        // Capture image of rect
        if let image = CGWindowListCreateImage(
            quartzRect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution, .nominalResolution]
        ) {
            return image
        }

        // Fallback: capture display and crop
        guard let screen = DisplayHelper.screenContaining(point: rect.origin) else { return nil }
        guard let fullImage = capture(screen: screen) else { return nil }

        let scale = screen.backingScaleFactor
        let screenOrigin = screen.frame.origin
        let relX = (rect.origin.x - screenOrigin.x) * scale
        let relY = (screen.frame.height - (rect.origin.y - screenOrigin.y + rect.height)) * scale
        let cropRect = CGRect(x: relX, y: relY, width: rect.width * scale, height: rect.height * scale)

        return fullImage.cropping(to: cropRect)
    }

    /// Captures a specific window by its CGWindowID
    public func capture(windowID: CGWindowID, withShadow: Bool = true) -> CGImage? {
        let options: CGWindowImageOption = withShadow ? [.bestResolution] : [.bestResolution, .boundsIgnoreFraming]
        return CGWindowListCreateImage(.null, .optionIncludingWindow, windowID, options)
    }
}
