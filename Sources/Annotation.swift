import Cocoa

struct Annotation: Identifiable {
    let id = UUID()
    let type: ToolType
    var color: NSColor
    var strokeWidth: CGFloat
    let roughnessSeed: UInt32
    let createdAt: Date
    var expiresAt: Date?
    
    // For pen and laser
    var points: [CGPoint] = []
    
    // For arrows
    var arrowStart: CGPoint?
    var arrowEnd: CGPoint?
    var arrowControlPoint: CGPoint?
    
    // For rectangles and ovals
    var rect: CGRect?
    
    // For text
    var text: String?
    var textRect: CGRect?
    var fontSize: CGFloat = 28.0
    
    static func fontSize(for strokeWidth: CGFloat) -> CGFloat {
        switch strokeWidth {
        case 4: return 20.0
        case 8: return 28.0 // current default
        case 12: return 36.0
        case 20: return 48.0
        default: return 28.0
        }
    }
    
    init(type: ToolType, color: NSColor, strokeWidth: CGFloat) {
        self.type = type
        self.color = color
        self.strokeWidth = strokeWidth
        self.roughnessSeed = arc4random()
        self.createdAt = Date()
        self.fontSize = Annotation.fontSize(for: strokeWidth)
        
        if type == .laserPen {
            self.expiresAt = Date().addingTimeInterval(1.5) // Fades after 1.5 seconds
        }
    }
    
    var dynamicArrowStrokeWidth: CGFloat {
        guard type == .arrow, let start = arrowStart, let end = arrowEnd else { return strokeWidth }
        let length = hypot(end.x - start.x, end.y - start.y)
        let scale = length / 150.0
        return min(strokeWidth * 1.5, max(strokeWidth * 0.5, strokeWidth * scale))
    }
}
