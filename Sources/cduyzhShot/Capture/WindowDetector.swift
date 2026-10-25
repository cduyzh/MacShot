import AppKit
import CoreGraphics

public struct DetectedWindow {
    public let windowID: CGWindowID
    public let ownerPID: pid_t
    public let ownerName: String
    public let windowTitle: String
    public let cocoaFrame: CGRect
    public let quartzFrame: CGRect
}

public final class WindowDetector {
    public static func findWindow(at point: CGPoint, ignoreWindowIDs: Set<CGWindowID> = []) -> DetectedWindow? {
        let currentPID = ProcessInfo.processInfo.processIdentifier

        guard let windowInfoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        let pHeight = DisplayHelper.primaryScreenHeight

        for dict in windowInfoList {
            guard let windowID = dict[kCGWindowNumber as String] as? CGWindowID,
                  !ignoreWindowIDs.contains(windowID) else {
                continue
            }

            guard let ownerPID = dict[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID != currentPID else {
                continue
            }

            // Check layer: standard windows are at layer 0
            let layer = dict[kCGWindowLayer as String] as? Int ?? 0
            if layer != 0 {
                continue
            }

            // Alpha must be visible
            let alpha = dict[kCGWindowAlpha as String] as? Double ?? 1.0
            if alpha < 0.1 {
                continue
            }

            guard let boundsDict = dict[kCGWindowBounds as String] as? [String: Any],
                  let quartzFrame = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else {
                continue
            }

            // Ignore tiny windows (e.g. shadow or tooltip)
            if quartzFrame.width < 50 || quartzFrame.height < 50 {
                continue
            }

            // Convert to Cocoa coordinates
            let cocoaY = pHeight - (quartzFrame.origin.y + quartzFrame.height)
            let cocoaFrame = CGRect(x: quartzFrame.origin.x, y: cocoaY, width: quartzFrame.width, height: quartzFrame.height)

            if cocoaFrame.contains(point) {
                let ownerName = dict[kCGWindowOwnerName as String] as? String ?? ""
                let title = dict[kCGWindowName as String] as? String ?? ownerName
                return DetectedWindow(
                    windowID: windowID,
                    ownerPID: ownerPID,
                    ownerName: ownerName,
                    windowTitle: title,
                    cocoaFrame: cocoaFrame,
                    quartzFrame: quartzFrame
                )
            }
        }

        return nil
    }
}
