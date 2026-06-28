import Cocoa

class AnnotationCanvasView: NSView, NSTextViewDelegate {
    
    private var annotations: [Annotation] = []
    private var currentAnnotation: Annotation?
    private var laserPointerLocation: CGPoint?
    private var laserTimer: Timer?
    
    private var editingTextIndex: Int?
    private var activeTextField: NSTextField?
    private var hoveredAnnotationID: UUID?
    private var trackingArea: NSTrackingArea?
    
    override var acceptsFirstResponder: Bool { true }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea {
            removeTrackingArea(ta)
        }
        trackingArea = NSTrackingArea(rect: bounds, options: [.activeInKeyWindow, .mouseMoved, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        
        // Timer to continually redraw while lasers are active
        laserTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.checkForActiveLasers()
        }
    }
    
    deinit {
        laserTimer?.invalidate()
    }
    
    private func checkForActiveLasers() {
        let hasLasers = annotations.contains { $0.type == .laserPen && ($0.expiresAt ?? Date()) > Date() }
        let hasCurrentLaser = currentAnnotation?.type == .laserPen
        
        if hasLasers || hasCurrentLaser {
            needsDisplay = true
            
            // Clean up expired lasers to save memory
            let now = Date()
            annotations.removeAll { $0.type == .laserPen && ($0.expiresAt ?? now) < now }
        }
    }
    
    func clear() {
        annotations.removeAll()
        currentAnnotation = nil
        needsDisplay = true
    }
    
    func undo() {
        if !annotations.isEmpty {
            annotations.removeLast()
            needsDisplay = true
        }
    }
    
    override func keyDown(with event: NSEvent) {
        guard let characters = event.characters else { return }
        
        // Esc cancels drawing or switches to select
        if event.keyCode == 53 {
            if currentAnnotation != nil {
                // Cancel current drawing
                currentAnnotation = nil
                needsDisplay = true
            } else if ToolManager.shared.activeTool != .select {
                // Switch to select tool and select the last drawn annotation
                ToolManager.shared.activeTool = .select
                if let last = annotations.last, last.type != .laserPen, last.type != .pen {
                    SelectionManager.shared.selectedAnnotationID = last.id
                }
                needsDisplay = true
            } else if SelectionManager.shared.selectedAnnotationID != nil {
                // Clear selection
                SelectionManager.shared.clearSelection()
                needsDisplay = true
            } else {
                // Toggle overlay if already in select mode with no selection
                if let appDelegate = NSApp.delegate as? AppDelegate {
                    appDelegate.overlayWindowController?.toggleOverlay()
                } else {
                    (window?.windowController as? OverlayWindowController)?.toggleOverlay()
                }
            }
            return
        }
        
        // Command + Z for Undo
        if characters.lowercased() == "z" && event.modifierFlags.contains(.command) {
            undo()
            return
        }
        
        // C for Clear
        if characters.lowercased() == "c" {
            promptForClear()
            return
        }
        
        // Backspace or Delete to remove selected annotation
        if event.keyCode == 51 || event.keyCode == 117 {
            if let selectedID = SelectionManager.shared.selectedAnnotationID {
                annotations.removeAll { $0.id == selectedID }
                SelectionManager.shared.clearSelection()
                needsDisplay = true
            }
            return
        }
        
        // Switch tools
        if ToolManager.shared.handleKeyPress(characters) {
            // Tool switched successfully
            return
        }
        
        super.keyDown(with: event)
    }
    
    enum InteractionState {
        case idle
        case drawingNewAnnotation
        case movingSelection(startPoint: CGPoint, originalAnnotation: Annotation)
        case resizingSelection(handleIndex: Int, startPoint: CGPoint, originalAnnotation: Annotation)
    }
    
    private var interactionState: InteractionState = .idle
    
    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        var newHover: UUID? = nil
        
        if ToolManager.shared.activeTool == .select {
            for annotation in annotations.reversed() {
                if AnnotationHitTester.hitTest(point: point, annotation: annotation) != .none {
                    newHover = annotation.id
                    break
                }
            }
        }
        
        if hoveredAnnotationID != newHover {
            hoveredAnnotationID = newHover
            needsDisplay = true
        }
        
        if ToolManager.shared.activeTool == .laserPointer {
            laserPointerLocation = point
            needsDisplay = true
        } else if laserPointerLocation != nil {
            laserPointerLocation = nil
            needsDisplay = true
        }
    }
    
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let tool = ToolManager.shared.activeTool
        let color = SettingsStore.shared.lastSelectedColor
        let width = SettingsStore.shared.lastSelectedStrokeWidth
        
        if tool == .text {
            if activeTextField != nil {
                // If we click outside while a text field is active, let Cocoa end editing
                // by forcing first responder away, and don't create a new text box.
                self.window?.makeFirstResponder(self)
                return
            }
            
            // Check if we hit an existing text annotation
            for (index, annotation) in annotations.enumerated().reversed() {
                if annotation.type == .text && AnnotationHitTester.hitTest(point: point, annotation: annotation) == .body {
                    startTextEditing(existingAnnotation: annotation, at: index)
                    return
                }
            }
            
            // Otherwise start new
            startTextEditing(at: point)
            return
        }
        
        // If in Select mode, check hit test
        if tool == .select {
            // Check if we clicked a selected handle
            if let selectedID = SelectionManager.shared.selectedAnnotationID,
               let index = annotations.firstIndex(where: { $0.id == selectedID }) {
                let hit = AnnotationHitTester.hitTest(point: point, annotation: annotations[index])
                switch hit {
                case .resizeHandle(let idx), .controlHandle(let idx):
                    interactionState = .resizingSelection(handleIndex: idx, startPoint: point, originalAnnotation: annotations[index])
                    return
                case .body:
                    if event.clickCount == 2 && annotations[index].type == .text {
                        startTextEditing(existingAnnotation: annotations[index], at: index)
                        return
                    }
                    interactionState = .movingSelection(startPoint: point, originalAnnotation: annotations[index])
                    return
                case .none:
                    break
                }
            }
            
            // Otherwise, see if we hit another annotation body
            for (index, annotation) in annotations.enumerated().reversed() {
                if AnnotationHitTester.hitTest(point: point, annotation: annotation) != .none {
                    if event.clickCount == 2 && annotation.type == .text {
                        startTextEditing(existingAnnotation: annotation, at: index)
                        return
                    }
                    SelectionManager.shared.selectedAnnotationID = annotation.id
                    interactionState = .movingSelection(startPoint: point, originalAnnotation: annotation)
                    needsDisplay = true
                    return
                }
            }
            
            // Hit nothing, clear selection
            SelectionManager.shared.clearSelection()
            needsDisplay = true
            return
        }
        
        // Otherwise, start drawing
        SelectionManager.shared.clearSelection()
        interactionState = .drawingNewAnnotation
        currentAnnotation = Annotation(type: tool, color: color, strokeWidth: width)
        
        if tool == .arrow {
            currentAnnotation?.arrowStart = point
            currentAnnotation?.arrowEnd = point
        } else if tool == .rectangle || tool == .oval {
            currentAnnotation?.rect = CGRect(origin: point, size: .zero)
        } else {
            currentAnnotation?.points.append(point)
        }
        needsDisplay = true
    }
    
    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        
        if ToolManager.shared.activeTool == .laserPointer {
            laserPointerLocation = point
            needsDisplay = true
            return
        }
        
        
        switch interactionState {
        case .idle:
            break
            
        case .drawingNewAnnotation:
            guard var current = currentAnnotation else { return }
            
            if current.type == .arrow {
                current.arrowEnd = point
                current.arrowControlPoint = CGPoint(x: (current.arrowStart!.x + point.x) / 2, y: (current.arrowStart!.y + point.y) / 2)
            } else if current.type == .rectangle || current.type == .oval {
                let start = current.rect?.origin ?? point
                if current.points.isEmpty { current.points.append(start) }
                let originalStart = current.points[0]
                current.rect = CGRect(
                    x: min(originalStart.x, point.x),
                    y: min(originalStart.y, point.y),
                    width: abs(point.x - originalStart.x),
                    height: abs(point.y - originalStart.y)
                )
            } else {
                current.points.append(point)
            }
            
            currentAnnotation = current
            needsDisplay = true
            
        case .movingSelection(let startPoint, let originalAnnotation):
            guard let index = annotations.firstIndex(where: { $0.id == originalAnnotation.id }) else { return }
            let dx = point.x - startPoint.x
            let dy = point.y - startPoint.y
            
            var moved = originalAnnotation
            if moved.type == .arrow {
                moved.arrowStart = CGPoint(x: moved.arrowStart!.x + dx, y: moved.arrowStart!.y + dy)
                moved.arrowEnd = CGPoint(x: moved.arrowEnd!.x + dx, y: moved.arrowEnd!.y + dy)
                if let ctrl = moved.arrowControlPoint {
                    moved.arrowControlPoint = CGPoint(x: ctrl.x + dx, y: ctrl.y + dy)
                }
            } else if moved.type == .rectangle || moved.type == .oval {
                if let r = moved.rect {
                    moved.rect = r.offsetBy(dx: dx, dy: dy)
                }
            } else if moved.type == .pen || moved.type == .laserPen {
                moved.points = moved.points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
            } else if moved.type == .text {
                if let r = moved.textRect {
                    moved.textRect = r.offsetBy(dx: dx, dy: dy)
                }
            }
            annotations[index] = moved
            needsDisplay = true
            
        case .resizingSelection(let handleIndex, let startPoint, let originalAnnotation):
            guard let index = annotations.firstIndex(where: { $0.id == originalAnnotation.id }) else { return }
            let dx = point.x - startPoint.x
            let dy = point.y - startPoint.y
            
            var resized = originalAnnotation
            if resized.type == .arrow {
                if handleIndex == 0 {
                    resized.arrowStart = CGPoint(x: resized.arrowStart!.x + dx, y: resized.arrowStart!.y + dy)
                } else if handleIndex == 1 {
                    let oldCtrl = resized.arrowControlPoint ?? CGPoint(x: (resized.arrowStart!.x + resized.arrowEnd!.x)/2, y: (resized.arrowStart!.y + resized.arrowEnd!.y)/2)
                    resized.arrowControlPoint = CGPoint(x: oldCtrl.x + 2 * dx, y: oldCtrl.y + 2 * dy)
                } else if handleIndex == 2 {
                    resized.arrowEnd = CGPoint(x: resized.arrowEnd!.x + dx, y: resized.arrowEnd!.y + dy)
                }
            } else if resized.type == .pen || resized.type == .laserPen {
                if let handles = AnnotationHitTester.getHandles(for: originalAnnotation) {
                    let oppositeIndex = 3 - handleIndex
                    let anchor = handles[oppositeIndex]
                    let currentHandle = handles[handleIndex]
                    
                    let newHandle = CGPoint(x: currentHandle.x + dx, y: currentHandle.y + dy)
                    let origW = abs(currentHandle.x - anchor.x)
                    let origH = abs(currentHandle.y - anchor.y)
                    
                    if origW > 1.0 && origH > 1.0 {
                        let newW = abs(newHandle.x - anchor.x)
                        let newH = abs(newHandle.y - anchor.y)
                        let scale = max(0.1, max(newW / origW, newH / origH))
                        
                        resized.points = originalAnnotation.points.map { p in
                            return CGPoint(x: anchor.x + (p.x - anchor.x) * scale,
                                           y: anchor.y + (p.y - anchor.y) * scale)
                        }
                    }
                }
            } else if resized.type == .text {
                guard let r = resized.textRect else { return }
                
                if handleIndex == 2 {
                    // Scaling handle (bottom-right)
                    let scaleFactor = max(0.1, 1.0 + (dx * 0.01))
                    
                    var resizedFont = originalAnnotation.fontSize * scaleFactor
                    resizedFont = max(8, min(resizedFont, 200)) // clamp
                    resized.fontSize = resizedFont
                    
                    if let text = resized.text, let origRect = originalAnnotation.textRect {
                        let font = NSFont(name: "Marker Felt", size: resizedFont) ?? NSFont.systemFont(ofSize: resizedFont, weight: .bold)
                        let attributes: [NSAttributedString.Key: Any] = [.font: font]
                        
                        let fontScale = resizedFont / originalAnnotation.fontSize
                        let newWidth = max(50.0, origRect.width * fontScale)
                        
                        let boundingRect = (text as NSString).boundingRect(
                            with: NSSize(width: newWidth, height: .greatestFiniteMagnitude),
                            options: [.usesLineFragmentOrigin, .usesFontLeading],
                            attributes: attributes
                        )
                        let height = boundingRect.height
                        
                        // Keep top-left anchored
                        let topY = origRect.maxY
                        let leftX = origRect.minX
                        resized.textRect = CGRect(x: leftX, y: topY - height, width: newWidth, height: height)
                    }
                } else {
                    var minX = r.minX
                    var maxX = r.maxX
                    let oldMaxY = r.maxY // Top edge in bottom-left coordinate system
                    
                    if handleIndex == 0 { // minX handle
                        minX += dx
                    } else if handleIndex == 1 { // maxX handle
                        maxX += dx
                    }
                    
                    let width = max(50.0, abs(maxX - minX))
                    let minXFixed = min(minX, maxX)
                    
                    if let text = resized.text {
                        let font = NSFont(name: "Marker Felt", size: resized.fontSize) ?? NSFont.systemFont(ofSize: resized.fontSize, weight: .bold)
                        let attributes: [NSAttributedString.Key: Any] = [.font: font]
                        let boundingRect = (text as NSString).boundingRect(
                            with: NSSize(width: width, height: .greatestFiniteMagnitude),
                            options: [.usesLineFragmentOrigin, .usesFontLeading],
                            attributes: attributes
                        )
                        let height = boundingRect.height
                        
                        // Keep the top edge anchored
                        resized.textRect = CGRect(x: minXFixed, y: oldMaxY - height, width: width, height: height)
                    }
                }
            } else if resized.type == .rectangle || resized.type == .oval {
                guard let r = resized.rect else { return }
                
                var minX = r.minX
                var minY = r.minY
                var maxX = r.maxX
                var maxY = r.maxY
                
                if handleIndex == 0 { // minX, minY
                    minX += dx; minY += dy
                } else if handleIndex == 1 { // maxX, minY
                    maxX += dx; minY += dy
                } else if handleIndex == 2 { // minX, maxY
                    minX += dx; maxY += dy
                } else if handleIndex == 3 { // maxX, maxY
                    maxX += dx; maxY += dy
                }
                
                // Keep valid rect with minimum size constraints
                let width = max(20.0, abs(maxX - minX))
                let height = max(20.0, abs(maxY - minY))
                let newRect = CGRect(x: min(minX, maxX), y: min(minY, maxY), width: width, height: height)
                resized.rect = newRect
            }
            annotations[index] = resized
            needsDisplay = true
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        
        switch interactionState {
        case .idle:
            break
            
        case .drawingNewAnnotation:
            guard var finalAnnotation = currentAnnotation else { return }
            
            var annotationAdded = false
            if finalAnnotation.type == .arrow {
                finalAnnotation.arrowEnd = point
                // Only create the arrow if the user dragged a minimum distance
                if let start = finalAnnotation.arrowStart, start.distance(to: point) > 5.0 {
                    finalAnnotation.arrowControlPoint = CGPoint(x: (start.x + point.x) / 2, y: (start.y + point.y) / 2)
                    annotations.append(finalAnnotation)
                    annotationAdded = true
                }
            } else if finalAnnotation.type == .rectangle || finalAnnotation.type == .oval {
                let originalStart = finalAnnotation.points.first ?? point
                finalAnnotation.rect = CGRect(
                    x: min(originalStart.x, point.x),
                    y: min(originalStart.y, point.y),
                    width: abs(point.x - originalStart.x),
                    height: abs(point.y - originalStart.y)
                )
                finalAnnotation.points.removeAll()
                if (finalAnnotation.rect?.width ?? 0) > 1 || (finalAnnotation.rect?.height ?? 0) > 1 {
                    annotations.append(finalAnnotation)
                    annotationAdded = true
                }
            } else {
                finalAnnotation.points.append(point)
                if finalAnnotation.points.count > 1 || finalAnnotation.type == .pen || finalAnnotation.type == .laserPen {
                    annotations.append(finalAnnotation)
                    annotationAdded = true
                }
            }
            
            if !annotationAdded && ToolManager.shared.activeTool != .select && ToolManager.shared.activeTool != .text {
                ToolManager.shared.activeTool = .select
            }
            
            if ToolManager.shared.activeTool == .select {
                SelectionManager.shared.selectedAnnotationID = finalAnnotation.id
            } else {
                SelectionManager.shared.clearSelection()
            }
            
            currentAnnotation = nil
            
        case .movingSelection, .resizingSelection:
            // End of drag
            // We just update the state
            // If it's too small, maybe delete it, but fine for now
            break
        }
        
        interactionState = .idle
        needsDisplay = true
    }
    private var activeTextMaxWidth: CGFloat = 300.0
    
    private func startTextEditing(at point: CGPoint) {
        if let existing = activeTextView {
            existing.removeFromSuperview()
        }
        
        editingTextIndex = nil
        
        // Calculate available width based on click position and window bounds
        let availableWidth = (self.bounds.width - point.x) - 20
        activeTextMaxWidth = max(50.0, availableWidth) // Unlimited up to screen edge
        
        let textView = NSTextView(frame: NSRect(x: point.x, y: point.y - 12, width: 50, height: 30))
        setupTextView(textView)
        
        self.addSubview(textView)
        self.window?.makeFirstResponder(textView)
        activeTextView = textView
    }
    
    private var activeTextView: NSTextView?
    
    private func startTextEditing(existingAnnotation: Annotation, at index: Int) {
        if let existing = activeTextView {
            existing.removeFromSuperview()
        }
        
        editingTextIndex = index
        let rect = existingAnnotation.textRect ?? CGRect(x: 0, y: 0, width: 200, height: 30)
        
        let availableWidth = (self.bounds.width - rect.minX) - 20
        activeTextMaxWidth = max(50.0, availableWidth)
        
        let textView = NSTextView(frame: NSRect(x: rect.minX, y: rect.minY, width: max(rect.width, 50), height: max(rect.height, 30)))
        setupTextView(textView)
        textView.font = NSFont(name: "Marker Felt", size: existingAnnotation.fontSize) ?? NSFont.systemFont(ofSize: existingAnnotation.fontSize, weight: .bold)
        textView.textColor = existingAnnotation.color
        textView.string = existingAnnotation.text ?? ""
        
        self.addSubview(textView)
        self.window?.makeFirstResponder(textView)
        
        // Move cursor to end
        textView.setSelectedRange(NSRange(location: textView.string.count, length: 0))
        
        activeTextView = textView
        self.needsDisplay = true // Redraw to hide the original annotation
        
        // Ensure proper initial size
        adjustTextViewSize(textView)
    }
    
    private func setupTextView(_ textView: NSTextView) {
        textView.delegate = self
        textView.drawsBackground = false
        textView.isRichText = false
        let fontSize = Annotation.fontSize(for: SettingsStore.shared.lastSelectedStrokeWidth)
        textView.font = NSFont(name: "Marker Felt", size: fontSize) ?? NSFont.systemFont(ofSize: fontSize, weight: .bold)
        textView.textColor = SettingsStore.shared.lastSelectedColor
        textView.isEditable = true
        textView.isSelectable = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: activeTextMaxWidth, height: .greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = false
        textView.textContainerInset = NSSize(width: 0, height: 0)
    }
    
    func textDidChange(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView else { return }
        adjustTextViewSize(textView)
    }
    
    private func adjustTextViewSize(_ textView: NSTextView) {
        guard let layoutManager = textView.layoutManager, let textContainer = textView.textContainer else { return }
        
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        let requiredHeight = max(30.0, usedRect.height + 10.0) // Add padding
        let requiredWidth = max(50.0, min(activeTextMaxWidth, usedRect.width + 10.0)) // Add padding
        let currentFrame = textView.frame
        
        var newFrame = currentFrame
        var changed = false
        
        if requiredHeight > currentFrame.height {
            let heightDiff = requiredHeight - currentFrame.height
            // NSView origin is bottom-left, so to keep the top edge fixed, we decrease Y by the height difference
            newFrame.origin.y -= heightDiff
            newFrame.size.height = requiredHeight
            changed = true
        }
        
        if requiredWidth != currentFrame.width {
            newFrame.size.width = requiredWidth
            changed = true
        }
        
        if changed {
            textView.frame = newFrame
        }
    }
    
    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            // Escape key finishes editing
            self.window?.makeFirstResponder(self)
            return true
        } else if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            textView.insertText("\n", replacementRange: textView.selectedRange())
            return true
        }
        return false
    }
    
    func textDidEndEditing(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView else { return }
        let text = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if !text.isEmpty {
            let font = textView.font ?? NSFont(name: "Marker Felt", size: 28) ?? NSFont.systemFont(ofSize: 24, weight: .bold)
            
            // Strictly calculate text bounds to snap the handles perfectly
            let attributes: [NSAttributedString.Key: Any] = [.font: font]
            let boundingRect = (text as NSString).boundingRect(
                with: NSSize(width: activeTextMaxWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attributes
            )
            
            let finalWidth = max(50.0, boundingRect.width + 10.0) // tiny padding for italics
            let finalHeight = max(30.0, boundingRect.height)
            let heightDiff = finalHeight - textView.frame.height
            
            let finalRect = CGRect(
                x: textView.frame.minX,
                y: textView.frame.minY - heightDiff,
                width: finalWidth,
                height: finalHeight
            )
            
            if let index = editingTextIndex {
                annotations[index].text = text
                annotations[index].textRect = finalRect
                annotations[index].fontSize = font.pointSize
                ToolManager.shared.activeTool = .select
                SelectionManager.shared.selectedAnnotationID = annotations[index].id
            } else {
                var annotation = Annotation(type: .text, color: SettingsStore.shared.lastSelectedColor, strokeWidth: SettingsStore.shared.lastSelectedStrokeWidth)
                annotation.text = text
                annotation.textRect = finalRect
                annotation.fontSize = font.pointSize
                annotations.append(annotation)
                
                ToolManager.shared.activeTool = .select
                SelectionManager.shared.selectedAnnotationID = annotation.id
            }
        } else {
            // Empty text
            if let index = editingTextIndex {
                annotations.remove(at: index)
            }
        }
        
        textView.removeFromSuperview()
        activeTextView = nil
        editingTextIndex = nil
        self.window?.makeFirstResponder(self)
        needsDisplay = true
    }
    
    private func promptForClear() {
        if let overlay = self.window?.windowController as? OverlayWindowController {
            overlay.showClearPrompt()
        } else {
            // Fallback just in case
            clear()
        }
    }
    
    private var isDragging: Bool {
        if case .resizingSelection = interactionState {
            return true
        }
        return false
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        // Draw confirmed annotations (skip the one being edited to avoid double-rendering / shadow effect)
        var annotationsToDraw = annotations
        if let editingIndex = editingTextIndex, editingIndex < annotationsToDraw.count {
            annotationsToDraw.remove(at: editingIndex)
        }
        
        AnnotationRenderer.draw(annotationsToDraw, in: context, isDragging: self.isDragging, hoveredID: hoveredAnnotationID)
        
        // Draw in-progress annotation
        if let current = currentAnnotation {
            AnnotationRenderer.draw([current], in: context, isDragging: self.isDragging)
        }
        
        // Draw laser pointer
        if ToolManager.shared.activeTool == .laserPointer, let pointerLoc = laserPointerLocation {
            let color = SettingsStore.shared.lastSelectedColor
            
            // Outer glow
            context.setFillColor(color.withAlphaComponent(0.3).cgColor)
            context.fillEllipse(in: CGRect(x: pointerLoc.x - 12, y: pointerLoc.y - 12, width: 24, height: 24))
            
            // Inner core
            context.setFillColor(color.cgColor)
            context.fillEllipse(in: CGRect(x: pointerLoc.x - 4, y: pointerLoc.y - 4, width: 8, height: 8))
        }
    }
}
