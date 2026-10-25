import AppKit
import SwiftUI

final class StudioPresentation: ObservableObject {
    @Published var preview: NSImage?
    @Published var sourceSize = ""
    @Published var outputSize = ""
    @Published var isRendering = false
    @Published var isExporting = false
    @Published var message = ""
}

struct ScreenshotStudioView: View {
    @ObservedObject var model: ScreenshotStudioModel
    @ObservedObject var presentation: StudioPresentation
    let onChange: () -> Void
    let onCopy: () -> Void
    let onSave: () -> Void
    let onPin: () -> Void
    let onClose: () -> Void

    private var canExport: Bool {
        presentation.preview != nil && !presentation.isRendering && !presentation.isExporting
    }

    var body: some View {
        HStack(spacing: 0) {
            canvas
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            inspector
                .frame(width: 310)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onReceive(model.objectWillChange) { _ in onChange() }
        .background {
            Button("关闭", action: onClose)
                .keyboardShortcut(.cancelAction)
                .hidden()
        }
    }

    private var canvas: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Label("预览", systemImage: "photo")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                if presentation.isRendering || presentation.isExporting {
                    ProgressView().controlSize(.small).scaleEffect(0.75)
                    Text(presentation.isExporting ? "正在保存" : "正在更新")
                        .font(.system(size: 11))
                } else {
                    Text("原图 \(presentation.sourceSize)")
                        .font(.system(size: 11, design: .monospaced))
                }
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 24)
            .padding(.vertical, 18)

            GeometryReader { geometry in
                ZStack {
                    if let preview = presentation.preview {
                        Image(nsImage: preview)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .background {
                                if model.background == .transparent {
                                    TransparencyGrid()
                                }
                            }
                            .opacity(presentation.isRendering ? 0.65 : 1)
                            .accessibilityLabel("美化图片预览")
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 36, weight: .ultraLight))
                            Text(presentation.isRendering ? "正在准备画布…" : "预览暂不可用")
                                .font(.system(size: 13))
                        }
                        .foregroundStyle(.tertiary)
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)

            HStack(spacing: 6) {
                Image(systemName: presentation.message.isEmpty ? "arrow.up.left.and.arrow.down.right" : "info.circle")
                    .accessibilityHidden(true)
                Text(presentation.message.isEmpty ? "\(presentation.outputSize) px · PNG" : presentation.message)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer()
                Text("按 Esc 关闭")
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 24)
            .padding(.bottom, 18)
        }
        .background(Color.primary.opacity(0.025))
    }

    private var inspector: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("让截图更出彩")
                        .font(.system(size: 18, weight: .semibold))
                    Text("一点留白，恰到好处。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: { model.reset() }) {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                .help("恢复默认样式")
                .accessibilityLabel("恢复默认样式")
            }
            .padding(22)
            .disabled(presentation.isExporting)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    section("窗口外框", symbol: "macwindow") {
                        Picker("外框", selection: $model.mockup) {
                            ForEach(StudioMockupStyle.allCases) { style in
                                Text(style.rawValue).tag(style)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                        if model.mockup != .none {
                            TextField("窗口标题", text: $model.windowTitle)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityLabel("样机窗口标题")
                        }
                    }
                    section("背景", symbol: "square.stack.3d.up") {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 12) {
                            ForEach(StudioBackgroundStyle.allCases) { style in
                                backgroundChoice(style)
                            }
                        }
                    }
                    section("构图", symbol: "slider.horizontal.3") {
                        valueSlider("留白", value: $model.padding, range: 0...100)
                        valueSlider("圆角", value: $model.cornerRadius, range: 0...40)
                        VStack(alignment: .leading, spacing: 9) {
                            Text("阴影").font(.system(size: 12)).foregroundStyle(.secondary)
                            Picker("阴影", selection: $model.shadow) {
                                ForEach(StudioShadowStyle.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }
                    }
                    section("画布比例", symbol: "aspectratio") {
                        Picker("比例", selection: $model.aspectRatio) {
                            ForEach(StudioAspectRatio.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                        Text("画幅自动扩展，保留完整截图。")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 24)
            }
            .disabled(presentation.isExporting)
            Divider()
            VStack(spacing: 10) {
                Button(action: onCopy) {
                    HStack {
                        Label("复制并完成", systemImage: "doc.on.doc")
                        Spacer()
                        Text("↩").foregroundStyle(.white.opacity(0.75))
                    }
                    .frame(maxWidth: .infinity, minHeight: 22)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: [])
                .disabled(!canExport)
                HStack {
                    Button(action: onSave) {
                        Label("另存为…", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .keyboardShortcut("s", modifiers: .command)
                    .help("另存为 PNG（⌘S）")
                    Button(action: onPin) {
                        Image(systemName: "pin")
                    }
                    .keyboardShortcut("p", modifiers: .option)
                    .help("钉在屏幕上（⌥P）")
                    .accessibilityLabel("钉在屏幕上")
                }
                .buttonStyle(.bordered)
                .disabled(!canExport)
            }
            .controlSize(.large)
            .padding(18)
        }
        .background(.regularMaterial)
    }

    private func section<Content: View>(_ title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Label(title, systemImage: symbol)
                .font(.system(size: 12, weight: .semibold))
            content()
        }
    }

    private func valueSlider(_ title: String, value: Binding<CGFloat>, range: ClosedRange<CGFloat>) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value.wrappedValue)) px")
                    .monospacedDigit()
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            Slider(value: value, in: range)
                .accessibilityLabel(title)
                .accessibilityValue("\(Int(value.wrappedValue)) 像素")
        }
    }

    private func backgroundChoice(_ style: StudioBackgroundStyle) -> some View {
        let selected = model.background == style
        return Button { model.background = style } label: {
            VStack(spacing: 6) {
                ZStack {
                    backgroundSwatch(style)
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.accentColor)
                            .font(.system(size: 18, weight: .semibold))
                            .shadow(color: .black.opacity(0.15), radius: 2)
                    }
                }
                .frame(height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: selected ? 2 : 0.5)
                }
                Text(shortName(style))
                    .font(.system(size: 10, weight: selected ? .medium : .regular))
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(style.rawValue)
        .accessibilityLabel(style.rawValue)
        .accessibilityValue(selected ? "已选择" : "未选择")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    @ViewBuilder private func backgroundSwatch(_ style: StudioBackgroundStyle) -> some View {
        switch style {
        case .blur:
            LinearGradient(colors: [.gray.opacity(0.25), .blue.opacity(0.35), .purple.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay { Image(systemName: "drop.halffull").foregroundStyle(.secondary) }
        case .gradientSonoma:
            LinearGradient(colors: [Color(red: 0.52, green: 0.24, blue: 0.78), Color(red: 0.95, green: 0.42, blue: 0.35), Color(red: 0.98, green: 0.72, blue: 0.38)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .gradientAurora:
            LinearGradient(colors: [Color(red: 0.06, green: 0.1, blue: 0.24), Color(red: 0.15, green: 0.72, blue: 0.55)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .gradientGraphite:
            LinearGradient(colors: [.gray.opacity(0.7), .black], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .gradientOcean:
            LinearGradient(colors: [Color(red: 0.08, green: 0.22, blue: 0.62), Color(red: 0.12, green: 0.52, blue: 0.88)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .solidDark: Color(white: 0.08)
        case .solidWhite: Color(white: 0.98)
        case .transparent: TransparencyGrid()
        }
    }

    private func shortName(_ style: StudioBackgroundStyle) -> String {
        switch style {
        case .blur: return "随图"
        case .gradientSonoma: return "晨曦"
        case .gradientAurora: return "极光"
        case .gradientGraphite: return "钛金"
        case .gradientOcean: return "深蓝"
        case .solidDark: return "深空黑"
        case .solidWhite: return "纯净白"
        case .transparent: return "透明"
        }
    }
}

private struct TransparencyGrid: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(nsColor: .controlBackgroundColor)))
            let step: CGFloat = 10
            for row in 0..<Int(ceil(size.height / step)) {
                for column in 0..<Int(ceil(size.width / step)) where (row + column).isMultiple(of: 2) {
                    context.fill(Path(CGRect(x: CGFloat(column) * step, y: CGFloat(row) * step, width: step, height: step)), with: .color(.primary.opacity(0.06)))
                }
            }
        }
        .accessibilityHidden(true)
    }
}
