import Cocoa
import Combine
import SwiftUI
import UniformTypeIdentifiers

class AnnotationCanvasView: NSView, NSTextViewDelegate {

    private var annotations: [Annotation] = []
    private var currentAnnotation: Annotation?
    private var redoStack: [Annotation] = []
    private var laserPointerLocation: CGPoint?
    var hoveredAnnotationID: UUID?
    private var marqueeRect: CGRect?
    private var laserTimer: Timer?

    private var editingTextIndex: Int?
    private var activeTextView: NSTextView?
    private var trackingArea: NSTrackingArea?
    private var cancellables = Set<AnyCancellable>()
    private var propertiesHostingView: NSHostingView<AnyView>!
    private var propertiesTrailingConstraint: NSLayoutConstraint!

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

        propertiesHostingView = NSHostingView(rootView: AnyView(EmptyView()))
        propertiesHostingView.isHidden = true
        propertiesHostingView.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(propertiesHostingView)

        propertiesTrailingConstraint = propertiesHostingView.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -20)
        NSLayoutConstraint.activate([
            propertiesHostingView.topAnchor.constraint(equalTo: self.topAnchor, constant: 20),
            propertiesTrailingConstraint
        ])

        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.checkForActiveLasers()
        }
        RunLoop.main.add(timer, forMode: .common)
        laserTimer = timer

        ToolManager.shared.objectWillChange.sink { [weak self] _ in
            self?.commitTextEditingIfActive()
        }.store(in: &cancellables)

        SettingsStore.shared.objectWillChange.sink { [weak self] _ in
            self?.commitTextEditingIfActive()
        }.store(in: &cancellables)
    }

    private func commitTextEditingIfActive() {
        if activeTextView != nil {
            self.window?.makeFirstResponder(self)
        }
    }

    deinit {
        laserTimer?.invalidate()
    }

    private func checkForActiveLasers() {
        let now = Date()
        let hasExpiredLasers = annotations.contains { $0.type == .laserPen && ($0.expiresAt ?? now) < now }

        if hasExpiredLasers {
            annotations.removeAll { $0.type == .laserPen && ($0.expiresAt ?? now) < now }
            needsDisplay = true
        }

        let hasLasers = annotations.contains { $0.type == .laserPen && ($0.expiresAt ?? now) > now }
        let hasCurrentLaser = currentAnnotation?.type == .laserPen

        if hasLasers || hasCurrentLaser {
            needsDisplay = true
        }
    }

    func clear() {
        activeTextView?.removeFromSuperview()
        activeTextView = nil
        editingTextIndex = nil
        annotations.removeAll()
        redoStack.removeAll()
        currentAnnotation = nil
        hoveredAnnotationID = nil
        marqueeRect = nil
        interactionState = .idle
        SelectionManager.shared.clearSelection()
        needsDisplay = true
    }

    func undo() {
        guard let removed = annotations.popLast() else { return }

        redoStack.append(removed)
        if SelectionManager.shared.selectedAnnotationIDs.contains(removed.id) {
            SelectionManager.shared.clearSelection()
        }
        if hoveredAnnotationID == removed.id {
            hoveredAnnotationID = nil
        }
        needsDisplay = true
    }

    func redo() {
        guard let restored = redoStack.popLast() else { return }
        annotations.append(restored)
        SelectionManager.shared.selectedAnnotationIDs = [restored.id]
        SelectionManager.shared.wasMarqueeSelected = false
        needsDisplay = true
    }

    private func duplicateSelectedAnnotations() {
        commitTextEditingIfActive()

        let selectedIDs = SelectionManager.shared.selectedAnnotationIDs
        let selectedAnnotations = annotations.filter { selectedIDs.contains($0.id) && $0.type != .laserPen }
        guard !selectedAnnotations.isEmpty else {
            NSSound.beep()
            return
        }

        let duplicates = selectedAnnotations.map { annotation in
            var copy = annotation
            copy.id = UUID()
            copy.offsetBy(dx: 16, dy: -16)
            return copy
        }

        annotations.append(contentsOf: duplicates)
        redoStack.removeAll()
        SelectionManager.shared.selectedAnnotationIDs = Set(duplicates.map { $0.id })
        SelectionManager.shared.wasMarqueeSelected = duplicates.count > 1
        needsDisplay = true
    }

    func exportAnnotations() {
        commitTextEditingIfActive()

        let exportableAnnotations = annotations.filter { annotation in
            annotation.type != .laserPen || (annotation.expiresAt ?? Date.distantFuture) > Date()
        }

        guard !exportableAnnotations.isEmpty else {
            NSSound.beep()
            return
        }

        let savePanel = NSSavePanel()
        savePanel.title = "Export Annotations"
        savePanel.nameFieldStringValue = "Mac Annotate.png"
        savePanel.allowedContentTypes = [.png]
        savePanel.canCreateDirectories = true

        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = savePanel.url, let self = self else { return }
            guard let data = self.pngData(for: exportableAnnotations) else {
                NSSound.beep()
                return
            }

            do {
                try data.write(to: url)
            } catch {
                NSSound.beep()
                print("Mac Annotate: failed to export annotations: \(error)")
            }
        }

        if let window = self.window {
            savePanel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            savePanel.begin(completionHandler: completion)
        }
    }

    private func pngData(for annotations: [Annotation]) -> Data? {
        let width = max(1, Int(bounds.width.rounded(.up)))
        let height = max(1, Int(bounds.height.rounded(.up)))
        guard let screenImage = screenCaptureExcludingOverlay() else { return nil }

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [.alphaFirst],
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }

        bitmap.size = bounds.size
        guard let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        NSImage(cgImage: screenImage, size: bounds.size).draw(
            in: bounds,
            from: .zero,
            operation: .copy,
            fraction: 1.0
        )
        AnnotationRenderer.draw(annotations, in: graphicsContext.cgContext, showsSelection: false)
        NSGraphicsContext.restoreGraphicsState()

        return bitmap.representation(using: .png, properties: [:])
    }

    private func screenCaptureExcludingOverlay() -> CGImage? {
        guard let window else { return nil }

        let viewRectInWindow = convert(bounds, to: nil)
        let screenRect = window.convertToScreen(viewRectInWindow)
        guard screenRect.width > 0, screenRect.height > 0 else { return nil }

        return CGWindowListCreateImage(
            screenRect,
            .optionOnScreenBelowWindow,
            CGWindowID(window.windowNumber),
            [.bestResolution, .boundsIgnoreFraming]
        )
    }

    override func keyDown(with event: NSEvent) {
        guard let characters = event.characters else { return }

        // Esc key handling
        if event.keyCode == 53 {
            if let appDelegate = NSApp.delegate as? AppDelegate {
                appDelegate.overlayWindowController?.hideShortcutHelp()
            }

            if currentAnnotation != nil {
                // Cancel current drawing in progress
                currentAnnotation = nil
                SelectionManager.shared.clearSelection()
                ToolManager.shared.activeTool = .select
                needsDisplay = true
                return
            }

            let hasSelection = !SelectionManager.shared.selectedAnnotationIDs.isEmpty
            let isNotSelectTool = ToolManager.shared.activeTool != .select

            if hasSelection || isNotSelectTool {
                // First Escape press: Deselect the active shape (hide transform/resize handles)
                // and switch the active tool to the Selection/Pointer tool.
                SelectionManager.shared.clearSelection()
                ToolManager.shared.activeTool = .select
                needsDisplay = true
            } else {
                // Second Escape press: Hide/minimize the application window.
                if let appDelegate = NSApp.delegate as? AppDelegate {
                    appDelegate.overlayWindowController?.toggleOverlay()
                } else {
                    (window?.windowController as? OverlayWindowController)?.toggleOverlay()
                }
            }
            return
        }

        // 'H' key to toggle toolbar visibility
        if event.keyCode == 4 { // 'H' key
            SettingsStore.shared.isToolbarHidden.toggle()
            return
        }

        // Command + Z for Undo
        if characters.lowercased() == "z" && event.modifierFlags.contains(.command) {
            if event.modifierFlags.contains(.shift) {
                redo()
            } else {
                undo()
            }
            return
        }

        // Command + Y for Redo
        if characters.lowercased() == "y" && event.modifierFlags.contains(.command) {
            redo()
            return
        }

        // Command + A for Select All
        if characters.lowercased() == "a" && (event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control)) {
            ToolManager.shared.activeTool = .select
            SelectionManager.shared.selectedAnnotationIDs = Set(annotations.filter { $0.type != .laserPen }.map { $0.id })
            SelectionManager.shared.wasMarqueeSelected = true
            needsDisplay = true
            return
        }

        // Command + D for Duplicate
        if characters.lowercased() == "d" && event.modifierFlags.contains(.command) {
            duplicateSelectedAnnotations()
            return
        }

        // C for Clear
        if characters.lowercased() == "c" {
            promptForClear()
            return
        }

        // Backspace or Delete to remove selected annotation
        if event.keyCode == 51 || event.keyCode == 117 {
            if !SelectionManager.shared.selectedAnnotationIDs.isEmpty {
                annotations.removeAll { SelectionManager.shared.selectedAnnotationIDs.contains($0.id) }
                redoStack.removeAll()
                SelectionManager.shared.clearSelection()
                needsDisplay = true
            }
            return
        }

        // F to toggle fill style
        if characters.lowercased() == "f" {
            if !SelectionManager.shared.selectedAnnotationIDs.isEmpty {
                var modified = false
                for id in SelectionManager.shared.selectedAnnotationIDs {
                    if let index = annotations.firstIndex(where: { $0.id == id }) {
                        let ann = annotations[index]
                        if ann.type == .rectangle || ann.type == .oval || ann.type == .text {
                            let nextStyle: ShapeFillStyle
                            switch ann.fillStyle {
                            case .hollow: nextStyle = .translucent
                            case .translucent: nextStyle = .filled
                            case .filled: nextStyle = .hollow
                            }
                            annotations[index].fillStyle = nextStyle
                            modified = true
                        }
                    }
                }
                if modified {
                    redoStack.removeAll()
                    needsDisplay = true
                    return
                }
            } else {
                let nextStyle: ShapeFillStyle
                switch SettingsStore.shared.lastSelectedFillStyle {
                case .hollow: nextStyle = .translucent
                case .translucent: nextStyle = .filled
                case .filled: nextStyle = .hollow
                }
                SettingsStore.shared.lastSelectedFillStyle = nextStyle
                return
            }
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
        case resizingSelection(handleIndex: Int, startPoint: CGPoint, originalAnnotation: Annotation)
        case movingSelection(startPoint: CGPoint, originalAnnotations: [UUID: Annotation])
        case marqueeSelection(startPoint: CGPoint, currentRect: CGRect)
        case resizingMultipleSelection(startPoint: CGPoint, originalAnnotations: [UUID: Annotation], groupBoundingBox: CGRect)
    }

    private var interactionState: InteractionState = .idle

    override func mouseMoved(with event: NSEvent) {
        if activeTextView != nil { return }

        let point = convert(event.locationInWindow, from: nil)
        var newHover: UUID? = nil

        if ToolManager.shared.activeTool == .select || !SelectionManager.shared.selectedAnnotationIDs.isEmpty {
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
            if activeTextView != nil {
                // If we click outside while a text field is active, let Cocoa end editing
                // by forcing first responder away, and don't create a new text box.
                self.window?.makeFirstResponder(self)
                return
            }

            // Check if user clicked an already selected text's handles or body
            if !SelectionManager.shared.selectedAnnotationIDs.isEmpty {
                for selectedID in SelectionManager.shared.selectedAnnotationIDs {
                    if let index = annotations.firstIndex(where: { $0.id == selectedID }) {
                        let hit = AnnotationHitTester.hitTest(point: point, annotation: annotations[index])
                        switch hit {
                        case .resizeHandle(let idx), .controlHandle(let idx):
                            if SelectionManager.shared.selectedAnnotationIDs.count == 1 && !SelectionManager.shared.wasMarqueeSelected {
                                redoStack.removeAll()
                                interactionState = .resizingSelection(handleIndex: idx, startPoint: point, originalAnnotation: annotations[index])
                                return
                            }
                        case .body:
                            if annotations[index].type == .text {
                                startTextEditing(existingAnnotation: annotations[index], at: index)
                                return
                            }
                        case .none:
                            break
                        }
                    }
                }
            }

            SelectionManager.shared.clearSelection()
            needsDisplay = true

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

        // Check if user clicked on an already selected annotation's handles or body (works for all tools!)
        var clickedSelectedBody = false
        if !SelectionManager.shared.selectedAnnotationIDs.isEmpty {
            for selectedID in SelectionManager.shared.selectedAnnotationIDs {
                if let index = annotations.firstIndex(where: { $0.id == selectedID }) {
                    let hit = AnnotationHitTester.hitTest(point: point, annotation: annotations[index])
                    switch hit {
                    case .resizeHandle(let idx), .controlHandle(let idx):
                        if SelectionManager.shared.selectedAnnotationIDs.count == 1 && !SelectionManager.shared.wasMarqueeSelected {
                            redoStack.removeAll()
                            interactionState = .resizingSelection(handleIndex: idx, startPoint: point, originalAnnotation: annotations[index])
                            return
                        }
                    case .body:
                        if event.clickCount == 2 && annotations[index].type == .text && SelectionManager.shared.selectedAnnotationIDs.count == 1 {
                            startTextEditing(existingAnnotation: annotations[index], at: index)
                            return
                        }
                        clickedSelectedBody = true
                    case .none:
                        break
                    }
                }
            }

            // Then check group bounding box for resizing (multiple items) or moving
            if let groupBB = AnnotationHitTester.getGroupBoundingBox(for: annotations, selectedIDs: SelectionManager.shared.selectedAnnotationIDs) {
                var originals: [UUID: Annotation] = [:]
                for id in SelectionManager.shared.selectedAnnotationIDs {
                    if let ann = annotations.first(where: { $0.id == id }) {
                        originals[id] = ann
                    }
                }

                let shouldShowGroupBB = SelectionManager.shared.selectedAnnotationIDs.count > 1 || (SelectionManager.shared.selectedAnnotationIDs.count == 1 && SelectionManager.shared.wasMarqueeSelected)

                if shouldShowGroupBB {
                    let groupHandle = CGPoint(x: groupBB.maxX, y: groupBB.maxY)
                    if point.distance(to: groupHandle) < 10.0 {
                        redoStack.removeAll()
                        interactionState = .resizingMultipleSelection(startPoint: point, originalAnnotations: originals, groupBoundingBox: groupBB)
                        return
                    }
                }

                if (shouldShowGroupBB && groupBB.contains(point)) || clickedSelectedBody {
                    redoStack.removeAll()
                    interactionState = .movingSelection(startPoint: point, originalAnnotations: originals)
                    return
                }
            }
        }

        // If in Select mode, check hit test for other annotations or start marquee
        if tool == .select {
            // See if we hit another annotation body (not currently selected)
            for (index, annotation) in annotations.enumerated().reversed() {
                if AnnotationHitTester.hitTest(point: point, annotation: annotation) != .none {
                    if event.clickCount == 2 && annotation.type == .text {
                        SelectionManager.shared.selectedAnnotationIDs = [annotation.id]
                        startTextEditing(existingAnnotation: annotation, at: index)
                        return
                    }
                    if event.modifierFlags.contains(.shift) {
                        if SelectionManager.shared.selectedAnnotationIDs.contains(annotation.id) {
                            SelectionManager.shared.selectedAnnotationIDs.remove(annotation.id)
                        } else {
                            SelectionManager.shared.selectedAnnotationIDs.insert(annotation.id)
                        }
                    } else {
                        SelectionManager.shared.selectedAnnotationIDs = [annotation.id]
                        SelectionManager.shared.wasMarqueeSelected = false
                    }

                    var originals: [UUID: Annotation] = [:]
                    for id in SelectionManager.shared.selectedAnnotationIDs {
                        if let ann = annotations.first(where: { $0.id == id }) {
                            originals[id] = ann
                        }
                    }
                    redoStack.removeAll()
                    interactionState = .movingSelection(startPoint: point, originalAnnotations: originals)
                    needsDisplay = true
                    return
                }
            }

            // Hit nothing in Select mode, clear selection and start marquee
            if !event.modifierFlags.contains(.shift) {
                SelectionManager.shared.clearSelection()
            }
            interactionState = .marqueeSelection(startPoint: point, currentRect: CGRect(origin: point, size: .zero))
            marqueeRect = CGRect(origin: point, size: .zero)
            needsDisplay = true
            return
        }

        // Otherwise, active drawing tool is enabled:
        // Clicking or dragging on an empty canvas area immediately draws a new shape as usual (clearing selection from previous shape)
        redoStack.removeAll()
        SelectionManager.shared.clearSelection()
        interactionState = .drawingNewAnnotation
        var newAnn = Annotation(type: tool, color: color, strokeWidth: width)
        newAnn.fillStyle = SettingsStore.shared.lastSelectedFillStyle
        currentAnnotation = newAnn

        if tool == .laserPen {
            let now = Date()
            annotations.removeAll { $0.type == .laserPen && ($0.expiresAt ?? now) < now }

            for i in 0..<annotations.count {
                if annotations[i].type == .laserPen {
                    annotations[i].expiresAt = nil
                }
            }
        }

        if tool == .arrow || tool == .line {
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

            if current.type == .arrow || current.type == .line {
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
                if let last = current.points.last {
                    if last.distance(to: point) > 1.0 {
                        current.points.append(point)
                    }
                } else {
                    current.points.append(point)
                }
            }

            currentAnnotation = current
            needsDisplay = true

        case .movingSelection(let startPoint, let originalAnnotations):
            let dx = point.x - startPoint.x
            let dy = point.y - startPoint.y

            for (id, originalAnnotation) in originalAnnotations {
                guard let index = annotations.firstIndex(where: { $0.id == id }) else { continue }
                var moved = originalAnnotation
                if moved.type == .arrow || moved.type == .line {
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
            }
            needsDisplay = true

        case .resizingSelection(let handleIndex, let startPoint, let originalAnnotation):
            guard let index = annotations.firstIndex(where: { $0.id == originalAnnotation.id }) else { return }
            let dx = point.x - startPoint.x
            let dy = point.y - startPoint.y

            var resized = originalAnnotation
            if resized.type == .arrow || resized.type == .line {
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

        case .resizingMultipleSelection(let startPoint, let originalAnnotations, let groupBB):
            // Scale relative to the bottom-left corner of the overall bounding box
            let origin = CGPoint(x: groupBB.minX, y: groupBB.minY)
            let initialDistance = startPoint.distance(to: origin)
            let currentDistance = point.distance(to: origin)

            guard initialDistance > 10 else { break }
            let scale = max(0.1, currentDistance / initialDistance)

            for (id, original) in originalAnnotations {
                if let index = annotations.firstIndex(where: { $0.id == id }) {
                    var scaledAnn = original
                    scaledAnn.scale(by: scale, origin: origin)
                    annotations[index] = scaledAnn
                }
            }
            needsDisplay = true

        case .marqueeSelection(let startPoint, _):
            let newRect = CGRect(
                x: min(startPoint.x, point.x),
                y: min(startPoint.y, point.y),
                width: abs(point.x - startPoint.x),
                height: abs(point.y - startPoint.y)
            )
            marqueeRect = newRect
            interactionState = .marqueeSelection(startPoint: startPoint, currentRect: newRect)

            var newlySelected: Set<UUID> = []
            let lenientRect = newRect.insetBy(dx: -2, dy: -2) // Leniency for float precision

            for annotation in annotations {
                let bb = AnnotationHitTester.getBoundingBox(for: annotation)
                let visibleBB = bb.intersection(self.bounds)
                let targetBB = visibleBB.isNull ? bb : visibleBB

                // We use intersects as a fallback if the shape is extremely thin or fully off-screen,
                // but generally we expect the lenientRect to contain the targetBB.
                // Wait, if targetBB is inside lenientRect, contains is true.
                if lenientRect.contains(targetBB) {
                    newlySelected.insert(annotation.id)
                }
            }

            if NSEvent.modifierFlags.contains(.shift) {
                // Keep existing selection and add newly intersected ones
                var union = SelectionManager.shared.selectedAnnotationIDs
                union.formUnion(newlySelected)
                SelectionManager.shared.selectedAnnotationIDs = union
            } else {
                SelectionManager.shared.selectedAnnotationIDs = newlySelected
            }
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        switch interactionState {
        case .idle:
            break

        case .resizingMultipleSelection:
            redoStack.removeAll()
            interactionState = .idle
            needsDisplay = true

        case .marqueeSelection:
            marqueeRect = nil
            interactionState = .idle
            if !SelectionManager.shared.selectedAnnotationIDs.isEmpty {
                SelectionManager.shared.wasMarqueeSelected = true
            }
            needsDisplay = true

        case .drawingNewAnnotation:
            guard var finalAnnotation = currentAnnotation else { return }

            var annotationAdded = false
            if finalAnnotation.type == .arrow || finalAnnotation.type == .line {
                finalAnnotation.arrowEnd = point
                // Only create the arrow if the user dragged a minimum distance
                if let start = finalAnnotation.arrowStart, start.distance(to: point) > 5.0 {
                    finalAnnotation.arrowControlPoint = CGPoint(x: (start.x + point.x) / 2, y: (start.y + point.y) / 2)
                annotations.append(finalAnnotation)
                redoStack.removeAll()
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
                    redoStack.removeAll()
                    annotationAdded = true
                }
            } else {
                if finalAnnotation.points.last != point {
                    finalAnnotation.points.append(point)
                }
                if finalAnnotation.points.count > 1 || finalAnnotation.type == .pen || finalAnnotation.type == .laserPen {
                    if finalAnnotation.type == .laserPen {
                        let expTime = Date().addingTimeInterval(1.5)
                        finalAnnotation.expiresAt = expTime
                        for i in 0..<annotations.count {
                            if annotations[i].type == .laserPen {
                                annotations[i].expiresAt = expTime
                            }
                        }
                    }
                    annotations.append(finalAnnotation)
                    redoStack.removeAll()
                    annotationAdded = true
                }
            }

            if annotationAdded && finalAnnotation.type != .laserPen {
                // Auto-Select on Creation:
                // Immediately select the newly created shape and show its transform handles
                // while keeping the active drawing tool enabled.
                SelectionManager.shared.selectedAnnotationIDs = [finalAnnotation.id]
                SelectionManager.shared.wasMarqueeSelected = false
            } else {
                SelectionManager.shared.clearSelection()
            }

            currentAnnotation = nil

        case .movingSelection, .resizingSelection:
            // End of drag
            // We just update the state
            // If it's too small, maybe delete it, but fine for now
            redoStack.removeAll()
            break
        }

        interactionState = .idle
        needsDisplay = true
    }
    private var activeTextMaxWidth: CGFloat = 300.0

    func updateSelectedFillStyle(_ style: ShapeFillStyle) {
        var updated = false
        for id in SelectionManager.shared.selectedAnnotationIDs {
            if let index = annotations.firstIndex(where: { $0.id == id }) {
                let type = annotations[index].type
                if type == .rectangle || type == .oval || type == .text {
                annotations[index].fillStyle = style
                redoStack.removeAll()
                updated = true
                }
            }
        }
        if updated {
            needsDisplay = true
        }
    }

    private func startTextEditing(at point: CGPoint) {
        if let existing = activeTextView {
            existing.removeFromSuperview()
        }

        editingTextIndex = nil

        // Calculate available width based on click position and window bounds
        let availableWidth = (self.bounds.width - point.x) - 20
        activeTextMaxWidth = max(50.0, availableWidth) // Unlimited up to screen edge

        let fillStyle = SettingsStore.shared.lastSelectedFillStyle
        let inset: CGFloat = fillStyle == .hollow ? 0 : 12
        let initialWidth: CGFloat = 50 + 2 * inset
        let initialHeight: CGFloat = 30 + 2 * inset

        let textView = NSTextView(frame: NSRect(x: point.x - inset, y: point.y + inset - initialHeight, width: initialWidth, height: initialHeight))
        setupTextView(textView, fillStyle: fillStyle, color: SettingsStore.shared.lastSelectedColor)

        self.addSubview(textView)
        self.window?.makeFirstResponder(textView)
        activeTextView = textView
        propertiesHostingView.isHidden = true
    }


    private func startTextEditing(existingAnnotation: Annotation, at index: Int) {
        if let existing = activeTextView {
            existing.removeFromSuperview()
        }

        editingTextIndex = index
        let rect = existingAnnotation.textRect ?? CGRect(x: 0, y: 0, width: 200, height: 30)

        let availableWidth = (self.bounds.width - rect.minX) - 20
        activeTextMaxWidth = max(50.0, availableWidth)

        let fillStyle = existingAnnotation.fillStyle
        let inset: CGFloat = fillStyle == .hollow ? 0 : 12
        let initialWidth = max(rect.width, 50) + 2 * inset
        let initialHeight = max(rect.height, 30) + 2 * inset

        let textView = NSTextView(frame: NSRect(x: rect.minX - inset, y: rect.maxY + inset - initialHeight, width: initialWidth, height: initialHeight))
        setupTextView(textView, fillStyle: fillStyle, color: existingAnnotation.color)
        textView.font = NSFont(name: "Marker Felt", size: existingAnnotation.fontSize) ?? NSFont.systemFont(ofSize: existingAnnotation.fontSize, weight: .bold)
        textView.string = existingAnnotation.text ?? ""

        self.addSubview(textView)
        self.window?.makeFirstResponder(textView)

        // Move cursor to end
        textView.setSelectedRange(NSRange(location: textView.string.count, length: 0))

        activeTextView = textView
        propertiesHostingView.isHidden = true
        self.needsDisplay = true // Redraw to hide the original annotation

        // Ensure proper initial size
        adjustTextViewSize(textView)
    }

    private func setupTextView(_ textView: NSTextView, fillStyle: ShapeFillStyle, color: NSColor) {
        textView.delegate = self

        switch fillStyle {
        case .hollow:
            textView.drawsBackground = false
            textView.textColor = color
            textView.textContainerInset = NSSize(width: 0, height: 0)
        case .translucent:
            textView.drawsBackground = true
            textView.backgroundColor = color.withAlphaComponent(0.2)
            textView.textColor = color
            textView.textContainerInset = NSSize(width: 12, height: 12)
        case .filled:
            textView.drawsBackground = true
            textView.backgroundColor = color
            textView.textColor = color.filledTextColor
            textView.textContainerInset = NSSize(width: 12, height: 12)
        }

        textView.insertionPointColor = textView.textColor ?? color

        textView.wantsLayer = true
        textView.layer?.cornerRadius = 8

        textView.isRichText = false
        let fontSize = Annotation.fontSize(for: SettingsStore.shared.lastSelectedStrokeWidth)
        textView.font = NSFont(name: "Marker Felt", size: fontSize) ?? NSFont.systemFont(ofSize: fontSize, weight: .bold)

        textView.isEditable = true
        textView.isSelectable = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: activeTextMaxWidth + 2 * textView.textContainerInset.width, height: .greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.lineFragmentPadding = 0
    }

    func textDidChange(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView else { return }
        adjustTextViewSize(textView)
    }

    private func adjustTextViewSize(_ textView: NSTextView) {
        guard let layoutManager = textView.layoutManager, let textContainer = textView.textContainer else { return }

        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        let insetX = textView.textContainerInset.width
        let insetY = textView.textContainerInset.height
        let requiredHeight = max(30.0 + 2 * insetY, usedRect.height + 2 * insetY)
        let requiredWidth = max(50.0 + 2 * insetX, min(activeTextMaxWidth + 2 * insetX, usedRect.width + 2 * insetX))
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

            let insetX = textView.textContainerInset.width
            let insetY = textView.textContainerInset.height
            let finalWidth = max(50.0, boundingRect.width)
            let finalHeight = max(30.0, boundingRect.height)

            let finalRect = CGRect(
                x: textView.frame.minX + insetX,
                y: textView.frame.maxY - insetY - finalHeight,
                width: finalWidth,
                height: finalHeight
            )

            if let index = editingTextIndex {
                annotations[index].text = text
                annotations[index].textRect = finalRect
                annotations[index].fontSize = font.pointSize
                redoStack.removeAll()
                SelectionManager.shared.selectedAnnotationIDs = [annotations[index].id]
                SelectionManager.shared.wasMarqueeSelected = false
            } else {
                var annotation = Annotation(type: .text, color: SettingsStore.shared.lastSelectedColor, strokeWidth: SettingsStore.shared.lastSelectedStrokeWidth)
                annotation.text = text
                annotation.textRect = finalRect
                annotation.fontSize = font.pointSize
                annotation.fillStyle = SettingsStore.shared.lastSelectedFillStyle
                annotations.append(annotation)
                redoStack.removeAll()

                SelectionManager.shared.selectedAnnotationIDs = [annotation.id]
                SelectionManager.shared.wasMarqueeSelected = false
            }
        } else {
            // Empty text
            if let index = editingTextIndex {
                annotations.remove(at: index)
                redoStack.removeAll()
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
        switch interactionState {
        case .movingSelection, .resizingSelection, .resizingMultipleSelection:
            return true
        default:
            return false
        }
    }

    private var isResizing: Bool {
        switch interactionState {
        case .resizingSelection, .resizingMultipleSelection:
            return true
        default:
            return false
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // Draw confirmed annotations (skip the one being edited to avoid double-rendering / shadow effect)
        var annotationsToDraw = annotations
        if let editingIndex = editingTextIndex, editingIndex < annotationsToDraw.count {
            annotationsToDraw.remove(at: editingIndex)
        }

        AnnotationRenderer.draw(annotationsToDraw, in: context, isDragging: self.isDragging, isResizing: self.isResizing, hoveredID: hoveredAnnotationID, marqueeRect: marqueeRect)

        // Draw in-progress annotation
        if let current = currentAnnotation {
            AnnotationRenderer.draw([current], in: context, isDragging: self.isDragging, isResizing: self.isResizing)
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

        updatePropertiesPill()
    }

    private func updatePropertiesPill() {
        let selectedIDs = SelectionManager.shared.selectedAnnotationIDs

        if selectedIDs.count != 1 || ToolManager.shared.activeTool != .select {
            propertiesHostingView.isHidden = true
            return
        }

        if SettingsStore.shared.toolbarEdge == .right {
            propertiesTrailingConstraint.constant = -110
        } else {
            propertiesTrailingConstraint.constant = -20
        }

        guard let id = selectedIDs.first,
              let index = annotations.firstIndex(where: { $0.id == id }) else {
            propertiesHostingView.isHidden = true
            return
        }

        let annotation = annotations[index]
        let view = SelectionPropertiesPanel(
            annotationType: annotation.type,
            currentColor: annotation.color,
            currentStrokeWidth: annotation.strokeWidth,
            currentFillStyle: annotation.fillStyle,
            onColorChanged: { [weak self] newColor in
                guard let self = self, let i = self.annotations.firstIndex(where: { $0.id == id }) else { return }
                self.annotations[i].color = newColor
                self.redoStack.removeAll()
                self.needsDisplay = true
            },
            onStrokeWidthChanged: { [weak self] newWidth in
                guard let self = self, let i = self.annotations.firstIndex(where: { $0.id == id }) else { return }
                self.annotations[i].strokeWidth = newWidth
                self.redoStack.removeAll()
                self.needsDisplay = true
            },
            onFillStyleChanged: { [weak self] newStyle in
                guard let self = self, let i = self.annotations.firstIndex(where: { $0.id == id }) else { return }
                self.annotations[i].fillStyle = newStyle
                self.redoStack.removeAll()
                self.needsDisplay = true
            }
        )

        propertiesHostingView.rootView = AnyView(view)
        propertiesHostingView.isHidden = false
    }
}

struct SelectionPropertiesPanel: View {
    let annotationType: ToolType
    let currentColor: NSColor
    let currentStrokeWidth: CGFloat
    let currentFillStyle: ShapeFillStyle

    let onColorChanged: (NSColor) -> Void
    let onStrokeWidthChanged: (CGFloat) -> Void
    let onFillStyleChanged: (ShapeFillStyle) -> Void

    @State private var localStrokeWidth: CGFloat = 0.0

    // Convert NSColor to Color for SwiftUI
    private var swiftUIColor: Color {
        Color(nsColor: currentColor)
    }

    private let availableColors: [NSColor] = [
        NSColor(hex: "#FF3B30") ?? .systemRed,
        NSColor(hex: "#FF9500") ?? .systemOrange,
        NSColor(hex: "#FFCC00") ?? .systemYellow,
        NSColor(hex: "#34C759") ?? .systemGreen,
        NSColor(hex: "#007AFF") ?? .systemBlue,
        NSColor(hex: "#AF52DE") ?? .systemPurple,
        .white,
        .black
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("\(annotationName) Properties")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)

            // Color Picker Grid
            VStack(alignment: .leading, spacing: 8) {
                Text("Color").font(.system(size: 11, weight: .medium)).foregroundColor(.secondary)

                HStack(spacing: 8) {
                    ForEach(availableColors, id: \.self) { color in
                        Circle()
                            .fill(Color(nsColor: color))
                            .frame(width: 18, height: 18)
                            .overlay(
                                Circle()
                                    .stroke(Color.primary.opacity(0.2), lineWidth: currentColor.hexString == color.hexString ? 0 : 1)
                            )
                            .overlay(
                                Circle()
                                    .stroke(Color.accentColor, lineWidth: currentColor.hexString == color.hexString ? 2 : 0)
                                    .padding(-2)
                            )
                            .shadow(color: .black.opacity(0.1), radius: 1, y: 1)
                            .onTapGesture {
                                onColorChanged(color)
                            }
                    }
                }
            }

            // Stroke Width Slider (Not for text)
            if annotationType != .text {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Stroke Width").font(.system(size: 11, weight: .medium)).foregroundColor(.secondary)
                        Spacer()
                        Text("\(Int(localStrokeWidth)) pt").font(.system(size: 11)).foregroundColor(.secondary)
                    }

                    TaperedStrokeSlider(value: $localStrokeWidth, range: 2...20) { isEditing in
                        if !isEditing {
                            onStrokeWidthChanged(localStrokeWidth)
                        }
                    }
                    .onChange(of: localStrokeWidth) { newValue in
                        onStrokeWidthChanged(newValue)
                    }
                }
            }

            // Fill Style Dropdown (if supported)
            if annotationType == .rectangle || annotationType == .oval || annotationType == .text {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Fill Style").font(.system(size: 11, weight: .medium)).foregroundColor(.secondary)
                    Picker("", selection: Binding(
                        get: { currentFillStyle },
                        set: { onFillStyleChanged($0) }
                    )) {
                        Text("Hollow").tag(ShapeFillStyle.hollow)
                        Text("Translucent").tag(ShapeFillStyle.translucent)
                        Text("Filled").tag(ShapeFillStyle.filled)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .labelsHidden()
                }
            }
        }
        .padding(16)
        .frame(width: 260)
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.2), lineWidth: 1))
                .shadow(color: Color.black.opacity(0.25), radius: 15, x: 0, y: 8)
        )
        .contentShape(Rectangle()) // Capture clicks anywhere on the panel
        .onTapGesture {}
        // Ensure SwiftUI handles mouse clicks properly on the Mac transparent window
        .onHover { _ in NSCursor.arrow.push() }
        .onAppear {
            localStrokeWidth = currentStrokeWidth
        }
        .onChange(of: currentStrokeWidth) { newValue in
            localStrokeWidth = newValue
        }
    }

    private var annotationName: String {
        switch annotationType {
        case .arrow: return "Arrow"
        case .line: return "Line"
        case .rectangle: return "Rectangle"
        case .oval: return "Oval"
        case .text: return "Text"
        case .pen: return "Pen"
        case .laserPointer, .laserPen: return "Laser"
        case .select: return "Selection"
        }
    }
}
