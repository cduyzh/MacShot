import AppKit
import Foundation

// MARK: - Mockup Style
public enum StudioMockupStyle: String, CaseIterable, Identifiable {
    case none = "无外框"
    case macLight = "macOS 浅色"
    case macDark = "macOS 深色"
    case browserLight = "浏览器 浅色"
    case browserDark = "浏览器 深色"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .none: return "rectangle"
        case .macLight: return "macwindow"
        case .macDark: return "macwindow.on.rectangle"
        case .browserLight: return "globe"
        case .browserDark: return "globe.badge.chevron.backward"
        }
    }
}

// MARK: - Background Style
public enum StudioBackgroundStyle: String, CaseIterable, Identifiable {
    case blur = "智能模糊"
    case gradientSonoma = "晨曦暮光"
    case gradientAurora = "极光夜空"
    case gradientGraphite = "哑光钛金"
    case gradientOcean = "深蓝之海"
    case solidDark = "深空黑"
    case solidWhite = "纯净白"
    case transparent = "透明底"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .blur: return "sparkles"
        case .gradientSonoma: return "sun.horizon.fill"
        case .gradientAurora: return "aurora"
        case .gradientGraphite: return "square.fill"
        case .gradientOcean: return "water.waves"
        case .solidDark: return "circle.fill"
        case .solidWhite: return "circle"
        case .transparent: return "square.dashed"
        }
    }
}

// MARK: - Shadow Style
public enum StudioShadowStyle: String, CaseIterable, Identifiable {
    case none = "无"
    case soft = "柔和"
    case deep = "深邃"

    public var id: String { rawValue }
}

// MARK: - Aspect Ratio
public enum StudioAspectRatio: String, CaseIterable, Identifiable {
    case auto = "自适应"
    case ratio16_9 = "16:9"
    case ratio4_3 = "4:3"
    case ratio1_1 = "1:1"
    case ratio9_16 = "9:16"
    case ratio3_4 = "3:4"

    public var id: String { rawValue }

    public func ratioMultiplier() -> CGFloat? {
        switch self {
        case .auto: return nil
        case .ratio16_9: return 16.0 / 9.0
        case .ratio4_3: return 4.0 / 3.0
        case .ratio1_1: return 1.0
        case .ratio9_16: return 9.0 / 16.0
        case .ratio3_4: return 3.0 / 4.0
        }
    }
}

// MARK: - Studio State Model
public final class ScreenshotStudioModel: ObservableObject {
    @Published public var mockup: StudioMockupStyle = .macDark
    @Published public var background: StudioBackgroundStyle = .blur
    @Published public var padding: CGFloat = 44
    @Published public var cornerRadius: CGFloat = 14
    @Published public var shadow: StudioShadowStyle = .deep
    @Published public var aspectRatio: StudioAspectRatio = .auto
    @Published public var windowTitle: String = "cduyzhShot"

    public init() {}
}

extension ScreenshotStudioModel {
    /// 在主线程读取一次；后台仅使用此副本，不接触正在编辑的模型。
    func snapshot() -> ScreenshotStudioModel {
        let copy = ScreenshotStudioModel()
        copy.mockup = mockup
        copy.background = background
        copy.padding = padding
        copy.cornerRadius = cornerRadius
        copy.shadow = shadow
        copy.aspectRatio = aspectRatio
        copy.windowTitle = windowTitle
        return copy
    }

    func reset() {
        mockup = .macDark
        background = .blur
        padding = 44
        cornerRadius = 14
        shadow = .deep
        aspectRatio = .auto
        windowTitle = "cduyzhShot"
    }
}
