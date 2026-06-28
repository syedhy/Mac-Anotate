import Cocoa

class AnnotationRenderer {
    
    static func draw(_ annotations: [Annotation], in context: CGContext, isDragging: Bool = false, isResizing: Bool = false, hoveredID: UUID? = nil, marqueeRect: CGRect? = nil) {
        let now = Date()
        
        for annotation in annotations {
            let isHovered = (annotation.id == hoveredID) || SelectionManager.shared.selectedAnnotationIDs.contains(annotation.id)
            let isSelected = SelectionManager.shared.selectedAnnotationIDs.contains(annotation.id)
            let isDraggingThis = isDragging && isSelected
            let isResizingThis = isResizing && isSelected
            
            var color = annotation.color
            if isHovered && !isSelected {
                color = color.blended(withFraction: 0.3, of: .white) ?? color
            }
            
            if let expiresAt = annotation.expiresAt {
                if now > expiresAt {
                    continue
                }
                
                let timeLeft = expiresAt.timeIntervalSince(now)
                let alpha = max(0, min(1.0, CGFloat(timeLeft / 0.5)))
                
                let fadedColor = color.withAlphaComponent(alpha)
                drawAnnotation(annotation, color: fadedColor, in: context, isDragging: isDraggingThis, isResizing: isResizingThis)
            } else {
                drawAnnotation(annotation, color: color, in: context, isDragging: isDraggingThis, isResizing: isResizingThis)
            }
        }
        
        if let marquee = marqueeRect {
            context.saveGState()
            context.setFillColor(NSColor.systemBlue.withAlphaComponent(0.2).cgColor)
            context.fill(marquee)
            context.setStrokeColor(NSColor.systemBlue.cgColor)
            context.setLineWidth(1.0)
            context.stroke(marquee)
            context.restoreGState()
        }
        
        let shouldShowGroupBB = SelectionManager.shared.selectedAnnotationIDs.count > 1 || (SelectionManager.shared.selectedAnnotationIDs.count == 1 && SelectionManager.shared.wasMarqueeSelected)
        if !isDragging && shouldShowGroupBB {
            if let groupBB = AnnotationHitTester.getGroupBoundingBox(for: annotations, selectedIDs: SelectionManager.shared.selectedAnnotationIDs) {
                
                NSGraphicsContext.saveGraphicsState()
                
                // Draw thin dashed outline for the group bounding box
                let outlineBB = groupBB
                let outlinePath = NSBezierPath(rect: outlineBB)
                NSColor.systemBlue.withAlphaComponent(0.5).setStroke()
                outlinePath.lineWidth = 1.0
                let dashPattern: [CGFloat] = [4.0, 4.0]
                outlinePath.setLineDash(dashPattern, count: 2, phase: 0)
                outlinePath.stroke()
                
                NSGraphicsContext.restoreGraphicsState()
                
                let handle = CGPoint(x: outlineBB.maxX, y: outlineBB.maxY)
                
                NSGraphicsContext.saveGraphicsState()
                
                NSColor.white.setFill()
                NSColor.systemBlue.setStroke()
                
                let handleShadow = NSShadow()
                handleShadow.shadowColor = NSColor.black.withAlphaComponent(0.2)
                handleShadow.shadowOffset = NSSize(width: 0, height: -1)
                handleShadow.shadowBlurRadius = 2
                handleShadow.set()
                
                let path = NSBezierPath(ovalIn: CGRect(x: handle.x - 5, y: handle.y - 5, width: 10, height: 10))
                path.fill()
                
                NSGraphicsContext.current?.cgContext.setShadow(offset: .zero, blur: 0, color: nil)
                
                path.lineWidth = 1.5
                path.stroke()
                
                NSGraphicsContext.restoreGraphicsState()
            }
        }
    }
    
    private static func drawAnnotation(_ annotation: Annotation, color: NSColor, in context: CGContext, isDragging: Bool, isResizing: Bool) {
        NSGraphicsContext.saveGraphicsState()
        let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.current = nsContext
        
        let isSelected = SelectionManager.shared.selectedAnnotationIDs.contains(annotation.id)
        let isGroupSelected = isSelected && SelectionManager.shared.selectedAnnotationIDs.count > 1
        let shouldGlow = isSelected && SelectionManager.shared.wasMarqueeSelected
        
        // Add subtle shadow or glow
        let shadow = NSShadow()
        if shouldGlow {
            shadow.shadowColor = NSColor.systemBlue.withAlphaComponent(0.8)
            shadow.shadowOffset = .zero
            shadow.shadowBlurRadius = 12
        } else {
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
            shadow.shadowOffset = NSSize(width: 0, height: -2)
            shadow.shadowBlurRadius = 4
        }
        
        if (annotation.type != .text && annotation.type != .laserPen) || shouldGlow {
            shadow.set()
        }
        
        if annotation.type == .text {
            if let text = annotation.text, let rect = annotation.textRect {
                let boxRect = rect.insetBy(dx: -12, dy: -12)
                let boxPath = NSBezierPath(roundedRect: boxRect, xRadius: 8, yRadius: 8)
                
                var textColor = color
                
                switch annotation.fillStyle {
                case .hollow:
                    if isResizing {
                        color.withAlphaComponent(0.15).setFill()
                        boxPath.fill()
                        color.withAlphaComponent(0.6).setStroke()
                        boxPath.lineWidth = 1.5
                        boxPath.stroke()
                    }
                case .translucent:
                    color.withAlphaComponent(0.2).setFill()
                    boxPath.fill()
                case .filled:
                    color.setFill()
                    boxPath.fill()
                    // Ensure text has contrast
                    textColor = color == .white ? .black : .white
                }
                
                drawText(text, in: rect, color: textColor, fontSize: annotation.fontSize)
                

            }
        } else if annotation.type == .laserPen {
            let path = NSBezierPath()
            let smoothedPoints = RoughPathGenerator.smoothPointsChaikin(annotation.points, iterations: 1)
            if smoothedPoints.count == 1 {
                let p = smoothedPoints[0]
                path.move(to: p)
                path.line(to: CGPoint(x: p.x + 0.1, y: p.y))
            } else if smoothedPoints.count >= 2 {
                path.move(to: smoothedPoints[0])
                for i in 1..<smoothedPoints.count {
                    path.line(to: smoothedPoints[i])
                }
            } else {
                return
            }
            
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            
            // Draw outer glow with transparency layer to prevent self-intersection alpha doubling
            let currentAlpha = color.alphaComponent
            context.setAlpha(currentAlpha * 0.3)
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            
            path.lineWidth = annotation.strokeWidth * 2.0
            color.withAlphaComponent(1.0).setStroke()
            path.stroke()
            
            context.endTransparencyLayer()
            context.setAlpha(1.0)
            
            // Draw inner core
            path.lineWidth = annotation.strokeWidth * 0.6
            color.setStroke()
            path.stroke()
            
        } else if annotation.type == .pen || annotation.type == .arrow {
            let path1 = RoughPathGenerator.generateDoodlePath(from: annotation, pass: 0)
            path1.lineWidth = annotation.type == .arrow ? annotation.dynamicArrowStrokeWidth : annotation.strokeWidth
            path1.lineCapStyle = .round
            path1.lineJoinStyle = .round
            color.setStroke()
            path1.stroke()
        } else if annotation.type == .rectangle || annotation.type == .oval {
            let path1 = RoughPathGenerator.generateDoodlePath(from: annotation, pass: 0)
            
            // Fill style rendering
            switch annotation.fillStyle {
            case .hollow:
                break
            case .translucent:
                color.withAlphaComponent(0.2).setFill()
                path1.fill()
            case .filled:
                color.setFill()
                path1.fill()
            }
            
            if annotation.fillStyle != .filled {
                path1.lineWidth = annotation.strokeWidth
                path1.lineCapStyle = .round
                path1.lineJoinStyle = .round
                color.setStroke()
                path1.stroke()
            }
            
            // Selection handles will be drawn below
        } else {
            // Pass 0: Main filled shape
            let path1 = RoughPathGenerator.generateDoodlePath(from: annotation, pass: 0)
            color.setFill()
            path1.fill()
            
            // Soft rounded edges via a thin stroke
            path1.lineWidth = 1.5
            path1.lineCapStyle = .round
            path1.lineJoinStyle = .round
            color.setStroke()
            path1.stroke()
            
            // Pass 1: Soft offset shape for double-stroke effect
            let path2 = RoughPathGenerator.generateDoodlePath(from: annotation, pass: 1)
            let softColor = color.withAlphaComponent(0.35)
            softColor.setFill()
            path2.fill()
            
            path2.lineWidth = 1.5
            path2.lineCapStyle = .round
            path2.lineJoinStyle = .round
            softColor.setStroke()
            path2.stroke()
        }
        
        if !isDragging && SelectionManager.shared.selectedAnnotationIDs.contains(annotation.id) {
            if SelectionManager.shared.selectedAnnotationIDs.count == 1 && !SelectionManager.shared.wasMarqueeSelected {
                if let handles = AnnotationHitTester.getHandles(for: annotation) {
                NSColor.white.setFill()
                NSColor.systemBlue.setStroke()
                
                // Add a subtle shadow to the handles to make them crisp and native
                let handleShadow = NSShadow()
                handleShadow.shadowColor = NSColor.black.withAlphaComponent(0.2)
                handleShadow.shadowOffset = NSSize(width: 0, height: -1)
                handleShadow.shadowBlurRadius = 2
                handleShadow.set()

                for (i, handle) in handles.enumerated() {
                    let handleSize: CGFloat = 12.0
                    let rect = NSRect(x: handle.x - handleSize/2, y: handle.y - handleSize/2, width: handleSize, height: handleSize)
                    let path: NSBezierPath
                    if annotation.type == .text && i == 2 {
                        // Scale handle (bottom-right) as a diamond
                        let size: CGFloat = 10.0
                        let cx = handle.x
                        let cy = handle.y
                        path = NSBezierPath()
                        path.move(to: CGPoint(x: cx, y: cy + size/2)) // Top
                        path.line(to: CGPoint(x: cx + size/2, y: cy)) // Right
                        path.line(to: CGPoint(x: cx, y: cy - size/2)) // Bottom
                        path.line(to: CGPoint(x: cx - size/2, y: cy)) // Left
                        path.close()
                    } else {
                        path = NSBezierPath(ovalIn: rect)
                    }
                    
                    path.lineWidth = 1.5
                    path.fill()
                    path.stroke()
                }
            }
            }
        }
        
        NSGraphicsContext.restoreGraphicsState()
    }
    
    private static func drawText(_ text: String, in rect: CGRect, color: NSColor, fontSize: CGFloat) {
        let font = NSFont(name: "Marker Felt", size: fontSize) ?? NSFont.systemFont(ofSize: fontSize, weight: .bold)
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle
        ]
        
        text.draw(in: rect, withAttributes: attributes)
    }
    
}
