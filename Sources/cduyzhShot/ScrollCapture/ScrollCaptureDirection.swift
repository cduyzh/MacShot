import Foundation

/// 文档浏览方向，而不是触控板手势方向：向下查看后面的内容，向上查看前面的内容。
public enum ScrollCaptureDirection: Equatable {
    case up
    case down

    var opposite: ScrollCaptureDirection { self == .up ? .down : .up }
    var title: String { self == .up ? "向上" : "向下" }
    var symbol: String { self == .up ? "arrow.up" : "arrow.down" }
}
