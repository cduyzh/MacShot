import AppKit
import UserNotifications

public final class NotificationHelper: NSObject, UNUserNotificationCenterDelegate {
    public static let shared = NotificationHelper()

    private override init() {
        super.init()
        guard Bundle.main.bundleIdentifier != nil, Bundle.main.object(forInfoDictionaryKey: "cduyzhUIPreview") as? Bool != true else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    public static func notifyScreenshotSaved(url: URL) {
        shared.postNotification(
            title: "截图已保存",
            body: "已保存至 \(url.lastPathComponent)",
            fileURL: url
        )
    }

    public static func notifyRecordingSaved(url: URL) {
        shared.postNotification(
            title: "录屏已完成",
            body: "视频已保存至 \(url.lastPathComponent)",
            fileURL: url
        )
    }

    private func postNotification(title: String, body: String, fileURL: URL) {
        guard Bundle.main.bundleIdentifier != nil, Bundle.main.object(forInfoDictionaryKey: "cduyzhUIPreview") as? Bool != true else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["filePath": fileURL.path]

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let path = response.notification.request.content.userInfo["filePath"] as? String {
            let url = URL(fileURLWithPath: path)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
        completionHandler()
    }
}
