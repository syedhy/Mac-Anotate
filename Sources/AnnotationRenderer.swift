import Cocoa

class AnnotationRenderer {
    
    static func draw(_ annotations: [Annotation], in context: CGContext) {
        let now = Date()
        
        for annotation in annotations {
            // Check laser expiration
            if let expiresAt = annotation.expiresAt {
                if now > expiresAt {
                    continue
                }
                
                // Fade out laser stroke based on time remaining
                let timeLeft = expiresAt.timeIntervalSince(now)
                let alpha = max(0, min(1.0, CGFloat(timeLeft / 0.5))) // Fade out over the last 0.5 second
                
                let fadedColor = annotation.color.withAlphaComponent(alpha)
                drawAnnotation(annotation, color: fadedColor, in: context)
            } else {
                drawAnnotation(annotation, color: annotation.color, in: context)
            }
        }
    }
    
    private static func drawAnnotation(_ annotation: Annotation, color: NSColor, in context: CGContext) {
        NSGraphicsContext.saveGraphicsState()
        let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.current = nsContext
        
        color.setStroke()
        color.setFill()
        
        // Add subtle shadow
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
        shadow.shadowOffset = NSSize(width: 0, height: -2)
        shadow.shadowBlurRadius = 4
        shadow.set()
        
        if annotation.type == .text {
            if let text = annotation.text, let rect = annotation.textRect {
                drawText(text, in: rect, color: color, fontSize: annotation.fontSize)
            }
        } else {
            // Draw arrowhead if needed
            if annotation.type == .arrow {
                let arrowPath = RoughPathGenerator.generateArrowhead(from: annotation)
                color.setFill()
                arrowPath.fill()
            }
            
            // Single clean solid pass to prevent weird overlaps
            let path = RoughPathGenerator.generateDoodlePath(from: annotation, pass: 0)
            
            // For arrows, dynamic stroke width based on length
            if annotation.type == .arrow, let s = annotation.arrowStart, let e = annotation.arrowEnd {
                let length = hypot(e.x - s.x, e.y - s.y)
                // Base thickness 4, scales up to 16 based on length (max at ~500 points)
                let dynamicWidth = min(16.0, max(4.0, length / 30.0))
                path.lineWidth = dynamicWidth
            } else {
                path.lineWidth = annotation.strokeWidth
            }
            
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            color.setStroke()
            path.stroke()
        }
        
        // Draw selection handles
        if SelectionManager.shared.selectedAnnotationID == annotation.id {
            if let handles = AnnotationHitTester.getHandles(for: annotation) {
                NSColor.systemBlue.setFill()
                NSColor.white.setStroke()
                
                for (i, handle) in handles.enumerated() {
                    let isControl = (annotation.type == .arrow && i == 1)
                    let handleSize: CGFloat = isControl ? 6.0 : 8.0
                    let rect = NSRect(x: handle.x - handleSize/2, y: handle.y - handleSize/2, width: handleSize, height: handleSize)
                    let path = isControl ? NSBezierPath(ovalIn: rect) : NSBezierPath(rect: rect)
                    
                    path.lineWidth = 1.5
                    path.fill()
                    path.stroke()
                }
            }
        }
        
        NSGraphicsContext.restoreGraphicsState()
    }
    
    private static var roundedFontDescriptor: NSFontDescriptor? = {
        if #available(macOS 11.0, *) {
            return NSFontDescriptor.preferredFontDescriptor(forTextStyle: .body)
                .withDesign(.rounded)?
                .withSymbolicTraits(.bold)
        }
        return nil
    }()
    
    private static func drawText(_ text: String, in rect: CGRect, color: NSColor, fontSize: CGFloat) {
        var font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
        
        if let desc = roundedFontDescriptor, let roundedFont = NSFont(descriptor: desc, size: fontSize) {
            font = roundedFont
        } else if let sfPro = NSFont(name: "SFProRounded-Bold", size: fontSize) {
            font = sfPro
        }
        
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
