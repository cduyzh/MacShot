import AppKit
import CoreGraphics

public struct DisplayHelper {
    public static var primaryScreen: NSScreen? {
        NSScreen.screens.first
    }

    public static var primaryScreenHeight: CGFloat {
        primaryScreen?.frame.height ?? 1080
    }

    /// Converts Cocoa screen coordinates (origin bottom-left, y up) to Quartz coordinates (origin top-left, y down)
    public static func cocoaToQuartz(rect: CGRect) -> CGRect {
        let pHeight = primaryScreenHeight
        let quartzY = pHeight - (rect.origin.y + rect.height)
        return CGRect(x: rect.origin.x, y: quartzY, width: rect.width, height: rect.height)
    }

    /// Converts Quartz coordinates (origin top-left, y down) to Cocoa coordinates (origin bottom-left, y up)
    public static func quartzToCocoa(rect: CGRect) -> CGRect {
        let pHeight = primaryScreenHeight
        let cocoaY = pHeight - (rect.origin.y + rect.height)
        return CGRect(x: rect.origin.x, y: cocoaY, width: rect.width, height: rect.height)
    }

    public static func screenContaining(point: CGPoint) -> NSScreen? {
        for screen in NSScreen.screens {
            if screen.frame.contains(point) {
                return screen
            }
        }
        return NSScreen.main ?? primaryScreen
    }

    public static func displayID(for screen: NSScreen) -> CGDirectDisplayID {
        guard let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return CGMainDisplayID()
        }
        return CGDirectDisplayID(num.uint32Value)
    }
}
