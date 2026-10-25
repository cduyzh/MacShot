import AppKit
import SwiftUI

/// 发现新版本时的独立弹窗控制器
public final class UpdateWindowController: NSWindowController, NSWindowDelegate {
    public static let shared = UpdateWindowController()

    private var currentRelease: RemoteReleaseInfo?

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 460),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "软件更新"
        window.subtitle = "cduyzhShot"
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.backgroundColor = .windowBackgroundColor
        window.contentMinSize = NSSize(width: 480, height: 380)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        if !window.setFrameUsingName("cduyzhShot.UpdateWindow") {
            window.center()
        }
        window.setFrameAutosaveName("cduyzhShot.UpdateWindow")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func show(release: RemoteReleaseInfo) {
        self.currentRelease = release
        window?.contentView = NSHostingView(rootView: UpdateDetailView(
            release: release,
            onClose: { [weak self] in
                self?.window?.close()
            },
            onDownload: { [weak self] in
                self?.openDownload(for: release)
            }
        ))
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openDownload(for release: RemoteReleaseInfo) {
        let targetURL = release.downloadURL ?? release.htmlURL ?? URL(string: "https://github.com/cduyzh/SnapScreen/releases")
        if let targetURL = targetURL {
            NSWorkspace.shared.open(targetURL)
        }
        window?.close()
    }

    public func windowWillClose(_ notification: Notification) {
        let hasOtherWindow = NSApp.windows.contains {
            $0 !== window && $0.isVisible && $0.styleMask.contains(.titled)
        }
        if !hasOtherWindow {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

private struct UpdateDetailView: View {
    let release: RemoteReleaseInfo
    let onClose: () -> Void
    let onDownload: () -> Void

    @ObservedObject var prefs = UserPreferences.shared

    var body: some View {
        VStack(spacing: 0) {
            // 头部卡片
            HStack(spacing: 16) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Color.accentColor.gradient)
                    .frame(width: 54, height: 54)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("发现新版本")
                            .font(.system(size: 19, weight: .bold))
                        Text(release.version)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    }

                    HStack(spacing: 12) {
                        if let build = release.build {
                            Text("构建号: \(build)")
                        }
                        if let date = release.releaseDate {
                            Text("发布时间: \(date)")
                        }
                        Text("当前版本: \(AppVersion.current.displayString)")
                            .foregroundStyle(.secondary)
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()

            // 更新日志内容区
            VStack(alignment: .leading, spacing: 10) {
                Text(release.title)
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.top, 4)

                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if release.releaseNotes.isEmpty {
                            Text("此版本未提供详细更新说明。")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        } else {
                            Text(release.releaseNotes)
                                .font(.system(size: 12, design: .default))
                                .lineSpacing(4)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(14)
                }
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08)))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()

            // 底部操作栏
            HStack {
                Toggle("启动时自动检查更新", isOn: $prefs.autoCheckForUpdates)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                Spacer()

                Button("稍后提醒") {
                    onClose()
                }
                .keyboardShortcut(.cancelAction)

                Button(action: onDownload) {
                    Text(release.downloadURL != nil ? "立即下载更新" : "前往 Releases 页面")
                        .fontWeight(.medium)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 480, idealWidth: 560, minHeight: 380, idealHeight: 460)
    }
}
