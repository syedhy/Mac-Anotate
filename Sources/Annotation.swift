import Cocoa

enum ShapeFillStyle: Int, Codable {
    case hollow
    case translucent
    case filled
}

struct Annotation: Identifiable {
    private static var versionCounter: Int = 0
    private static func nextVersion() -> Int {
        versionCounter += 1
        return versionCounter
    }
    
    var id = UUID()
    var version: Int = 0
    let type: ToolType
    var color: NSColor { didSet { version = Annotation.nextVersion() } }
    var strokeWidth: CGFloat { didSet { version = Annotation.nextVersion() } }
    var fillStyle: ShapeFillStyle = .hollow { didSet { version = Annotation.nextVersion() } }
    let roughnessSeed: UInt32
    let createdAt: Date
    var expiresAt: Date? { didSet { version = Annotation.nextVersion() } }
    
    // For pen and laser
    var points: [CGPoint] = [] { didSet { version = Annotation.nextVersion() } }
    
    // For arrows
    var arrowStart: CGPoint? { didSet { version = Annotation.nextVersion() } }
    var arrowEnd: CGPoint? { didSet { version = Annotation.nextVersion() } }
    var arrowControlPoint: CGPoint? { didSet { version = Annotation.nextVersion() } }
    
    // For rectangles and ovals
    var rect: CGRect? { didSet { version = Annotation.nextVersion() } }
    
    // For text
    var text: String? { didSet { version = Annotation.nextVersion() } }
    var textRect: CGRect? { didSet { version = Annotation.nextVersion() } }
    var fontSize: CGFloat = 28.0 { didSet { version = Annotation.nextVersion() } }
    
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
        
    }
    
    var dynamicArrowStrokeWidth: CGFloat {
        guard (type == .arrow || type == .line), let start = arrowStart, let end = arrowEnd else { return strokeWidth }
        let length = hypot(end.x - start.x, end.y - start.y)
        let scale = length / 150.0
        return min(strokeWidth * 1.5, max(strokeWidth * 0.5, strokeWidth * scale))
    }
    
    mutating func scale(by factor: CGFloat, origin: CGPoint) {
        func scalePoint(_ p: CGPoint) -> CGPoint {
            return CGPoint(x: origin.x + (p.x - origin.x) * factor,
                           y: origin.y + (p.y - origin.y) * factor)
        }
        
        func scaleRect(_ r: CGRect) -> CGRect {
            let newOrigin = scalePoint(r.origin)
            let newSize = CGSize(width: r.width * factor, height: r.height * factor)
            return CGRect(origin: newOrigin, size: newSize)
        }
        
        self.strokeWidth *= factor
        self.fontSize *= factor
        
        switch type {
        case .arrow, .line:
            if let s = arrowStart { arrowStart = scalePoint(s) }
            if let e = arrowEnd { arrowEnd = scalePoint(e) }
            if let c = arrowControlPoint { arrowControlPoint = scalePoint(c) }
        case .rectangle, .oval:
            if let r = rect { rect = scaleRect(r) }
        case .text:
            if let r = textRect { textRect = scaleRect(r) }
        default:
            points = points.map(scalePoint)
        }
    }

    mutating func offsetBy(dx: CGFloat, dy: CGFloat) {
        func offsetPoint(_ point: CGPoint) -> CGPoint {
            CGPoint(x: point.x + dx, y: point.y + dy)
        }

        points = points.map(offsetPoint)

        if let start = arrowStart { arrowStart = offsetPoint(start) }
        if let end = arrowEnd { arrowEnd = offsetPoint(end) }
        if let control = arrowControlPoint { arrowControlPoint = offsetPoint(control) }
        if let r = rect { rect = r.offsetBy(dx: dx, dy: dy) }
        if let r = textRect { textRect = r.offsetBy(dx: dx, dy: dy) }
    }
}
