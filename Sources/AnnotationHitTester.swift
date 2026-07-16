import Cocoa

struct AnnotationHitTester {
    static let hitTolerance: CGFloat = 15.0
    
    enum HitResult: Equatable {
        case none
        case body
        case resizeHandle(index: Int)
        case controlHandle(index: Int)
    }
    
    static func hitTest(point: CGPoint, annotation: Annotation) -> HitResult {
        // Fast path: check bounding box first
        let bb = getBoundingBox(for: annotation)
        if !bb.insetBy(dx: -hitTolerance, dy: -hitTolerance).contains(point) {
            return .none
        }
        
        // First check handles
        if let handles = getHandles(for: annotation) {
            for (i, handle) in handles.enumerated() {
                if point.distance(to: handle) <= hitTolerance {
                    if (annotation.type == .arrow || annotation.type == .line) && i == 1 {
                        return .controlHandle(index: i)
                    }
                    return .resizeHandle(index: i)
                }
            }
        }
        
        // Then check body
        switch annotation.type {
        case .pen, .laserPen:
            guard annotation.points.count > 0 else { return .none }
            if annotation.points.count == 1 {
                if point.distance(to: annotation.points[0]) < hitTolerance { return .body }
                return .none
            }
            
            var prevPoint = annotation.points[0]
            for i in 1..<annotation.points.count {
                let currentPoint = annotation.points[i]
                if distanceToSegment(p: point, a: prevPoint, b: currentPoint) < hitTolerance {
                    return .body
                }
                prevPoint = currentPoint
            }
        case .arrow, .line:
            guard let start = annotation.arrowStart, let end = annotation.arrowEnd else { return .none }
            let baseControl = annotation.arrowControlPoint ?? CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
            
            var random = RoughPathGenerator.SeededRandom(seed: annotation.roughnessSeed)
            let dx = end.x - start.x
            let dy = end.y - start.y
            let length = hypot(dx, dy)
            let isStraight = annotation.arrowControlPoint == nil
            var finalControl = baseControl
            
            if isStraight {
                let dirX = dx / max(length, 1)
                let dirY = dy / max(length, 1)
                let bowAmount = random.nextFloat(in: -0.05...0.05) * length
                finalControl = CGPoint(x: baseControl.x - dirY * bowAmount, y: baseControl.y + dirX * bowAmount)
            } else {
                let varX = random.nextFloat(in: -0.01...0.01) * length
                let varY = random.nextFloat(in: -0.01...0.01) * length
                finalControl = CGPoint(x: baseControl.x + varX, y: baseControl.y + varY)
            }
            
            let dxCtrl = end.x - finalControl.x
            let dyCtrl = end.y - finalControl.y
            let angle = atan2(dyCtrl, dxCtrl)
            let dynamicStrokeWidth = min(16.0, max(2.0, length / 30.0))
            let headLength = annotation.type == .arrow ? dynamicStrokeWidth * 3.5 : 0
            let headWidth = annotation.type == .arrow ? dynamicStrokeWidth * 3.0 : 0
            let shaftEnd = CGPoint(x: end.x - headLength * cos(angle), y: end.y - headLength * sin(angle))
            
            var minDistance: CGFloat = .infinity
            let steps = 50
            var prevPoint = start
            for i in 1...steps {
                let t = CGFloat(i) / CGFloat(steps)
                let x = pow(1 - t, 2) * start.x + 2 * (1 - t) * t * finalControl.x + pow(t, 2) * shaftEnd.x
                let y = pow(1 - t, 2) * start.y + 2 * (1 - t) * t * finalControl.y + pow(t, 2) * shaftEnd.y
                let currentPoint = CGPoint(x: x, y: y)
                let d = distanceToSegment(p: point, a: prevPoint, b: currentPoint)
                if d < minDistance { minDistance = d }
                prevPoint = currentPoint
            }
            
            if annotation.type == .arrow {
                let p1 = CGPoint(x: end.x - headLength * cos(angle) - headWidth/2 * sin(angle),
                                 y: end.y - headLength * sin(angle) + headWidth/2 * cos(angle))
                let p2 = CGPoint(x: end.x - headLength * cos(angle) + headWidth/2 * sin(angle),
                                 y: end.y - headLength * sin(angle) - headWidth/2 * cos(angle))
                
                let d1 = distanceToSegment(p: point, a: end, b: p1)
                let d2 = distanceToSegment(p: point, a: p1, b: p2)
                let d3 = distanceToSegment(p: point, a: p2, b: end)
                
                minDistance = min(minDistance, min(d1, min(d2, d3)))
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
        case .select, .laserPointer:
            break
        }
        
        return .none
    }
    
    static func getHandles(for annotation: Annotation) -> [CGPoint]? {
        switch annotation.type {
        case .arrow, .line:
            guard let start = annotation.arrowStart, let end = annotation.arrowEnd else { return nil }
            let control = annotation.arrowControlPoint ?? CGPoint(x: (start.x + end.x)/2, y: (start.y + end.y)/2)
            let strokeW = annotation.dynamicArrowStrokeWidth
            let headL = annotation.type == .arrow ? strokeW * 3.5 : 0
            let dxCtrl = end.x - control.x
            let dyCtrl = end.y - control.y
            let angle = atan2(dyCtrl, dxCtrl)
            let shaftEnd = CGPoint(x: end.x - headL * 1.2 * cos(angle), y: end.y - headL * 1.2 * sin(angle))
            
            let m = CGPoint(x: 0.25 * start.x + 0.5 * control.x + 0.25 * shaftEnd.x, y: 0.25 * start.y + 0.5 * control.y + 0.25 * shaftEnd.y)
            
            let handleRadius: CGFloat = 6.0
            
            let startToM_dx = m.x - start.x
            let startToM_dy = m.y - start.y
            let startToMLen = hypot(startToM_dx, startToM_dy)
            let insetStart = startToMLen > 0 ? CGPoint(x: start.x + (startToM_dx/startToMLen)*handleRadius, y: start.y + (startToM_dy/startToMLen)*handleRadius) : start
            
            let endToM_dx = m.x - end.x
            let endToM_dy = m.y - end.y
            let endToMLen = hypot(endToM_dx, endToM_dy)
            let insetEnd = endToMLen > 0 ? CGPoint(x: end.x + (endToM_dx/endToMLen)*handleRadius, y: end.y + (endToM_dy/endToMLen)*handleRadius) : end

            return [insetStart, m, insetEnd]
        case .rectangle, .oval, .text:
            if annotation.type == .text {
                guard let r = annotation.textRect else { return nil }
                return [
                    CGPoint(x: r.minX - 12, y: r.midY), // 0: left
                    CGPoint(x: r.maxX + 12, y: r.midY), // 1: right
                    CGPoint(x: r.maxX + 12, y: r.minY - 12)  // 2: bottom-right (scale)
                ]
            } else {
                guard let r = annotation.rect else { return nil }
                return [
                    CGPoint(x: r.minX, y: r.minY),
                    CGPoint(x: r.maxX, y: r.minY),
                    CGPoint(x: r.minX, y: r.maxY),
                    CGPoint(x: r.maxX, y: r.maxY)
                ]
            }
        case .pen, .laserPen:
            guard annotation.points.count > 1 else { return nil }
            var minX = annotation.points[0].x
            var minY = annotation.points[0].y
            var maxX = annotation.points[0].x
            var maxY = annotation.points[0].y
            for p in annotation.points {
                if p.x < minX { minX = p.x }
                if p.x > maxX { maxX = p.x }
                if p.y < minY { minY = p.y }
                if p.y > maxY { maxY = p.y }
            }
            let pad: CGFloat = 5.0
            return [
                CGPoint(x: minX - pad, y: minY - pad),
                CGPoint(x: maxX + pad, y: minY - pad),
                CGPoint(x: minX - pad, y: maxY + pad),
                CGPoint(x: maxX + pad, y: maxY + pad)
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

    static func getBoundingBox(for annotation: Annotation) -> CGRect {
        switch annotation.type {
        case .rectangle, .oval:
            return annotation.rect ?? .zero
        case .arrow, .line:
            return getRenderedArrowBoundingBox(for: annotation)
        case .pen, .laserPen:
            guard !annotation.points.isEmpty else { return .zero }
            var minX = annotation.points[0].x
            var minY = annotation.points[0].y
            var maxX = annotation.points[0].x
            var maxY = annotation.points[0].y
            for p in annotation.points {
                if p.x < minX { minX = p.x }
                if p.x > maxX { maxX = p.x }
                if p.y < minY { minY = p.y }
                if p.y > maxY { maxY = p.y }
            }
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        case .text:
            return annotation.textRect ?? .zero
        default:
            return .zero
        }
    }

    private static func getRenderedArrowBoundingBox(for annotation: Annotation) -> CGRect {
        guard annotation.arrowStart != nil, annotation.arrowEnd != nil else { return .zero }

        let shaftPath = AnnotationRenderer.cachedVariableStrokePath(from: annotation, pass: 0)
        var boundingBox = shaftPath.bounds

        if annotation.type == .arrow {
            let headPath = AnnotationRenderer.cachedArrowHeadPath(from: annotation, pass: 0)
            let headBox = headPath.bounds
            boundingBox = boundingBox.isEmpty ? headBox : boundingBox.union(headBox)
        }

        return boundingBox
    }
    
    static func getGroupBoundingBox(for annotations: [Annotation], selectedIDs: Set<UUID>) -> CGRect? {
        var unionRect: CGRect?
        for id in selectedIDs {
            if let ann = annotations.first(where: { $0.id == id }) {
                let bb = getBoundingBox(for: ann)
                if let existing = unionRect {
                    unionRect = existing.union(bb)
                } else {
                    unionRect = bb
                }
            }
        }
        return unionRect?.insetBy(dx: -10, dy: -10)
    }
}

extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        return hypot(x - other.x, y - other.y)
    }
}
