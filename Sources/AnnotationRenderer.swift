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
        
        if !isDragging && SelectionManager.shared.selectedAnnotationIDs.count > 1 {
            if let groupBB = AnnotationHitTester.getGroupBoundingBox(for: annotations, selectedIDs: SelectionManager.shared.selectedAnnotationIDs) {
                
                NSGraphicsContext.saveGraphicsState()
                
                // Draw thin dashed outline for the group bounding box
                let outlineBB = groupBB.insetBy(dx: -4, dy: -4)
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
        
        // Add subtle shadow or glow if selected as a group
        let shadow = NSShadow()
        if isGroupSelected {
            shadow.shadowColor = NSColor.systemBlue.withAlphaComponent(0.8)
            shadow.shadowOffset = .zero
            shadow.shadowBlurRadius = 12
        } else {
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
            shadow.shadowOffset = NSSize(width: 0, height: -2)
            shadow.shadowBlurRadius = 4
        }
        
        if annotation.type != .text || isGroupSelected {
            shadow.set()
        }
        
        if annotation.type == .text {
            if let text = annotation.text, let rect = annotation.textRect {
                if isResizing {
                    let highlightPath = NSBezierPath(roundedRect: rect.insetBy(dx: -12, dy: -12), xRadius: 8, yRadius: 8)
                    color.withAlphaComponent(0.15).setFill()
                    highlightPath.fill()
                    
                    color.withAlphaComponent(0.6).setStroke()
                    highlightPath.lineWidth = 1.5
                    highlightPath.stroke()
                }
                drawText(text, in: rect, color: color, fontSize: annotation.fontSize)
            }
        } else if annotation.type == .laserPen {
            let path = NSBezierPath()
            guard annotation.points.count >= 2 else { return }
            path.move(to: annotation.points[0])
            for i in 1..<annotation.points.count {
                path.line(to: annotation.points[i])
            }
            
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            
            // Draw outer glow (constant thickness 12)
            path.lineWidth = 12.0
            color.withAlphaComponent(0.3).setStroke()
            path.stroke()
            
            // Draw inner core (constant thickness 3)
            path.lineWidth = 3.0
            color.setStroke()
            path.stroke()
            
        } else if annotation.type == .pen || annotation.type == .rectangle || annotation.type == .oval || annotation.type == .arrow {
            let path1 = RoughPathGenerator.generateDoodlePath(from: annotation, pass: 0)
            path1.lineWidth = annotation.type == .arrow ? annotation.dynamicArrowStrokeWidth : annotation.strokeWidth
            path1.lineCapStyle = .round
            path1.lineJoinStyle = .round
            color.setStroke()
            path1.stroke()
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
            if SelectionManager.shared.selectedAnnotationIDs.count == 1 {
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
