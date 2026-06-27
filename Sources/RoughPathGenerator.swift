import Cocoa

class RoughPathGenerator {
    
    struct SeededRandom {
        var state: UInt32
        
        init(seed: UInt32) {
            self.state = seed
        }
        
        mutating func next() -> UInt32 {
            state = state &* 1664525 &+ 1013904223
            return state
        }
        
        mutating func nextFloat() -> CGFloat {
            return CGFloat(next() % 10000) / 10000.0
        }
        
        mutating func nextFloat(in range: ClosedRange<CGFloat>) -> CGFloat {
            let val = nextFloat()
            return range.lowerBound + val * (range.upperBound - range.lowerBound)
        }
    }
    
    static func generateDoodlePath(from annotation: Annotation, pass: Int) -> NSBezierPath {
        let path = NSBezierPath()
        // Use a deterministic seed for the organic variations
        var random = SeededRandom(seed: annotation.roughnessSeed &+ UInt32(pass * 4200))
        
        switch annotation.type {
        case .pen, .laser:
            guard annotation.points.count >= 2 else { return path }
            path.move(to: annotation.points[0])
            for i in 1..<annotation.points.count {
                let p0 = annotation.points[i - 1]
                let p1 = annotation.points[i]
                let midPoint = CGPoint(x: (p0.x + p1.x) / 2, y: (p0.y + p1.y) / 2)
                if i == 1 {
                    path.line(to: midPoint)
                } else {
                    path.curve(to: midPoint, controlPoint1: p0, controlPoint2: p0)
                }
                if i == annotation.points.count - 1 {
                    path.line(to: p1)
                }
            }
            
        case .arrow:
            guard let start = annotation.arrowStart, let end = annotation.arrowEnd else { return path }
            let baseControl = annotation.arrowControlPoint ?? CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
            
            // Add a geometric bow based on seed, scaled by length
            let dx = end.x - start.x
            let dy = end.y - start.y
            let length = hypot(dx, dy)
            
            // If the user hasn't explicitly curved it, we apply the hand-drawn bow
            let isStraight = annotation.arrowControlPoint == nil
            var finalControl = baseControl
            
            if isStraight {
                let dirX = dx / max(length, 1)
                let dirY = dy / max(length, 1)
                let bowAmount = random.nextFloat(in: -0.05...0.05) * length // Bow up to 5% of length
                // Perpendicular offset
                finalControl = CGPoint(x: baseControl.x - dirY * bowAmount, y: baseControl.y + dirX * bowAmount)
            } else {
                // For a manually curved arrow, just add a tiny pass-dependent variation
                let varX = random.nextFloat(in: -0.01...0.01) * length
                let varY = random.nextFloat(in: -0.01...0.01) * length
                finalControl = CGPoint(x: baseControl.x + varX, y: baseControl.y + varY)
            }
            
            path.move(to: start)
            path.curve(to: end, controlPoint1: finalControl, controlPoint2: finalControl)
            
        case .rectangle:
            guard let rect = annotation.rect else { return path }
            let tl = CGPoint(x: rect.minX, y: rect.maxY)
            let tr = CGPoint(x: rect.maxX, y: rect.maxY)
            let br = CGPoint(x: rect.maxX, y: rect.minY)
            let bl = CGPoint(x: rect.minX, y: rect.minY)
            
            drawRoughLine(on: path, from: tl, to: tr, random: &random, bowDirection: 1) // Top edge bows out (or in depending on seed sign, but biased)
            drawRoughLine(on: path, from: tr, to: br, random: &random, bowDirection: 1) // Right edge bows out
            drawRoughLine(on: path, from: br, to: bl, random: &random, bowDirection: -1) // Bottom edge bows in
            drawRoughLine(on: path, from: bl, to: tl, random: &random, bowDirection: -1) // Left edge bows in
            
        case .oval:
            guard let rect = annotation.rect else { return path }
            let kappa: CGFloat = 0.5522848
            let w = rect.width
            let h = rect.height
            let ox = (w / 2) * kappa
            let oy = (h / 2) * kappa
            let xe = rect.maxX
            let ye = rect.maxY
            let xm = rect.midX
            let ym = rect.midY
            
            // Perturb the control points slightly based on size
            func p(_ val: CGFloat, maxScale: CGFloat) -> CGFloat {
                return val + random.nextFloat(in: -maxScale...maxScale)
            }
            
            let scaleX = w * 0.03
            let scaleY = h * 0.03
            
            path.move(to: CGPoint(x: rect.minX, y: ym))
            path.curve(to: CGPoint(x: xm, y: ye), 
                       controlPoint1: CGPoint(x: rect.minX, y: p(ym + oy, maxScale: scaleY)),
                       controlPoint2: CGPoint(x: p(xm - ox, maxScale: scaleX), y: ye))
            path.curve(to: CGPoint(x: xe, y: ym), 
                       controlPoint1: CGPoint(x: p(xm + ox, maxScale: scaleX), y: ye),
                       controlPoint2: CGPoint(x: xe, y: p(ym + oy, maxScale: scaleY)))
            path.curve(to: CGPoint(x: xm, y: rect.minY), 
                       controlPoint1: CGPoint(x: xe, y: p(ym - oy, maxScale: scaleY)),
                       controlPoint2: CGPoint(x: p(xm + ox, maxScale: scaleX), y: rect.minY))
            path.curve(to: CGPoint(x: rect.minX, y: ym), 
                       controlPoint1: CGPoint(x: p(xm - ox, maxScale: scaleX), y: rect.minY),
                       controlPoint2: CGPoint(x: rect.minX, y: p(ym - oy, maxScale: scaleY)))
            
        case .text, .select:
            break
        }
        
        return path
    }
    
    static func generateArrowhead(from annotation: Annotation) -> NSBezierPath {
        let path = NSBezierPath()
        guard annotation.type == .arrow, let start = annotation.arrowStart, let end = annotation.arrowEnd else { return path }
        
        let control = annotation.arrowControlPoint ?? CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        
        let dx = end.x - control.x
        let dy = end.y - control.y
        let angle = atan2(dy, dx)
        
        // Dynamic arrowhead size based on length
        let arrowLength = hypot(end.x - start.x, end.y - start.y)
        let dynamicStrokeWidth = min(16.0, max(4.0, arrowLength / 30.0))
        
        let length = dynamicStrokeWidth * 3.5
        let width = dynamicStrokeWidth * 3.0
        
        let p1 = CGPoint(x: end.x - length * cos(angle) - width/2 * sin(angle),
                         y: end.y - length * sin(angle) + width/2 * cos(angle))
        
        let p2 = CGPoint(x: end.x - length * cos(angle) + width/2 * sin(angle),
                         y: end.y - length * sin(angle) - width/2 * cos(angle))
        
        path.move(to: end)
        path.line(to: p1)
        path.line(to: p2)
        path.close()
        return path
    }
    
    private static func drawRoughLine(on path: NSBezierPath, from start: CGPoint, to end: CGPoint, random: inout SeededRandom, bowDirection: CGFloat) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        
        if length == 0 {
            path.move(to: start)
            path.line(to: end)
            return
        }
        
        path.move(to: start)
        
        let midX = (start.x + end.x) / 2
        let midY = (start.y + end.y) / 2
        let dirX = dx / length
        let dirY = dy / length
        
        // Scale bowing by length (e.g. 2% to 4% of line length)
        let bowAmount = random.nextFloat(in: 0.02...0.04) * length * bowDirection
        let ctrl = CGPoint(x: midX - dirY * bowAmount, y: midY + dirX * bowAmount)
        
        path.curve(to: end, controlPoint1: ctrl, controlPoint2: ctrl)
    }
}
