import Cocoa

struct AnnotationHitTester {
    static let hitTolerance: CGFloat = 10.0
    
    enum HitResult: Equatable {
        case none
        case body
        case resizeHandle(index: Int)
        case controlHandle(index: Int)
    }
    
    static func hitTest(point: CGPoint, annotation: Annotation) -> HitResult {
        // First check handles
        if let handles = getHandles(for: annotation) {
            for (i, handle) in handles.enumerated() {
                if point.distance(to: handle) <= hitTolerance {
                    if annotation.type == .arrow && i == 1 {
                        return .controlHandle(index: i)
                    }
                    return .resizeHandle(index: i)
                }
            }
        }
        
        // Then check body
        switch annotation.type {
        case .pen, .laser:
            // Just check distance to any point
            for p in annotation.points {
                if point.distance(to: p) < hitTolerance { return .body }
            }
        case .arrow:
            guard let start = annotation.arrowStart, let end = annotation.arrowEnd else { return .none }
            let control = annotation.arrowControlPoint ?? CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
            
            // Sample distance to quadratic bezier curve
            var minDistance: CGFloat = .infinity
            let steps = 20
            for i in 0...steps {
                let t = CGFloat(i) / CGFloat(steps)
                let x = pow(1 - t, 2) * start.x + 2 * (1 - t) * t * control.x + pow(t, 2) * end.x
                let y = pow(1 - t, 2) * start.y + 2 * (1 - t) * t * control.y + pow(t, 2) * end.y
                let d = point.distance(to: CGPoint(x: x, y: y))
                if d < minDistance { minDistance = d }
            }
            if minDistance < hitTolerance { return .body }
        case .rectangle, .oval:
            guard let rect = annotation.rect else { return .none }
            // Check if inside or on edge (just inside for now)
            if rect.insetBy(dx: -hitTolerance, dy: -hitTolerance).contains(point) {
                return .body
            }
        case .text:
            guard let rect = annotation.textRect else { return .none }
            if rect.insetBy(dx: -hitTolerance, dy: -hitTolerance).contains(point) {
                return .body
            }
        case .select:
            break
        }
        
        return .none
    }
    
    static func getHandles(for annotation: Annotation) -> [CGPoint]? {
        switch annotation.type {
        case .arrow:
            guard let start = annotation.arrowStart, let end = annotation.arrowEnd else { return nil }
            let control = annotation.arrowControlPoint ?? CGPoint(x: (start.x + end.x)/2, y: (start.y + end.y)/2)
            return [start, control, end]
        case .rectangle, .oval, .text:
            let rect: CGRect
            if annotation.type == .text {
                guard let r = annotation.textRect else { return nil }
                rect = r
            } else {
                guard let r = annotation.rect else { return nil }
                rect = r
            }
            return [
                CGPoint(x: rect.minX, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.minY),
                CGPoint(x: rect.minX, y: rect.maxY),
                CGPoint(x: rect.maxX, y: rect.maxY)
            ]
        default:
            return nil
        }
    }
    
    private static func distanceToSegment(p: CGPoint, a: CGPoint, b: CGPoint) -> CGFloat {
        let l2 = (a.x - b.x)*(a.x - b.x) + (a.y - b.y)*(a.y - b.y)
        if l2 == 0 { return p.distance(to: a) }
        var t = ((p.x - a.x) * (b.x - a.x) + (p.y - a.y) * (b.y - a.y)) / l2
        t = max(0, min(1, t))
        let proj = CGPoint(x: a.x + t * (b.x - a.x), y: a.y + t * (b.y - a.y))
        return p.distance(to: proj)
    }
}

extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        return hypot(x - other.x, y - other.y)
    }
}
