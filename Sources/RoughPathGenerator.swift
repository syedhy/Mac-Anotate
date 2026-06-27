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
        var random = SeededRandom(seed: annotation.roughnessSeed &+ UInt32(pass * 1000))
        
        switch annotation.type {
        case .pen, .laser:
            // Pen is smooth, no double stroke needed unless we want subtle
            // Just use a single pass or same pass. 
            // We use simple quadratic smoothing here.
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
            let control = annotation.arrowControlPoint ?? CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
            
            // Add subtle bowing/variation
            let offset: CGFloat = 3.0
            let startMod = CGPoint(x: start.x + random.nextFloat(in: -offset...offset), y: start.y + random.nextFloat(in: -offset...offset))
            let endMod = CGPoint(x: end.x + random.nextFloat(in: -offset...offset), y: end.y + random.nextFloat(in: -offset...offset))
            let controlMod = CGPoint(x: control.x + random.nextFloat(in: -offset...offset), y: control.y + random.nextFloat(in: -offset...offset))
            
            path.move(to: startMod)
            path.curve(to: endMod, controlPoint1: controlMod, controlPoint2: controlMod)
            
        case .rectangle:
            guard let rect = annotation.rect else { return path }
            let tl = CGPoint(x: rect.minX, y: rect.maxY)
            let tr = CGPoint(x: rect.maxX, y: rect.maxY)
            let br = CGPoint(x: rect.maxX, y: rect.minY)
            let bl = CGPoint(x: rect.minX, y: rect.minY)
            
            drawRoughLine(on: path, from: tl, to: tr, random: &random)
            drawRoughLine(on: path, from: tr, to: br, random: &random)
            drawRoughLine(on: path, from: br, to: bl, random: &random)
            drawRoughLine(on: path, from: bl, to: tl, random: &random)
            
        case .oval:
            guard let rect = annotation.rect else { return path }
            let kappa: CGFloat = 0.5522848
            let ox = (rect.width / 2) * kappa
            let oy = (rect.height / 2) * kappa
            let xe = rect.maxX
            let ye = rect.maxY
            let xm = rect.midX
            let ym = rect.midY
            
            let wAmount: CGFloat = 2.0
            func w() -> CGFloat { return random.nextFloat(in: -wAmount...wAmount) }
            
            path.move(to: CGPoint(x: rect.minX + w(), y: ym + w()))
            path.curve(to: CGPoint(x: xm + w(), y: ye + w()), controlPoint1: CGPoint(x: rect.minX + w(), y: ym + oy + w()), controlPoint2: CGPoint(x: xm - ox + w(), y: ye + w()))
            path.curve(to: CGPoint(x: xe + w(), y: ym + w()), controlPoint1: CGPoint(x: xm + ox + w(), y: ye + w()), controlPoint2: CGPoint(x: xe + w(), y: ym + oy + w()))
            path.curve(to: CGPoint(x: xm + w(), y: rect.minY + w()), controlPoint1: CGPoint(x: xe + w(), y: ym - oy + w()), controlPoint2: CGPoint(x: xm + ox + w(), y: rect.minY + w()))
            path.curve(to: CGPoint(x: rect.minX + w(), y: ym + w()), controlPoint1: CGPoint(x: xm - ox + w(), y: rect.minY + w()), controlPoint2: CGPoint(x: rect.minX + w(), y: ym - oy + w()))
            
        case .text, .select:
            break
        }
        
        return path
    }
    
    static func generateArrowhead(from annotation: Annotation) -> NSBezierPath {
        let path = NSBezierPath()
        guard annotation.type == .arrow, let start = annotation.arrowStart, let end = annotation.arrowEnd else { return path }
        
        let control = annotation.arrowControlPoint ?? CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        
        // Derivative of quadratic bezier at t=1 is 2*(end - control)
        let dx = end.x - control.x
        let dy = end.y - control.y
        let angle = atan2(dy, dx)
        
        let length = annotation.strokeWidth * 4.0
        let width = annotation.strokeWidth * 3.0
        
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
    
    private static func drawRoughLine(on path: NSBezierPath, from start: CGPoint, to end: CGPoint, random: inout SeededRandom) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        
        if length == 0 {
            path.move(to: start)
            path.line(to: end)
            return
        }
        
        // Slight offset
        let offset: CGFloat = 2.0
        let newStart = CGPoint(x: start.x + random.nextFloat(in: -offset...offset), y: start.y + random.nextFloat(in: -offset...offset))
        let newEnd = CGPoint(x: end.x + random.nextFloat(in: -offset...offset), y: end.y + random.nextFloat(in: -offset...offset))
        
        path.move(to: newStart)
        
        // Slight bow
        let midX = (start.x + end.x) / 2
        let midY = (start.y + end.y) / 2
        let dirX = dx / length
        let dirY = dy / length
        let bowAmount = random.nextFloat(in: -2.0...2.0)
        let ctrl = CGPoint(x: midX - dirY * bowAmount, y: midY + dirX * bowAmount)
        
        path.curve(to: newEnd, controlPoint1: ctrl, controlPoint2: ctrl)
    }
}
