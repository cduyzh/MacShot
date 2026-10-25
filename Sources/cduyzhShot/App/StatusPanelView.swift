import AppKit
import SwiftUI

/// 所有文案来自同一份快照；预览可传入固定快照，不触碰系统权限或截屏。
struct StatusPanelSnapshot: Equatable {
    var version = AppVersion.current.displayString
    var screenGranted = false
    var accessibilityGranted = false
    var recording = false
    var scrollCapturing = false
    var scrollHeight = 0
    var pinCount = 0
    var visiblePinCount = 0
    var pinsHidden = false
    var screenshotShortcut = "⌃A"
    var scrollShortcut = "⌥S"
    var recordingShortcut = "⌃["
    var pinShortcut = "⌥P"
    var hasUnreadRelease = false

    var statusTitle: String {
        if recording { return "录屏会话进行中" }
        if scrollCapturing { return "正在截取长图" }
        return screenGranted ? "准备就绪" : "需要屏幕录制权限"
    }
    var statusColor: Color { recording ? .red : (scrollCapturing ? .blue : (screenGranted ? .green : .orange)) }

    static var preview: StatusPanelSnapshot {
        var snapshot = StatusPanelSnapshot()
        snapshot.screenGranted = true
        snapshot.accessibilityGranted = true
        return snapshot
    }
}

enum StatusPanelAction: Hashable {
    case screenshot, scroll, record, pin, studio, settings
    case screenPermission, accessibilityPermission, togglePins, closePins, more, quit
    case clearCache, checkUpdates, releaseNotes, scrollExample, relaunch, about, dismiss
}

final class StatusPanelModel: ObservableObject {
    @Published var snapshot = StatusPanelSnapshot()
    @Published var focusedAction: StatusPanelAction?
}

struct StatusPanelContent: View {
    @ObservedObject var model: StatusPanelModel
    let onAction: (StatusPanelAction) -> Void

    var body: some View {
        StatusPanelView(snapshot: model.snapshot, focusedAction: model.focusedAction, onAction: onAction,
                        onFocusChange: { model.focusedAction = $0 })
    }
}

/// 与菜单栏 popover、独立视觉预览共用的视图。
struct StatusPanelView: View {
    let snapshot: StatusPanelSnapshot
    var focusedAction: StatusPanelAction? = nil
    var onAction: (StatusPanelAction) -> Void = { _ in }
    var onFocusChange: (StatusPanelAction?) -> Void = { _ in }
    @FocusState private var nativeFocus: StatusPanelAction?

    private let secondary = Color(nsColor: .secondaryLabelColor)

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.bottom, 17)
            VStack(spacing: 4) {
                captureRow(.screenshot, title: "区域截图", detail: "框选区域，立即标注与复制", symbol: "viewfinder", color: .blue, shortcut: snapshot.screenshotShortcut)
                captureRow(.scroll, title: "滚动长截图", detail: snapshot.scrollCapturing ? "已捕获 \(snapshot.scrollHeight.formatted()) px · 点击完成" : "向上或向下，拼成一张长图", symbol: "arrow.up.and.down", color: .purple, shortcut: snapshot.scrollShortcut)
                captureRow(.record, title: snapshot.recording ? "结束录屏会话" : "屏幕录制", detail: snapshot.recording ? "停止或取消当前会话" : "录下屏幕画面", symbol: snapshot.recording ? "stop.circle.fill" : "record.circle", color: .red, shortcut: snapshot.recordingShortcut)
            }
            .padding(5)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 13))

            HStack(spacing: 8) {
                compactAction(.pin, title: "剪贴板贴图", symbol: "pin", shortcut: snapshot.pinShortcut)
                compactAction(.studio, title: "图片美化", symbol: "slider.horizontal.3", shortcut: "⌥E")
            }
            .padding(.top, 10)

            HStack {
                Text("权限状态").font(.system(size: 11, weight: .medium)).foregroundStyle(secondary)
                Spacer()
                Text("点击前往系统设置").font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            .padding(.top, 18)
            .padding(.bottom, 6)
            VStack(spacing: 1) {
                permissionRow(.screenPermission, title: "屏幕录制", detail: "截图与录屏", symbol: "display", granted: snapshot.screenGranted)
                permissionRow(.accessibilityPermission, title: "辅助功能", detail: "自动滚动", symbol: "hand.raised", granted: snapshot.accessibilityGranted)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 11))

            HStack(spacing: 6) {
                Image(systemName: "pin.fill").font(.system(size: 11)).foregroundStyle(secondary)
                Text(pinSummary)
                    .font(.system(size: 11)).foregroundStyle(secondary)
                Spacer()
                iconButton(.togglePins, symbol: snapshot.pinsHidden ? "eye" : "eye.slash", label: snapshot.pinsHidden ? "显示所有贴图" : "隐藏所有贴图", enabled: snapshot.pinCount > 0)
                iconButton(.closePins, symbol: "xmark.rectangle", label: "关闭所有贴图", enabled: snapshot.pinCount > 0)
            }
            .padding(.top, 10)
            .padding(.horizontal, 5)

            Divider().padding(.top, 10).padding(.bottom, 9)
            HStack {
                Button { onAction(.more) } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "ellipsis.circle")
                        Text("更多")
                        if snapshot.hasUnreadRelease { Circle().fill(Color.blue).frame(width: 5, height: 5).accessibilityLabel("有新版本记录") }
                        Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
                    }
                    .font(.system(size: 12)).padding(.horizontal, 7).padding(.vertical, 7)
                }
                .buttonStyle(StatusControlStyle(isFocused: focusedAction == .more))
                .focused($nativeFocus, equals: .more)
                .focusEffectDisabled()
                .accessibilityLabel("更多操作：缓存、更新、帮助与重启")
                Spacer()
                Text("左键截图 · 右键状态").font(.system(size: 10)).foregroundStyle(.tertiary)
                Spacer()
                Button { onAction(.quit) } label: {
                    Label("退出", systemImage: "power").font(.system(size: 12)).padding(.horizontal, 7).padding(.vertical, 7)
                }
                .buttonStyle(StatusControlStyle(isFocused: focusedAction == .quit))
                .focused($nativeFocus, equals: .quit)
                .focusEffectDisabled()
                .accessibilityLabel("退出 cduyzhShot")
            }
        }
        .padding(18)
        .frame(width: 368)
        .modifier(StatusPanelGlassSurface())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("cduyzhShot 状态与操作")
        .onAppear { nativeFocus = focusedAction }
        .onChange(of: focusedAction) { _, action in nativeFocus = action }
        .onChange(of: nativeFocus) { _, action in onFocusChange(action) }
    }

    private var pinSummary: String {
        if snapshot.pinCount == 0 { return "暂无贴图" }
        if snapshot.pinsHidden { return "\(snapshot.pinCount) 张贴图 · 已隐藏" }
        if snapshot.visiblePinCount == snapshot.pinCount { return "\(snapshot.pinCount) 张贴图 · 显示中" }
        return "\(snapshot.pinCount) 张贴图 · \(snapshot.visiblePinCount) 张显示"
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 23, weight: .medium))
                .foregroundStyle(.blue)
                .frame(width: 40, height: 40)
                .background(Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text("cduyzhShot").font(.system(size: 18, weight: .semibold))
                    Text(snapshot.version).font(.system(size: 10)).foregroundStyle(.tertiary)
                }
                HStack(spacing: 5) {
                    Circle().fill(snapshot.statusColor).frame(width: 5, height: 5)
                    Text(snapshot.statusTitle).font(.system(size: 11)).foregroundStyle(secondary)
                }
                .accessibilityElement(children: .combine)
            }
            Spacer(minLength: 0)
            iconButton(.settings, symbol: "gearshape", label: "打开设置（⌘,）")
        }
    }

    private func captureRow(_ action: StatusPanelAction, title: String, detail: String, symbol: String, color: Color, shortcut: String) -> some View {
        Button { onAction(action) } label: {
            HStack(spacing: 11) {
                Image(systemName: symbol).font(.system(size: 19, weight: .medium))
                    .foregroundStyle(color).frame(width: 37, height: 37)
                    .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    Text(detail).font(.system(size: 10)).foregroundStyle(secondary).lineLimit(1)
                }
                Spacer(minLength: 3)
                Text(shortcut).font(.system(size: 11, design: .monospaced)).foregroundStyle(secondary)
                    .padding(.horizontal, 5).padding(.vertical, 3)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 4))
            }
            .padding(.horizontal, 9).padding(.vertical, 9).contentShape(Rectangle())
        }
        .buttonStyle(StatusControlStyle(isFocused: focusedAction == action))
        .focused($nativeFocus, equals: action)
        .focusEffectDisabled()
        .accessibilityLabel("\(title)，\(detail)，快捷键 \(shortcut)")
    }

    private func compactAction(_ action: StatusPanelAction, title: String, symbol: String, shortcut: String) -> some View {
        Button { onAction(action) } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(.secondary)
                Text(title).font(.system(size: 11, weight: .medium))
                Spacer(minLength: 0)
                Text(shortcut).font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10).padding(.vertical, 11)
            .frame(maxWidth: .infinity)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(StatusControlStyle(isFocused: focusedAction == action))
        .focused($nativeFocus, equals: action)
        .focusEffectDisabled()
        .accessibilityLabel("\(title)，快捷键 \(shortcut)")
    }

    private func permissionRow(_ action: StatusPanelAction, title: String, detail: String, symbol: String, granted: Bool) -> some View {
        Button { onAction(action) } label: {
            HStack(spacing: 7) {
                Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(secondary).frame(width: 18)
                Text(title).font(.system(size: 11, weight: .medium))
                Text(detail).font(.system(size: 10)).foregroundStyle(.tertiary)
                Spacer()
                Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(granted ? Color.green : .orange).font(.system(size: 10))
                Text(granted ? "已授权" : "未授权").font(.system(size: 10)).foregroundStyle(granted ? secondary : .orange)
                Image(systemName: "chevron.right").font(.system(size: 8)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 5).padding(.vertical, 8).contentShape(Rectangle())
        }
        .buttonStyle(StatusControlStyle(isFocused: focusedAction == action))
        .focused($nativeFocus, equals: action)
        .focusEffectDisabled()
        .accessibilityLabel("\(title)，\(granted ? "已授权" : "未授权")，用于\(detail)，打开系统设置")
    }

    private func iconButton(_ action: StatusPanelAction, symbol: String, label: String, enabled: Bool = true) -> some View {
        Button { onAction(action) } label: {
            Image(systemName: symbol).font(.system(size: 14)).frame(width: 28, height: 28).contentShape(Rectangle())
        }
        .buttonStyle(StatusControlStyle(isFocused: focusedAction == action))
        .focused($nativeFocus, equals: action)
        .focusEffectDisabled()
        .disabled(!enabled)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// Use the system Liquid Glass surface on macOS 26/27 while retaining the
/// regular material fallback for the macOS 14–25 deployment range.
private struct StatusPanelGlassSurface: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else {
            content.background(.regularMaterial)
        }
    }
}

private struct StatusControlStyle: ButtonStyle {
    let isFocused: Bool
    func makeBody(configuration: Configuration) -> some View {
        StatusControlBody(configuration: configuration, isFocused: isFocused)
    }
    private struct StatusControlBody: View {
        let configuration: ButtonStyleConfiguration
        let isFocused: Bool
        @State private var hovering = false
        @Environment(\.isEnabled) private var enabled
        var body: some View {
            configuration.label
                .foregroundStyle(Color.primary)
                .background(Color.primary.opacity(configuration.isPressed ? 0.1 : (hovering && enabled ? 0.055 : 0)), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor.opacity(isFocused ? 0.85 : 0), lineWidth: 2))
                .opacity(enabled ? 1 : 0.3)
                .onHover { hovering = $0 }
        }
    }
}
