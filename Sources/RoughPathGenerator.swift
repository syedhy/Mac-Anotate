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
            let dx = end.x - start.x
            let dy = end.y - start.y
            let length = hypot(dx, dy)
            if length < 1 { return path }
            
            let baseControl = annotation.arrowControlPoint ?? CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
            let isStraight = annotation.arrowControlPoint == nil
            var finalControl = baseControl
            
            if isStraight {
                let dirX = dx / length
                let dirY = dy / length
                let bowAmount = random.nextFloat(in: -0.06...0.06) * length
                finalControl = CGPoint(x: baseControl.x - dirY * bowAmount, y: baseControl.y + dirX * bowAmount)
            } else {
                let varX = random.nextFloat(in: -0.01...0.01) * length
                let varY = random.nextFloat(in: -0.01...0.01) * length
                finalControl = CGPoint(x: baseControl.x + varX, y: baseControl.y + varY)
            }
            
            let dynamicStrokeWidth = min(16.0, max(2.0, length / 30.0))
            let headLength = dynamicStrokeWidth * 3.5
            let headWidth = dynamicStrokeWidth * 3.0
            
            let dxCtrl = end.x - finalControl.x
            let dyCtrl = end.y - finalControl.y
            let ctrlLen = hypot(dxCtrl, dyCtrl)
            let dirX = ctrlLen > 0 ? dxCtrl / ctrlLen : dx / length
            let dirY = ctrlLen > 0 ? dyCtrl / ctrlLen : dy / length
            let angle = atan2(dirY, dirX)
            
            let shaftEnd = CGPoint(x: end.x - headLength * 0.8 * cos(angle), y: end.y - headLength * 0.8 * sin(angle))
            
            let wStart = dynamicStrokeWidth * random.nextFloat(in: 1.0...1.3)
            let wMid = dynamicStrokeWidth * random.nextFloat(in: 0.6...0.9)
            let wEnd = dynamicStrokeWidth * random.nextFloat(in: 0.9...1.2)
            
            addVariableWidthLine(to: path, from: start, to: shaftEnd, control: finalControl, wStart: wStart, wMid: wMid, wEnd: wEnd, roundCapStart: true, roundCapEnd: false)
            
            let p1 = CGPoint(x: end.x - headLength * cos(angle) - headWidth/2 * sin(angle),
                             y: end.y - headLength * sin(angle) + headWidth/2 * cos(angle))
            let p2 = CGPoint(x: end.x - headLength * cos(angle) + headWidth/2 * sin(angle),
                             y: end.y - headLength * sin(angle) - headWidth/2 * cos(angle))
            let backMid = CGPoint(x: end.x - headLength * 0.9 * cos(angle), y: end.y - headLength * 0.9 * sin(angle))
            
            path.move(to: end)
            path.curve(to: p1, controlPoint1: CGPoint(x: end.x * 0.5 + p1.x * 0.5, y: end.y * 0.5 + p1.y * 0.5), controlPoint2: p1)
            path.curve(to: p2, controlPoint1: backMid, controlPoint2: p2)
            path.curve(to: end, controlPoint1: CGPoint(x: end.x * 0.5 + p2.x * 0.5, y: end.y * 0.5 + p2.y * 0.5), controlPoint2: end)
            path.close()
            
        case .rectangle:
            guard let rect = annotation.rect else { return path }
            let tl = CGPoint(x: rect.minX, y: rect.maxY)
            let tr = CGPoint(x: rect.maxX, y: rect.maxY)
            let br = CGPoint(x: rect.maxX, y: rect.minY)
            let bl = CGPoint(x: rect.minX, y: rect.minY)
            
            let baseWidth = annotation.strokeWidth
            let overlapX = baseWidth * random.nextFloat(in: 0.5...1.5)
            let overlapY = baseWidth * random.nextFloat(in: 0.5...1.5)
            
            func rw() -> CGFloat { return baseWidth * random.nextFloat(in: 0.6...1.4) }
            
            let tL_ext = CGPoint(x: tl.x - overlapX, y: tl.y + random.nextFloat(in: -2...2))
            let tR_ext = CGPoint(x: tr.x + overlapX, y: tr.y + random.nextFloat(in: -2...2))
            let bowTop = random.nextFloat(in: 0.02...0.04) * rect.width
            let cTop = CGPoint(x: rect.midX, y: tl.y + bowTop)
            addVariableWidthLine(to: path, from: tL_ext, to: tR_ext, control: cTop, wStart: rw(), wMid: rw(), wEnd: rw(), roundCapStart: true, roundCapEnd: true)
            
            let rT_ext = CGPoint(x: tr.x + random.nextFloat(in: -2...2), y: tr.y + overlapY)
            let rB_ext = CGPoint(x: br.x + random.nextFloat(in: -2...2), y: br.y - overlapY)
            let bowRight = random.nextFloat(in: 0.02...0.04) * rect.height
            let cRight = CGPoint(x: tr.x + bowRight, y: rect.midY)
            addVariableWidthLine(to: path, from: rT_ext, to: rB_ext, control: cRight, wStart: rw(), wMid: rw(), wEnd: rw(), roundCapStart: true, roundCapEnd: true)
            
            let bR_ext = CGPoint(x: br.x + overlapX, y: br.y + random.nextFloat(in: -2...2))
            let bL_ext = CGPoint(x: bl.x - overlapX, y: bl.y + random.nextFloat(in: -2...2))
            let bowBottom = random.nextFloat(in: 0.02...0.04) * rect.width
            let cBottom = CGPoint(x: rect.midX, y: br.y - bowBottom)
            addVariableWidthLine(to: path, from: bR_ext, to: bL_ext, control: cBottom, wStart: rw(), wMid: rw(), wEnd: rw(), roundCapStart: true, roundCapEnd: true)
            
            let lB_ext = CGPoint(x: bl.x + random.nextFloat(in: -2...2), y: bl.y - overlapY)
            let lT_ext = CGPoint(x: tl.x + random.nextFloat(in: -2...2), y: tl.y + overlapY)
            let bowLeft = random.nextFloat(in: 0.02...0.04) * rect.height
            let cLeft = CGPoint(x: tl.x - bowLeft, y: rect.midY)
            addVariableWidthLine(to: path, from: lB_ext, to: lT_ext, control: cLeft, wStart: rw(), wMid: rw(), wEnd: rw(), roundCapStart: true, roundCapEnd: true)
            
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
            
            func p(_ val: CGFloat, maxScale: CGFloat) -> CGFloat {
                return val + random.nextFloat(in: -maxScale...maxScale)
            }
            
            let scaleX = w * 0.05
            let scaleY = h * 0.05
            
            let points = [
                CGPoint(x: rect.minX, y: ym),
                CGPoint(x: xm, y: ye),
                CGPoint(x: xe, y: ym),
                CGPoint(x: xm, y: rect.minY)
            ]
            let controls1 = [
                CGPoint(x: rect.minX, y: p(ym + oy, maxScale: scaleY)),
                CGPoint(x: p(xm + ox, maxScale: scaleX), y: ye),
                CGPoint(x: xe, y: p(ym - oy, maxScale: scaleY)),
                CGPoint(x: p(xm - ox, maxScale: scaleX), y: rect.minY)
            ]
            let controls2 = [
                CGPoint(x: p(xm - ox, maxScale: scaleX), y: ye),
                CGPoint(x: xe, y: p(ym + oy, maxScale: scaleY)),
                CGPoint(x: p(xm + ox, maxScale: scaleX), y: rect.minY),
                CGPoint(x: rect.minX, y: p(ym - oy, maxScale: scaleY))
            ]
            
            let baseW = annotation.strokeWidth
            let widths = [
                baseW * random.nextFloat(in: 0.6...1.4),
                baseW * random.nextFloat(in: 0.6...1.4),
                baseW * random.nextFloat(in: 0.6...1.4),
                baseW * random.nextFloat(in: 0.6...1.4)
            ]
            addVariableWidthContinuousCubic(to: path, points: points, controls1: controls1, controls2: controls2, widths: widths)
            
        case .text, .select:
            break
        }
        
        return path
    }
    
    private static func addVariableWidthLine(to path: NSBezierPath, from start: CGPoint, to end: CGPoint, control: CGPoint?, wStart: CGFloat, wMid: CGFloat, wEnd: CGFloat, roundCapStart: Bool, roundCapEnd: Bool) {
        let steps = 30
        var leftPoints: [CGPoint] = []
        var rightPoints: [CGPoint] = []
        var tangents: [CGPoint] = []
        
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let oneMinusT = 1.0 - t
            
            let w = wStart * oneMinusT * oneMinusT + wMid * 2 * t * oneMinusT + wEnd * t * t
            let halfW = w / 2.0
            
            let pt: CGPoint
            let tangent: CGPoint
            if let c = control {
                pt = CGPoint(
                    x: oneMinusT * oneMinusT * start.x + 2 * oneMinusT * t * c.x + t * t * end.x,
                    y: oneMinusT * oneMinusT * start.y + 2 * oneMinusT * t * c.y + t * t * end.y
                )
                tangent = CGPoint(
                    x: 2 * oneMinusT * (c.x - start.x) + 2 * t * (end.x - c.x),
                    y: 2 * oneMinusT * (c.y - start.y) + 2 * t * (end.y - c.y)
                )
            } else {
                pt = CGPoint(
                    x: start.x + t * (end.x - start.x),
                    y: start.y + t * (end.y - start.y)
                )
                tangent = CGPoint(x: end.x - start.x, y: end.y - start.y)
            }
            
            let length = hypot(tangent.x, tangent.y)
            let nTangent = length > 0.001 ? CGPoint(x: tangent.x / length, y: tangent.y / length) : CGPoint(x: 1, y: 0)
            tangents.append(nTangent)
            
            let normal = CGPoint(x: -nTangent.y, y: nTangent.x)
            
            leftPoints.append(CGPoint(x: pt.x + normal.x * halfW, y: pt.y + normal.y * halfW))
            rightPoints.append(CGPoint(x: pt.x - normal.x * halfW, y: pt.y - normal.y * halfW))
        }
        
        if path.isEmpty {
            path.move(to: rightPoints[0])
        } else {
            path.line(to: rightPoints[0])
        }
        
        if roundCapStart {
            let r = wStart / 2.0
            let t0 = tangents[0]
            let fX = -t0.x
            let fY = -t0.y
            let pRight = rightPoints[0]
            let pLeft = leftPoints[0]
            
            path.curve(to: pLeft, 
                       controlPoint1: CGPoint(x: pRight.x + fX * r * 1.3, y: pRight.y + fY * r * 1.3), 
                       controlPoint2: CGPoint(x: pLeft.x + fX * r * 1.3, y: pLeft.y + fY * r * 1.3))
        } else {
            path.line(to: leftPoints[0])
        }
        
        for i in 1...steps {
            path.line(to: leftPoints[i])
        }
        
        if roundCapEnd {
            let r = wEnd / 2.0
            let tE = tangents[steps]
            let fX = tE.x
            let fY = tE.y
            let pLeft = leftPoints[steps]
            let pRight = rightPoints[steps]
            
            path.curve(to: pRight, 
                       controlPoint1: CGPoint(x: pLeft.x + fX * r * 1.3, y: pLeft.y + fY * r * 1.3), 
                       controlPoint2: CGPoint(x: pRight.x + fX * r * 1.3, y: pRight.y + fY * r * 1.3))
        } else {
            path.line(to: rightPoints[steps])
        }
        
        for i in (0..<steps).reversed() {
            path.line(to: rightPoints[i])
        }
        
        path.close()
    }
    
    private static func addVariableWidthContinuousCubic(to path: NSBezierPath, points: [CGPoint], controls1: [CGPoint], controls2: [CGPoint], widths: [CGFloat]) {
        let stepsPerCurve = 20
        var leftPoints: [CGPoint] = []
        var rightPoints: [CGPoint] = []
        
        for curveIdx in 0..<points.count {
            let p0 = points[curveIdx]
            let p1 = points[(curveIdx + 1) % points.count]
            let c1 = controls1[curveIdx]
            let c2 = controls2[curveIdx]
            let w0 = widths[curveIdx]
            let w1 = widths[(curveIdx + 1) % widths.count]
            
            for i in 0..<stepsPerCurve {
                let t = CGFloat(i) / CGFloat(stepsPerCurve)
                let oneMinusT = 1.0 - t
                
                let w = w0 * (1 - t) + w1 * t
                let halfW = w / 2.0
                
                let pt = CGPoint(
                    x: oneMinusT * oneMinusT * oneMinusT * p0.x + 3 * oneMinusT * oneMinusT * t * c1.x + 3 * oneMinusT * t * t * c2.x + t * t * t * p1.x,
                    y: oneMinusT * oneMinusT * oneMinusT * p0.y + 3 * oneMinusT * oneMinusT * t * c1.y + 3 * oneMinusT * t * t * c2.y + t * t * t * p1.y
                )
                let tangent = CGPoint(
                    x: 3 * oneMinusT * oneMinusT * (c1.x - p0.x) + 6 * oneMinusT * t * (c2.x - c1.x) + 3 * t * t * (p1.x - c2.x),
                    y: 3 * oneMinusT * oneMinusT * (c1.y - p0.y) + 6 * oneMinusT * t * (c2.y - c1.y) + 3 * t * t * (p1.y - c2.y)
                )
                
                let length = hypot(tangent.x, tangent.y)
                let nTangent = length > 0.001 ? CGPoint(x: tangent.x / length, y: tangent.y / length) : CGPoint(x: 1, y: 0)
                let normal = CGPoint(x: -nTangent.y, y: nTangent.x)
                
                leftPoints.append(CGPoint(x: pt.x + normal.x * halfW, y: pt.y + normal.y * halfW))
                rightPoints.append(CGPoint(x: pt.x - normal.x * halfW, y: pt.y - normal.y * halfW))
            }
        }
        
        if leftPoints.isEmpty { return }
        
        path.move(to: leftPoints[0])
        for i in 1..<leftPoints.count {
            path.line(to: leftPoints[i])
        }
        path.line(to: rightPoints.last!) 
        for i in (0..<rightPoints.count).reversed() {
            path.line(to: rightPoints[i])
        }
        path.close()
    }
}
