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

    static func smoothPointsChaikin(_ points: [CGPoint], iterations: Int) -> [CGPoint] {
        guard points.count > 2 else { return points }
        var currentPoints = points

        for _ in 0..<iterations {
            var newPoints = [currentPoints[0]]
            for i in 0..<(currentPoints.count - 1) {
                let p0 = currentPoints[i]
                let p1 = currentPoints[i+1]
                let q = CGPoint(x: 0.75 * p0.x + 0.25 * p1.x, y: 0.75 * p0.y + 0.25 * p1.y)
                let r = CGPoint(x: 0.25 * p0.x + 0.75 * p1.x, y: 0.25 * p0.y + 0.75 * p1.y)
                newPoints.append(q)
                newPoints.append(r)
            }
            newPoints.append(currentPoints.last!)
            currentPoints = newPoints
        }

        return currentPoints
    }

    static func generateDoodlePath(from annotation: Annotation, pass: Int) -> NSBezierPath {
        let path = NSBezierPath()
        var random = SeededRandom(seed: annotation.roughnessSeed &+ UInt32(pass * 4200))

        switch annotation.type {
        case .pen, .laserPen:
            if annotation.points.count == 1 {
                let p = annotation.points[0]
                path.move(to: p)
                path.line(to: CGPoint(x: p.x + 0.1, y: p.y))
                return path
            }
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

            let isStraight = annotation.arrowControlPoint == nil
            let baseControl = annotation.arrowControlPoint ?? CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
            var finalControl = baseControl

            if isStraight {
                let dirX = length > 0 ? dx / length : 0.0
                let dirY = length > 0 ? dy / length : 0.0
                let bowAmount = random.nextFloat(in: -0.06...0.06) * length
                finalControl = CGPoint(x: baseControl.x - dirY * bowAmount, y: baseControl.y + dirX * bowAmount)
            } else {
                let varX = random.nextFloat(in: -0.01...0.01) * length
                let varY = random.nextFloat(in: -0.01...0.01) * length
                finalControl = CGPoint(x: baseControl.x + varX, y: baseControl.y + varY)
            }

            let strokeW = annotation.dynamicArrowStrokeWidth
            let headL = strokeW * 3.5
            let headW = strokeW * 3.0

            let dxCtrl = end.x - finalControl.x
            let dyCtrl = end.y - finalControl.y
            let angle = atan2(dyCtrl, dxCtrl)

            // Shaft stops a bit BEFORE the arrowhead to make it float
            let shaftEnd = CGPoint(x: end.x - headL * 1.2 * cos(angle), y: end.y - headL * 1.2 * sin(angle))

            path.move(to: start)
            let cp1 = CGPoint(x: start.x + (2.0/3.0)*(finalControl.x - start.x), y: start.y + (2.0/3.0)*(finalControl.y - start.y))
            let cp2 = CGPoint(x: shaftEnd.x + (2.0/3.0)*(finalControl.x - shaftEnd.x), y: shaftEnd.y + (2.0/3.0)*(finalControl.y - shaftEnd.y))
            path.curve(to: shaftEnd, controlPoint1: cp1, controlPoint2: cp2)

            let p1 = CGPoint(x: end.x - headL * cos(angle) - headW/2 * sin(angle),
                             y: end.y - headL * sin(angle) + headW/2 * cos(angle))
            let p2 = CGPoint(x: end.x - headL * cos(angle) + headW/2 * sin(angle),
                             y: end.y - headL * sin(angle) - headW/2 * cos(angle))

            path.move(to: end)
            path.line(to: p1)
            path.line(to: p2)
            path.close()

        case .rectangle:
            guard let rect = annotation.rect else { return path }
            let w = rect.width
            let h = rect.height
            let r = min(16, min(w, h) * 0.25)
            path.appendRoundedRect(rect, xRadius: r, yRadius: r)

        case .oval:
            guard let rect = annotation.rect else { return path }
            path.appendOval(in: rect)

        case .text, .select, .laserPointer:
            break
        }

        return path
    }

    static func generateVariableStrokePath(from annotation: Annotation, pass: Int) -> NSBezierPath {
        let path = NSBezierPath()
        var random = SeededRandom(seed: annotation.roughnessSeed &+ UInt32(pass * 7351))

        switch annotation.type {
        case .pen:
            let smoothedPoints = smoothPointsChaikin(annotation.points, iterations: 1)
            appendVariablePolyline(to: path, points: smoothedPoints, baseWidth: annotation.strokeWidth, random: &random, closed: false)
        case .arrow:
            appendVariableArrow(to: path, annotation: annotation, random: &random)
        case .rectangle:
            guard let rect = annotation.rect, rect.width > 1, rect.height > 1 else { return path }
            appendVariablePolyline(to: path, points: rectangleOutlinePoints(for: rect), baseWidth: annotation.strokeWidth, random: &random, closed: true)
        case .oval:
            guard let rect = annotation.rect, rect.width > 1, rect.height > 1 else { return path }
            appendVariablePolyline(to: path, points: ovalOutlinePoints(for: rect), baseWidth: annotation.strokeWidth, random: &random, closed: true)
        default:
            break
        }

        return path
    }

    static func generateArrowHeadPath(from annotation: Annotation, pass: Int) -> NSBezierPath {
        let path = NSBezierPath()
        guard annotation.type == .arrow,
              let start = annotation.arrowStart,
              let end = annotation.arrowEnd else {
            return path
        }

        let geometry = arrowGeometry(start: start, end: end, control: annotation.arrowControlPoint, strokeWidth: annotation.dynamicArrowStrokeWidth, seed: annotation.roughnessSeed &+ UInt32(pass * 7351))
        guard let arrow = geometry else { return path }

        path.move(to: end)
        path.line(to: arrow.headPoint1)
        path.line(to: arrow.headPoint2)
        path.close()
        return path
    }

    private static func variableWidths(count: Int, baseWidth: CGFloat, random: inout SeededRandom) -> [CGFloat] {
        guard count > 0 else { return [] }

        var multiplier = random.nextFloat(in: 0.82...1.24)
        return (0..<count).map { index in
            if index == 0 || random.nextFloat() < 0.34 {
                multiplier = random.nextFloat(in: 0.66...1.38)
            } else {
                multiplier += random.nextFloat(in: -0.18...0.18)
            }

            multiplier = max(0.6, min(1.45, multiplier))
            return max(1.0, baseWidth * multiplier)
        }
    }

    private static func appendVariablePolyline(to path: NSBezierPath, points: [CGPoint], baseWidth: CGFloat, random: inout SeededRandom, closed: Bool) {
        guard points.count >= 2 else {
            if let point = points.first {
                let width = variableWidths(count: 1, baseWidth: baseWidth, random: &random)[0]
                path.appendOval(in: CGRect(x: point.x - width / 2, y: point.y - width / 2, width: width, height: width))
            }
            return
        }

        var widths = variableWidths(count: points.count, baseWidth: baseWidth, random: &random)
        if closed {
            widths.append(widths.first ?? baseWidth)
        }

        let segmentCount = closed ? points.count : points.count - 1
        for index in 0..<segmentCount {
            let start = points[index]
            let end = points[(index + 1) % points.count]
            let startWidth = widths[index]
            let endWidth = widths[index + 1]
            let midWidth = max(1.0, baseWidth * random.nextFloat(in: 0.58...1.48))
            addVariableWidthLine(
                to: path,
                from: start,
                to: end,
                control: nil,
                wStart: startWidth,
                wMid: midWidth,
                wEnd: endWidth,
                roundCapStart: true,
                roundCapEnd: true
            )
        }
    }

    private static func appendVariableArrow(to path: NSBezierPath, annotation: Annotation, random: inout SeededRandom) {
        guard let start = annotation.arrowStart, let end = annotation.arrowEnd else { return }
        let strokeWidth = annotation.dynamicArrowStrokeWidth
        guard let arrow = arrowGeometry(start: start, end: end, control: annotation.arrowControlPoint, strokeWidth: strokeWidth, seed: random.state) else { return }
        appendVariablePolyline(to: path, points: sampleQuadratic(from: start, control: arrow.control, to: arrow.shaftEnd, steps: 18), baseWidth: strokeWidth, random: &random, closed: false)
    }

    private struct ArrowGeometry {
        let control: CGPoint
        let shaftEnd: CGPoint
        let headPoint1: CGPoint
        let headPoint2: CGPoint
    }

    private static func arrowGeometry(start: CGPoint, end: CGPoint, control: CGPoint?, strokeWidth: CGFloat, seed: UInt32) -> ArrowGeometry? {
        var random = SeededRandom(seed: seed)
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        if length < 1 { return nil }

        let baseControl = control ?? CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        let finalControl: CGPoint

        if control == nil {
            let dirX = dx / length
            let dirY = dy / length
            let bowAmount = random.nextFloat(in: -0.06...0.06) * length
            finalControl = CGPoint(x: baseControl.x - dirY * bowAmount, y: baseControl.y + dirX * bowAmount)
        } else {
            let varX = random.nextFloat(in: -0.01...0.01) * length
            let varY = random.nextFloat(in: -0.01...0.01) * length
            finalControl = CGPoint(x: baseControl.x + varX, y: baseControl.y + varY)
        }

        let headLength = strokeWidth * 3.5
        let headWidth = strokeWidth * 3.0
        let dxCtrl = end.x - finalControl.x
        let dyCtrl = end.y - finalControl.y
        let angle = atan2(dyCtrl, dxCtrl)
        let shaftEnd = CGPoint(x: end.x - headLength * 1.2 * cos(angle), y: end.y - headLength * 1.2 * sin(angle))
        let p1 = CGPoint(x: end.x - headLength * cos(angle) - headWidth / 2 * sin(angle),
                         y: end.y - headLength * sin(angle) + headWidth / 2 * cos(angle))
        let p2 = CGPoint(x: end.x - headLength * cos(angle) + headWidth / 2 * sin(angle),
                         y: end.y - headLength * sin(angle) - headWidth / 2 * cos(angle))

        return ArrowGeometry(control: finalControl, shaftEnd: shaftEnd, headPoint1: p1, headPoint2: p2)
    }

    private static func rectangleOutlinePoints(for rect: CGRect) -> [CGPoint] {
        let corners = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY)
        ]
        return sampleClosedPolyline(corners, pointsPerEdge: 8)
    }

    private static func ovalOutlinePoints(for rect: CGRect) -> [CGPoint] {
        let steps = 48
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radiusX = rect.width / 2
        let radiusY = rect.height / 2

        return (0..<steps).map { index in
            let angle = CGFloat(index) / CGFloat(steps) * .pi * 2
            return CGPoint(x: center.x + cos(angle) * radiusX, y: center.y + sin(angle) * radiusY)
        }
    }

    private static func sampleQuadratic(from start: CGPoint, control: CGPoint, to end: CGPoint, steps: Int) -> [CGPoint] {
        (0...steps).map { index in
            let t = CGFloat(index) / CGFloat(steps)
            let oneMinusT = 1.0 - t
            return CGPoint(
                x: oneMinusT * oneMinusT * start.x + 2 * oneMinusT * t * control.x + t * t * end.x,
                y: oneMinusT * oneMinusT * start.y + 2 * oneMinusT * t * control.y + t * t * end.y
            )
        }
    }

    private static func sampleClosedPolyline(_ points: [CGPoint], pointsPerEdge: Int) -> [CGPoint] {
        guard points.count > 1 else { return points }

        var sampled: [CGPoint] = []
        for index in 0..<points.count {
            let start = points[index]
            let end = points[(index + 1) % points.count]
            for step in 0..<pointsPerEdge {
                let t = CGFloat(step) / CGFloat(pointsPerEdge)
                sampled.append(CGPoint(
                    x: start.x + (end.x - start.x) * t,
                    y: start.y + (end.y - start.y) * t
                ))
            }
        }
        return sampled
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

        path.move(to: rightPoints[0])

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
