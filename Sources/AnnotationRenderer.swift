import Cocoa

class AnnotationRenderer {
    
    static func draw(_ annotations: [Annotation], in context: CGContext, isDragging: Bool = false) {
        let now = Date()
        
        for annotation in annotations {
            if let expiresAt = annotation.expiresAt {
                if now > expiresAt {
                    continue
                }
                
                let timeLeft = expiresAt.timeIntervalSince(now)
                let alpha = max(0, min(1.0, CGFloat(timeLeft / 0.5)))
                
                let fadedColor = annotation.color.withAlphaComponent(alpha)
                drawAnnotation(annotation, color: fadedColor, in: context, isDragging: isDragging)
            } else {
                drawAnnotation(annotation, color: annotation.color, in: context, isDragging: isDragging)
            }
        }
    }
    
    private static func drawAnnotation(_ annotation: Annotation, color: NSColor, in context: CGContext, isDragging: Bool) {
        NSGraphicsContext.saveGraphicsState()
        let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.current = nsContext
        
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
        } else if annotation.type == .pen || annotation.type == .laser || annotation.type == .rectangle || annotation.type == .oval || annotation.type == .arrow {
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
        
        if !isDragging && SelectionManager.shared.selectedAnnotationID == annotation.id {
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
                    let path = NSBezierPath(ovalIn: rect) // Always circles
                    
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
