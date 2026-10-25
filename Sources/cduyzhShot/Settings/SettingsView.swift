import SwiftUI
import AppKit

private enum SettingsPane: String, CaseIterable, Identifiable {
    case screenshot, recording, hotkeys, cache, permissions, about

    var id: Self { self }

    var title: String {
        switch self {
        case .screenshot: return "截屏与剪贴板"
        case .recording: return "录屏与声音"
        case .hotkeys: return "快捷键"
        case .cache: return "缓存与清理"
        case .permissions: return "系统权限"
        case .about: return "关于与更新"
        }
    }

    var subtitle: String {
        switch self {
        case .screenshot: return "让每次截图，都恰好符合你的习惯。"
        case .recording: return "调整画面流畅度与声音录制。"
        case .hotkeys: return "常用操作，随手可达。"
        case .cache: return "查看临时文件占用，保持存储空间整洁。"
        case .permissions: return "管理截图、录屏和长截图所需的系统访问权限。"
        case .about: return "查看当前安装版本，以及每次更新带来的变化。"
        }
    }

    var symbol: String {
        switch self {
        case .screenshot: return "viewfinder"
        case .recording: return "record.circle"
        case .hotkeys: return "keyboard"
        case .cache: return "internaldrive"
        case .permissions: return "hand.raised"
        case .about: return "info.circle"
        }
    }

    var color: Color {
        switch self {
        case .screenshot: return .blue
        case .recording: return .red
        case .hotkeys: return .secondary
        case .cache: return .orange
        case .permissions: return .purple
        case .about: return .blue
        }
    }
}

public struct SettingsView: View {
    @ObservedObject var prefs = UserPreferences.shared
    @ObservedObject var updateManager = UpdateManager.shared
    @State private var selectedPane: SettingsPane? = .screenshot
    @State private var currentCacheSizeText = CacheManager.shared.formattedCacheSize()
    @State private var cleanCacheFeedback = ""
    @State private var hasScreenRecording = Permissions.hasScreenRecordingPermission
    @State private var hasAccessibility = Permissions.hasAccessibilityPermission
    @State private var refreshFeedback = ""
    @State private var showAdvancedUpdateSettings = false

    public init() {}

    public var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            detail
        }
        .frame(minWidth: 740, idealWidth: 800, minHeight: 520, idealHeight: 600)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            refreshCacheSize()
            refreshPermissions()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissions()
            refreshCacheSize()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("cduyzhShot.settings.showAbout"))) { _ in
            selectedPane = .about
        }
        .onChange(of: selectedPane) { _, pane in
            if pane == .cache { refreshCacheSize() }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "viewfinder")
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("cduyzhShot")
                        .font(.system(size: 13, weight: .semibold))
                    Text("设置")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 24)

            List(SettingsPane.allCases, selection: $selectedPane) { pane in
                HStack(spacing: 9) {
                    Image(systemName: pane.symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 25, height: 25)
                        .background(pane.color.gradient, in: RoundedRectangle(cornerRadius: 6))
                        .accessibilityHidden(true)
                    Text(pane.title)
                        .font(.system(size: 13))
                }
                .padding(.vertical, 3)
                .tag(pane)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .accessibilityLabel("设置分类")

            VStack(alignment: .leading, spacing: 4) {
                Text("版本 \(AppVersion.current.displayString)")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                Text("cduyzhShot")
                    .font(.system(size: 10))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
        }
        .frame(width: 184)
        .background(.regularMaterial)
    }

    private var detail: some View {
        let pane = selectedPane ?? .screenshot
        return ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(pane.title)
                        .font(.system(size: 25, weight: .bold))
                        .accessibilityAddTraits(.isHeader)
                    Text(pane.subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.bottom, 2)

                switch pane {
                case .screenshot: screenshotSettings
                case .recording: recordingSettings
                case .hotkeys: hotkeySettings
                case .cache: cacheSettings
                case .permissions: permissionSettings
                case .about: aboutSettings
                }
            }
            .frame(maxWidth: 660, alignment: .leading)
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .id(pane)
    }

    private var screenshotSettings: some View {
        VStack(spacing: 24) {
            SettingsCard(title: "剪贴板") {
                SettingsToggle("自动复制截图", subtitle: "完成后即可用 ⌘V 粘贴。", isOn: $prefs.autoCopyToClipboard)
                SettingsDivider()
                SettingsToggle("同时复制文件引用", subtitle: "兼容微信等支持文件粘贴的应用。", isOn: $prefs.copyAsTempFileToClipboard)
            }

            SettingsCard(title: "截图体验") {
                SettingsToggle("显示浮动缩略图", subtitle: "在屏幕右下角快速美化、贴图或查看文件。", isOn: $prefs.showFloatingThumbnail)
                SettingsDivider()
                SettingsToggle("显示取色放大镜", subtitle: "选择区域时，更精确地查看像素与颜色。", isOn: $prefs.showMagnifier)
                SettingsDivider()
                SettingsToggle("播放提示音", subtitle: "用于截图完成及录屏开始、结束。", isOn: $prefs.playCaptureSound)
            }

            SettingsCard(title: "图片保存") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("图片格式")
                        .font(.system(size: 13, weight: .medium))
                    Picker("图片格式", selection: $prefs.screenshotFormat) {
                        Text("PNG · 无损").tag("PNG")
                        Text("JPEG · 更小文件").tag("JPEG")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                .padding(16)
                SettingsDivider()
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("默认保存位置")
                            .font(.system(size: 13, weight: .medium))
                        Text(prefs.saveDirectoryPath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(prefs.saveDirectoryPath)
                            .textSelection(.enabled)
                    }
                    Spacer(minLength: 4)
                    Button("更改…", action: selectSaveDirectory)
                        .accessibilityLabel("更改默认保存位置")
                }
                .padding(16)
            }
        }
    }

    private var recordingSettings: some View {
        VStack(spacing: 24) {
            SettingsCard(title: "声音") {
                SettingsToggle("录制系统声音", subtitle: "直接录制 Mac 播放的声音，无需额外驱动。", isOn: $prefs.captureSystemAudio)
                SettingsDivider()
                SettingsToggle("播放提示音", subtitle: "用于录屏开始、结束及截图完成。", isOn: $prefs.playCaptureSound)
            }

            SettingsCard(title: "画面") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("录屏帧率")
                        .font(.system(size: 13, weight: .medium))
                    Picker("录屏帧率", selection: $prefs.recordFPS) {
                        Text("30 FPS · 节省空间").tag(30)
                        Text("60 FPS · 更流畅").tag(60)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                .padding(16)
            }
        }
    }

    private var hotkeySettings: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsCard(title: "全局快捷键", footer: "快捷键在应用后台运行时同样可用。") {
                hotkeyRow("区域截图", symbol: "viewfinder", shortcut: prefs.hotkeyScreenshot.displayString)
                SettingsDivider()
                hotkeyRow("屏幕录制", symbol: "record.circle", shortcut: prefs.hotkeyRecording.displayString)
                SettingsDivider()
                hotkeyRow("滚动长截图", symbol: "rectangle.portrait", shortcut: prefs.hotkeyScroll.displayString)
                SettingsDivider()
                hotkeyRow("贴图到屏幕", symbol: "pin", shortcut: prefs.hotkeyPin.displayString)
            }

            Label {
                Text("截图时按 Enter 完成并复制，按 Esc 取消。")
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "keyboard")
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
        }
    }

    private func hotkeyRow(_ title: String, symbol: String, shortcut: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 13))
            Spacer()
            Text(shortcut)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(Color(nsColor: .quaternaryLabelColor).opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.07)))
        }
        .padding(16)
        .accessibilityElement(children: .combine)
    }

    private var cacheSettings: some View {
        VStack(spacing: 24) {
            SettingsCard(title: "存储空间") {
                HStack(spacing: 16) {
                    Image(systemName: "internaldrive")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(currentCacheSizeText)
                            .font(.system(size: 24, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text("临时截图与录屏文件")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Button("清理缓存", action: clearCache)
                }
                .padding(18)

                if !cleanCacheFeedback.isEmpty {
                    SettingsDivider()
                    Label(cleanCacheFeedback, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                }
            }

            SettingsCard(title: "自动清理", footer: "超期文件会在后台清理；超过容量上限时，优先移除较早的文件。") {
                SettingsToggle("自动清理缓存", subtitle: "按保留时间和容量上限管理临时文件。", isOn: $prefs.autoCleanCacheEnabled)
                SettingsDivider()
                VStack(spacing: 16) {
                    Picker("保留时间", selection: $prefs.cacheRetentionDays) {
                        Text("1 天").tag(1)
                        Text("3 天").tag(3)
                        Text("7 天").tag(7)
                        Text("30 天").tag(30)
                    }
                    Picker("容量上限", selection: $prefs.maxCacheSizeMB) {
                        Text("200 MB").tag(200)
                        Text("500 MB").tag(500)
                        Text("1 GB").tag(1000)
                        Text("2 GB").tag(2000)
                    }
                }
                .pickerStyle(.menu)
                .disabled(!prefs.autoCleanCacheEnabled)
                .padding(16)
            }

            Button {
                NSWorkspace.shared.open(CacheManager.shared.cacheDirectory)
            } label: {
                Label("在访达中打开缓存文件夹", systemImage: "folder")
            }
            .buttonStyle(.link)
            .font(.caption)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
        }
    }

    private var permissionSettings: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsCard(title: "访问权限") {
                permissionRow(
                    "屏幕录制",
                    subtitle: "截图、取色和屏幕录制所必需。",
                    symbol: "rectangle.inset.filled",
                    granted: hasScreenRecording,
                    type: "screen"
                )
                SettingsDivider()
                permissionRow(
                    "辅助功能",
                    subtitle: "用于长截图自动滚动；未开启时仍可手动滚动。",
                    symbol: "accessibility",
                    granted: hasAccessibility,
                    type: "accessibility"
                )
            }

            HStack(spacing: 12) {
                Button {
                    refreshPermissions(showFeedback: true)
                } label: {
                    Label("刷新状态", systemImage: "arrow.clockwise")
                }
                if !refreshFeedback.isEmpty {
                    Text(refreshFeedback)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            SettingsCard(title: "权限生效") {
                VStack(alignment: .leading, spacing: 14) {
                    Label {
                        Text("在系统设置中开启权限后，可能需要重新启动应用。若状态尚未更新，可先刷新，再重新启动。")
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "info.circle")
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                    Button {
                        Permissions.relaunchApp()
                    } label: {
                        Label("重新启动 cduyzhShot", systemImage: "arrow.counterclockwise")
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func permissionRow(_ title: String, subtitle: String, symbol: String, granted: Bool, type: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 19))
                .foregroundStyle(.secondary)
                .frame(width: 25)
                .padding(.top, 1)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                    Spacer(minLength: 4)
                    Label(granted ? "已授权" : "未授权", systemImage: granted ? "checkmark.circle.fill" : "circle.dashed")
                        .font(.caption)
                        .foregroundStyle(granted ? Color.green : Color.secondary)
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !granted {
                    Button("打开系统设置…") {
                        Permissions.openSystemSettings(for: type)
                    }
                    .controlSize(.small)
                    .accessibilityLabel("在系统设置中授权\(title)")
                    .padding(.top, 3)
                }
            }
        }
        .padding(16)
    }

    private var aboutSettings: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsCard(title: "当前安装") {
                HStack(spacing: 14) {
                    Image(systemName: "viewfinder")
                        .font(.system(size: 27, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 52, height: 52)
                        .background(Color.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 13))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("cduyzhShot")
                            .font(.system(size: 18, weight: .semibold))
                        Text("截图、录屏与滚动长截图")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(18)
                SettingsDivider()
                versionInfoRow("版本", value: AppVersion.current.version)
                SettingsDivider()
                versionInfoRow("构建号", value: AppVersion.current.build)
                if let buildDate = AppVersion.current.buildDateDisplayString {
                    SettingsDivider()
                    versionInfoRow("构建时间", value: buildDate)
                }
                SettingsDivider()
                versionInfoRow("版本发布日期", value: AppVersion.current.releaseDateDisplayString ?? "此版本尚无对应记录")
            }

            SettingsCard(title: "软件更新") {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("在线检查新版本")
                            .font(.system(size: 13, weight: .medium))
                        Text(updateManager.statusMessage)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    if updateManager.isChecking {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 70)
                    } else {
                        Button("检查更新") {
                            updateManager.checkForUpdates(isUserInitiated: true)
                        }
                    }
                }
                .padding(16)

                SettingsDivider()

                SettingsToggle("启动时自动检查更新", subtitle: "每次启动应用时静默检查更新，发现新版本时弹窗提示", isOn: $prefs.autoCheckForUpdates)

                SettingsDivider()

                DisclosureGroup(
                    isExpanded: $showAdvancedUpdateSettings,
                    content: {
                        VStack(alignment: .leading, spacing: 14) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("GitHub 个人访问令牌（PAT）")
                                    .font(.system(size: 12, weight: .medium))
                                Text("由于本项目为 GitHub 私人仓库，若要通过 GitHub API 检测私有 Release，需填入具备 repo 读取权限的 Token；如使用公开源或留空则默认以匿名方式请求。")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                SecureField("ghp_xxxxxxxxxxxxxxxxxxxx", text: $prefs.githubToken)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 12))
                            }

                            VStack(alignment: .leading, spacing: 5) {
                                Text("更新检测接口地址")
                                    .font(.system(size: 12, weight: .medium))
                                Text("支持 GitHub Releases API 或 release.json 清单。留空则恢复默认 GitHub 地址。")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                TextField(UpdateManager.defaultGitHubEndpoint, text: $prefs.customUpdateURL)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 12))
                            }
                        }
                        .padding(.top, 10)
                        .padding(.bottom, 4)
                    },
                    label: {
                        Text("高级更新源设置（私人仓库与自定义地址）")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                )
                .padding(16)
            }

            SettingsCard(title: "更新记录") {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("每次改动，清楚可见")
                            .font(.system(size: 13, weight: .medium))
                        Text("查看当前版本及历史版本的功能与修复。")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    Button("查看更新记录…") {
                        ReleaseNotesWindowController.shared.show()
                    }
                    .accessibilityLabel("查看 cduyzhShot 更新记录")
                }
                .padding(16)
            }
        }
    }

    private func versionInfoRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 20) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .textSelection(.enabled)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .accessibilityElement(children: .combine)
    }

    private func refreshPermissions(showFeedback: Bool = false) {
        hasScreenRecording = Permissions.hasScreenRecordingPermission
        hasAccessibility = Permissions.hasAccessibilityPermission
        if showFeedback {
            refreshFeedback = hasScreenRecording && hasAccessibility
                ? "所有权限均已授权。"
                : "已检查。更改权限后可重新启动应用。"
        }
    }

    private func refreshCacheSize() {
        currentCacheSizeText = CacheManager.shared.formattedCacheSize()
    }

    private func clearCache() {
        CacheManager.shared.clearAllCache()
        refreshCacheSize()
        cleanCacheFeedback = CacheManager.shared.getCacheSizeBytes() == 0
            ? "缓存已清理。"
            : "已完成清理，部分文件暂时无法移除。"
    }

    private func selectSaveDirectory() {
        let panel = NSOpenPanel()
        panel.title = "选择默认保存位置"
        panel.prompt = "选择"
        panel.directoryURL = prefs.saveDirectoryURL
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        let completion: (NSApplication.ModalResponse) -> Void = { response in
            if response == .OK, let url = panel.url {
                prefs.saveDirectoryPath = url.path
            }
        }
        if let window = SettingsWindowController.shared.window {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let footer: String?
    let content: Content

    init(title: String, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.06)))
            if let footer {
                Text(footer)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsToggle: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    init(_ title: String, subtitle: String, isOn: Binding<Bool>) {
        self.title = title
        self.subtitle = subtitle
        self._isOn = isOn
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityLabel(title)
                .accessibilityHint(subtitle)
        }
        .padding(16)
    }

}

private struct SettingsDivider: View {
    var body: some View {
        Divider().padding(.horizontal, 16)
    }
}

public final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    public static let shared = SettingsWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "cduyzhShot 设置"
        window.contentMinSize = NSSize(width: 740, height: 520)
        window.contentView = NSHostingView(rootView: SettingsView())
        window.isReleasedWhenClosed = false
        if !window.setFrameUsingName("cduyzhShot.Settings") {
            window.center()
        }
        window.setFrameAutosaveName("cduyzhShot.Settings")
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func show() {
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func showAbout() {
        show()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Notification.Name("cduyzhShot.settings.showAbout"), object: nil)
        }
    }

    public func windowWillClose(_ notification: Notification) {
        let hasOtherWindow = NSApp.windows.contains {
            $0 !== window && $0.isVisible && $0.styleMask.contains(.titled)
        }
        if !hasOtherWindow { NSApp.setActivationPolicy(.accessory) }
    }
}
