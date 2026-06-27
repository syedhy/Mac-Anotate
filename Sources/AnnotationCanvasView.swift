import Cocoa

class AnnotationCanvasView: NSView, NSTextFieldDelegate {
    
    private var annotations: [Annotation] = []
    private var currentAnnotation: Annotation?
    private var laserTimer: Timer?
    
    // For text entry
    private var activeTextField: NSTextField?
    
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
    
    override var acceptsFirstResponder: Bool {
        return true
    }
    
    private func checkForActiveLasers() {
        let hasLasers = annotations.contains { $0.type == .laser && ($0.expiresAt ?? Date()) > Date() }
        let hasCurrentLaser = currentAnnotation?.type == .laser
        
        if hasLasers || hasCurrentLaser {
            needsDisplay = true
            
            // Clean up expired lasers to save memory
            let now = Date()
            annotations.removeAll { $0.type == .laser && ($0.expiresAt ?? now) < now }
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
                if let last = annotations.last, last.type != .laser, last.type != .pen {
                    SelectionManager.shared.selectedAnnotationID = last.id
                }
                needsDisplay = true
            } else if SelectionManager.shared.selectedAnnotationID != nil {
                // Clear selection
                SelectionManager.shared.clearSelection()
                needsDisplay = true
            } else {
                // Toggle overlay if already in select mode with no selection
                (window?.windowController as? OverlayWindowController)?.toggleOverlay()
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
    
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let tool = ToolManager.shared.activeTool
        let color = SettingsStore.shared.lastSelectedColor
        let width = SettingsStore.shared.lastSelectedStrokeWidth
        
        if tool == .text {
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
                    interactionState = .movingSelection(startPoint: point, originalAnnotation: annotations[index])
                    return
                case .none:
                    break
                }
            }
            
            // Otherwise, see if we hit another annotation body
            for annotation in annotations.reversed() {
                if AnnotationHitTester.hitTest(point: point, annotation: annotation) != .none {
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
            } else if moved.type == .pen || moved.type == .laser {
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
                    resized.arrowControlPoint = CGPoint(x: oldCtrl.x + dx, y: oldCtrl.y + dy)
                } else if handleIndex == 2 {
                    resized.arrowEnd = CGPoint(x: resized.arrowEnd!.x + dx, y: resized.arrowEnd!.y + dy)
                }
            } else if resized.type == .pen || resized.type == .laser {
                resized.points = resized.points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
            } else if resized.type == .rectangle || resized.type == .oval || resized.type == .text {
                let r: CGRect
                if resized.type == .text {
                    guard let tr = resized.textRect else { return }
                    r = tr
                } else {
                    guard let rr = resized.rect else { return }
                    r = rr
                }
                
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
                
                // Keep valid rect
                let newRect = CGRect(x: min(minX, maxX), y: min(minY, maxY), width: abs(maxX - minX), height: abs(maxY - minY))
                if resized.type == .text {
                    resized.textRect = newRect
                } else {
                    resized.rect = newRect
                }
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
            
            if finalAnnotation.type == .arrow {
                finalAnnotation.arrowEnd = point
                // Only create the arrow if the user dragged a minimum distance
                if let start = finalAnnotation.arrowStart, start.distance(to: point) > 5.0 {
                    finalAnnotation.arrowControlPoint = CGPoint(x: (start.x + point.x) / 2, y: (start.y + point.y) / 2)
                    annotations.append(finalAnnotation)
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
                }
            } else {
                finalAnnotation.points.append(point)
                if finalAnnotation.points.count > 1 || finalAnnotation.type == .pen || finalAnnotation.type == .laser {
                    annotations.append(finalAnnotation)
                }
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
    
    private var editingTextIndex: Int?
    
    private func startTextEditing(at point: CGPoint) {
        if let existing = activeTextField {
            existing.removeFromSuperview()
        }
        
        editingTextIndex = nil
        
        // Convert to view coordinates. The click point is already in view coords.
        let textField = NSTextField(frame: NSRect(x: point.x, y: point.y - 12, width: 200, height: 30))
        setupTextField(textField)
        
        self.addSubview(textField)
        self.window?.makeFirstResponder(textField)
        activeTextField = textField
    }
    
    private func startTextEditing(existingAnnotation: Annotation, at index: Int) {
        if let existing = activeTextField {
            existing.removeFromSuperview()
        }
        
        editingTextIndex = index
        let rect = existingAnnotation.textRect ?? CGRect(x: 0, y: 0, width: 200, height: 30)
        
        let textField = NSTextField(frame: NSRect(x: rect.minX, y: rect.minY, width: max(rect.width, 200), height: max(rect.height, 30)))
        setupTextField(textField)
        textField.stringValue = existingAnnotation.text ?? ""
        
        self.addSubview(textField)
        self.window?.makeFirstResponder(textField)
        activeTextField = textField
    }
    
    private func setupTextField(_ textField: NSTextField) {
        textField.delegate = self
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.font = NSFont.systemFont(ofSize: 24, weight: .bold)
        textField.textColor = SettingsStore.shared.lastSelectedColor
        textField.isEditable = true
        textField.isSelectable = true
    }
    
    func controlTextDidEndEditing(_ obj: Notification) {
        guard let textField = activeTextField else { return }
        let text = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if !text.isEmpty {
            let font = textField.font ?? NSFont.systemFont(ofSize: 24, weight: .bold)
            let attributes: [NSAttributedString.Key: Any] = [.font: font]
            let size = (text as NSString).size(withAttributes: attributes)
            let rect = CGRect(origin: textField.frame.origin, size: size)
            
            if let index = editingTextIndex {
                annotations[index].text = text
                annotations[index].textRect = rect
                annotations[index].fontSize = font.pointSize
            } else {
                var annotation = Annotation(type: .text, color: SettingsStore.shared.lastSelectedColor, strokeWidth: SettingsStore.shared.lastSelectedStrokeWidth)
                annotation.text = text
                annotation.textRect = rect
                annotation.fontSize = font.pointSize
                annotations.append(annotation)
                
                // Also select it
                if ToolManager.shared.activeTool == .select {
                    SelectionManager.shared.selectedAnnotationID = annotation.id
                }
            }
        } else {
            // Empty text
            if let index = editingTextIndex {
                annotations.remove(at: index)
            }
        }
        
        textField.removeFromSuperview()
        activeTextField = nil
        editingTextIndex = nil
        self.window?.makeFirstResponder(self)
        needsDisplay = true
    }
    
    private func promptForClear() {
        let alert = NSAlert()
        alert.messageText = "Clear all annotations?"
        alert.informativeText = "This action cannot be undone."
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            clear()
        }
        window?.makeFirstResponder(self)
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        // Draw confirmed annotations
        AnnotationRenderer.draw(annotations, in: context)
        
        // Draw current in-progress annotation
        if let current = currentAnnotation {
            AnnotationRenderer.draw([current], in: context)
        }
    }
}
