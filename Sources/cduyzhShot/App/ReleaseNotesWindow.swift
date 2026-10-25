import AppKit
import SwiftUI

final class ReleaseNotesWindowController: NSWindowController, NSWindowDelegate {
    static let shared = ReleaseNotesWindowController()
    private let seenReleasesKey = "cduyzhShot.releaseNotes.seenReleaseIDs"

    /// 只有记录与安装版本完全匹配时，才为该版本提示未读内容。
    var hasUnreadRelease: Bool {
        guard let release = AppVersion.current.releaseRecord else { return false }
        return !Set(UserDefaults.standard.stringArray(forKey: seenReleasesKey) ?? []).contains(release.id)
    }

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 650),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "更新记录"
        window.subtitle = "cduyzhShot · \(AppVersion.current.displayString)"
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.backgroundColor = .windowBackgroundColor
        window.contentMinSize = NSSize(width: 540, height: 440)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.contentView = NSHostingView(rootView: ReleaseNotesView(onClose: { [weak self] in
            self?.window?.close()
        }))
        if !window.setFrameUsingName("cduyzhShot.ReleaseNotes") { window.center() }
        window.setFrameAutosaveName("cduyzhShot.ReleaseNotes")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if let release = AppVersion.current.releaseRecord {
            var seen = Set(UserDefaults.standard.stringArray(forKey: seenReleasesKey) ?? [])
            seen.insert(release.id)
            UserDefaults.standard.set(Array(seen).sorted(), forKey: seenReleasesKey)
        }
    }

    func showIfNeeded() {
        guard hasUnreadRelease else { return }
        show()
    }

    func windowWillClose(_ notification: Notification) {
        let hasOtherWindow = NSApp.windows.contains {
            $0 !== window && $0.isVisible && $0.styleMask.contains(.titled)
        }
        if !hasOtherWindow { NSApp.setActivationPolicy(.accessory) }
    }
}

private struct ReleaseNotesView: View {
    let onClose: () -> Void
    private let current = AppVersion.current
    private let history = ReleaseHistory.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Image(systemName: "viewfinder")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 58, height: 58)
                    .background(Color.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 15))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text("cduyzhShot")
                        .font(.system(size: 22, weight: .semibold))
                    Text("当前安装 \(current.displayString)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
            }
            .padding(26)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if history.isAvailable {
                        if current.releaseRecord == nil {
                            Label("此安装版本尚无对应记录，以下为应用内附带的历史记录。", systemImage: "info.circle")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        ForEach(history.releases) { release in
                            ReleaseNotesCard(
                                release: release,
                                isCurrent: release.version == current.version && release.build == current.build
                            )
                        }
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 30, weight: .light))
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                            Text("更新记录暂不可用")
                                .font(.system(size: 16, weight: .semibold))
                            Text("此应用包未包含可读取的更新记录。重新安装完整版本后可在这里查看。")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                    }
                }
                .frame(maxWidth: 700, alignment: .leading)
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .background(Color.primary.opacity(0.025))

            Divider()
            HStack(spacing: 16) {
                Text("记录随应用发布，未连接在线更新服务。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                Button("完成", action: onClose)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(minWidth: 540, minHeight: 440)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct ReleaseNotesCard: View {
    let release: AppRelease
    let isCurrent: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Text(release.version)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                    if isCurrent {
                        Text("当前安装")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.09), in: Capsule())
                    }
                    Spacer(minLength: 4)
                }
                Text("\(release.dateDisplayString) · 构建 \(release.build)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 7) {
                Text(release.title)
                    .font(.system(size: 14, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                if !release.summary.isEmpty {
                    Text(release.summary)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !release.highlights.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(release.highlights.enumerated()), id: \.offset) { _, highlight in
                        HStack(alignment: .top, spacing: 10) {
                            Circle()
                                .fill(isCurrent ? Color.accentColor : Color.secondary)
                                .frame(width: 4, height: 4)
                                .padding(.top, 6)
                                .accessibilityHidden(true)
                            Text(highlight)
                                .font(.system(size: 12))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            if !release.notes.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(release.notes.enumerated()), id: \.offset) { _, note in
                        Text(note)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(
            isCurrent ? Color.accentColor.opacity(0.24) : Color.primary.opacity(0.07),
            lineWidth: 1
        ))
        .textSelection(.enabled)
    }
}
