import AppKit
import ScreenCaptureKit

protocol ScrollCaptureFrameProviding: AnyObject {
    func capture(completion: @escaping (Result<CGImage, Error>) -> Void)
}

/// 每个会话独立持有过滤器；控制条即使放在选区内，也不会出现在捕获结果里。
final class ScrollCaptureFrameSource: ScrollCaptureFrameProviding {
    private let filter: SCContentFilter
    private let configuration: SCStreamConfiguration
    private let targetWindow: (id: CGWindowID, frame: CGRect)?

    private init(filter: SCContentFilter, configuration: SCStreamConfiguration, targetWindow: (CGWindowID, CGRect)?) {
        self.filter = filter
        self.configuration = configuration
        self.targetWindow = targetWindow
    }

    static func prepare(rect: CGRect, screen: NSScreen, excludingWindowIDs: Set<CGWindowID>, targetPID: pid_t?,
                        completion: @escaping (Result<ScrollCaptureFrameSource, Error>) -> Void) {
        Task { @MainActor in
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                let displayID = DisplayHelper.displayID(for: screen)
                guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                    throw failure("选区所在的显示器已不可用。")
                }
                let excluded = content.windows.filter { excludingWindowIDs.contains($0.windowID) }
                let config = SCStreamConfiguration()
                config.sourceRect = CGRect(x: rect.minX - screen.frame.minX,
                                           y: screen.frame.maxY - rect.maxY,
                                           width: rect.width, height: rect.height)
                config.width = Int((rect.width * screen.backingScaleFactor).rounded())
                config.height = Int((rect.height * screen.backingScaleFactor).rounded())
                config.captureResolution = .best
                config.showsCursor = false
                config.ignoreShadowsDisplay = true
                config.scalesToFit = false
                let quartzRect = DisplayHelper.cocoaToQuartz(rect: rect)
                let candidates = content.windows.filter {
                    $0.owningApplication?.processID == targetPID && !excludingWindowIDs.contains($0.windowID) &&
                    $0.frame.intersection(quartzRect).width * $0.frame.intersection(quartzRect).height >= rect.width * rect.height * 0.98
                }
                let target = candidates.min { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
                let filter: SCContentFilter
                if let target {
                    // Keep display-relative cropping while excluding overlays from other windows/apps.
                    filter = SCContentFilter(display: display, including: [target])
                } else if let ownApp = content.applications.first(where: { $0.processID == ProcessInfo.processInfo.processIdentifier }),
                   targetPID != ownApp.processID || target != nil {
                    // 按应用排除也覆盖会话中途新出现的缩略图和浮窗；本应用测试文档仅保留目标窗口。
                    let exceptions = targetPID == ownApp.processID ? target.map { [$0] } ?? [] : []
                    filter = SCContentFilter(display: display, excludingApplications: [ownApp], exceptingWindows: exceptions)
                } else {
                    filter = SCContentFilter(display: display, excludingWindows: excluded)
                }
                completion(.success(ScrollCaptureFrameSource(filter: filter, configuration: config,
                                                            targetWindow: target.map { ($0.windowID, $0.frame) })))
            } catch { completion(.failure(error)) }
        }
    }

    func capture(completion: @escaping (Result<CGImage, Error>) -> Void) {
        if let targetWindow {
            let windows = CGWindowListCopyWindowInfo(.optionIncludingWindow, targetWindow.id) as? [[String: Any]]
            guard let info = windows?.first, let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let current = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  abs(current.minX - targetWindow.frame.minX) < 1,
                  abs(current.minY - targetWindow.frame.minY) < 1,
                  abs(current.width - targetWindow.frame.width) < 1,
                  abs(current.height - targetWindow.frame.height) < 1 else {
                completion(.failure(Self.failure("目标窗口已移动、缩放或关闭，请重新选择滚动区域。")))
                return
            }
        }
        SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) { image, error in
            DispatchQueue.main.async {
                if let image { completion(.success(image)) }
                else { completion(.failure(error ?? Self.failure("无法读取选区画面，请检查屏幕录制权限。"))) }
            }
        }
    }

    private static func failure(_ message: String) -> Error {
        NSError(domain: "cduyzhShot.ScrollCapture", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
