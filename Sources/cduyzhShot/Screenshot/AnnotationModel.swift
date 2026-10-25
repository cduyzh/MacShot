import AppKit

public enum AnnotationTool: String, CaseIterable {
    case select = "选择"
    case rect = "矩形"
    case ellipse = "圆形"
    case arrow = "箭头"
    case line = "直线"
    case mosaic = "马赛克"
    case text = "文字"
    case stepBadge = "序号"

    public var shortcutNumber: String? {
        switch self {
        case .rect: return "1"
        case .ellipse: return "2"
        case .arrow: return "3"
        case .mosaic: return "6"
        case .text: return "7"
        case .stepBadge: return "8"
        default: return nil
        }
    }
}

public struct AnnotationItem: Identifiable, Equatable {
    public static let defaultLineWidth: CGFloat = 4.0

    public let id: UUID
    public var tool: AnnotationTool
    public var startPoint: CGPoint
    public var endPoint: CGPoint
    public var color: NSColor
    public var lineWidth: CGFloat
    public var text: String
    public var fontSize: CGFloat
    public var badgeNumber: Int
    public var isFilled: Bool

    public init(
        id: UUID = UUID(),
        tool: AnnotationTool,
        startPoint: CGPoint,
        endPoint: CGPoint,
        color: NSColor = PresetColor.red.color,
        lineWidth: CGFloat = AnnotationItem.defaultLineWidth,
        text: String = "",
        fontSize: CGFloat = 16.0,
        badgeNumber: Int = 1,
        isFilled: Bool = false
    ) {
        self.id = id
        self.tool = tool
        self.startPoint = startPoint
        self.endPoint = endPoint
        self.color = color
        self.lineWidth = lineWidth
        self.text = text
        self.fontSize = fontSize
        self.badgeNumber = badgeNumber
        self.isFilled = isFilled
    }

    public var boundingRect: CGRect {
        let x = min(startPoint.x, endPoint.x)
        let y = min(startPoint.y, endPoint.y)
        let w = abs(endPoint.x - startPoint.x)
        let h = abs(endPoint.y - startPoint.y)
        return CGRect(x: x, y: y, width: max(w, 1), height: max(h, 1))
    }
}
