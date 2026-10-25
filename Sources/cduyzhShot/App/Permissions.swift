import AppKit
import AVFoundation

public enum Permissions {
    public static var hasScreenRecordingPermission: Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }
        // Fallback probe: if system has granted access but CGPreflight cache hasn't updated in current process,
        // a 1x1 screen capture test will verify actual screen capture access
        if let probe = CGWindowListCreateImage(
            CGRect(x: 0, y: 0, width: 1, height: 1),
            .optionOnScreenOnly,
            kCGNullWindowID,
            .nominalResolution
        ), probe.width > 0 && probe.height > 0 {
            return true
        }
        return false
    }

    public static func requestScreenRecordingPermission(promptUser: Bool = false) {
        if !hasScreenRecordingPermission {
            CGRequestScreenCaptureAccess()
            if promptUser {
                showScreenRecordingPermissionAlert()
            }
        }
    }

    public static func showScreenRecordingPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "cduyzhShot 需要「屏幕录制」权限"
        alert.informativeText = "cduyzhShot 需要屏幕录制权限以正常截取屏幕、长截图与录屏。\n\n1. 请在即将打开的系统设置中找到并开启 cduyzhShot 开关；\n2. 若您刚刚已开启权限，请点击下方【重启生效】重新载入权限。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "前往系统设置")
        alert.addButton(withTitle: "重启生效")
        alert.addButton(withTitle: "稍后")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            openSystemSettings(for: "screen")
        } else if response == .alertSecondButtonReturn {
            relaunchApp()
        }
    }

    public static func relaunchApp() {
        let bundleURL = Bundle.main.bundleURL
        let pid = ProcessInfo.processInfo.processIdentifier

        let task = Process()
        task.launchPath = "/bin/sh"
        if bundleURL.pathExtension == "app" {
            // .app 包形态：等待当前 PID 完全退出后，使用 open -n 重新启动该应用
            let script = "while kill -0 \(pid) 2>/dev/null; do sleep 0.1; done; /usr/bin/open -n \"\(bundleURL.path)\""
            task.arguments = ["-c", script]
        } else {
            // 二进制或开发执行形态：等待退出后重新拉起当前可执行文件
            let execPath = Bundle.main.executablePath ?? ProcessInfo.processInfo.arguments[0]
            let script = "while kill -0 \(pid) 2>/dev/null; do sleep 0.1; done; \"\(execPath)\""
            task.arguments = ["-c", script]
        }
        try? task.run()
        NSApp.terminate(nil)
    }

    public static var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    public static func requestAccessibilityPermission(promptUser: Bool = false) {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        if !trusted && promptUser {
            openSystemSettings(for: "accessibility")
        }
    }

    public static func checkMicrophonePermission(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        default:
            completion(false)
        }
    }

    public static func openSystemSettings(for type: String) {
        var urlString = ""
        switch type {
        case "screen":
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        case "accessibility":
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case "microphone":
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        default:
            urlString = "x-apple.systempreferences:com.apple.preference.security"
        }
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}
