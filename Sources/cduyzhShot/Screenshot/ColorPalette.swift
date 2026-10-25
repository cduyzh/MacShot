import AppKit

public struct PresetColor: Equatable, Hashable {
    public let name: String
    public let color: NSColor

    public static let red = PresetColor(name: "红色", color: NSColor(red: 0.93, green: 0.27, blue: 0.27, alpha: 1.0))
    public static let orange = PresetColor(name: "橙色", color: NSColor(red: 0.98, green: 0.55, blue: 0.22, alpha: 1.0))
    public static let yellow = PresetColor(name: "黄色", color: NSColor(red: 0.95, green: 0.77, blue: 0.15, alpha: 1.0))
    public static let green = PresetColor(name: "绿色", color: NSColor(red: 0.20, green: 0.78, blue: 0.45, alpha: 1.0))
    public static let cyan = PresetColor(name: "青色", color: NSColor(red: 0.12, green: 0.74, blue: 0.88, alpha: 1.0))
    public static let blue = PresetColor(name: "蓝色", color: NSColor(red: 0.23, green: 0.51, blue: 0.96, alpha: 1.0))
    public static let purple = PresetColor(name: "紫色", color: NSColor(red: 0.65, green: 0.35, blue: 0.95, alpha: 1.0))
    public static let white = PresetColor(name: "白色", color: NSColor.white)
    public static let black = PresetColor(name: "黑色", color: NSColor.black)

    public static let all: [PresetColor] = [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .white, .black]
}
