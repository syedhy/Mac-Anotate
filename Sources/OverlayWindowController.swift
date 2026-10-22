import Cocoa
import SwiftUI

class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool {
        return true
    }
}

class OverlayWindowController: NSWindowController, NSWindowDelegate {

    private var canvasView: AnnotationCanvasView!
    private var toolbarHostingView: NSHostingView<FloatingToolbarView>!

    // Constraints for free dragging
    private var toolbarLeftConstraint: NSLayoutConstraint!
    private var toolbarTopConstraint: NSLayoutConstraint!

    // Constraints for snapped edges
    private var snapTopConstraint: NSLayoutConstraint!
    private var snapBottomConstraint: NSLayoutConstraint!
    private var snapLeadingConstraint: NSLayoutConstraint!
    private var snapTrailingConstraint: NSLayoutConstraint!
    private var snapCenterXConstraint: NSLayoutConstraint!
    private var snapCenterYConstraint: NSLayoutConstraint!

    var isOverlayActive: Bool = false

    init() {
        let overlayFrame = OverlayWindowController.overlayFrame(for: NSScreen.main)

        let overlayWindow = OverlayWindow(
            contentRect: overlayFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        overlayWindow.level = .screenSaver
        overlayWindow.backgroundColor = .clear
        overlayWindow.isOpaque = false
        overlayWindow.hasShadow = false
        overlayWindow.ignoresMouseEvents = true
        overlayWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        super.init(window: overlayWindow)

        overlayWindow.delegate = self
        setupViews()
        overlayWindow.orderOut(nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        guard let window = self.window else { return }

        let contentView = NSView(frame: window.frame)
        contentView.wantsLayer = true
        window.contentView = contentView

        // Setup Canvas
        canvasView = AnnotationCanvasView(frame: contentView.bounds)
        canvasView.autoresizingMask = [.width, .height]
        contentView.addSubview(canvasView)

        // Setup Toolbar
        let toolbarView = FloatingToolbarView(overlayController: self, toolManager: ToolManager.shared)
        toolbarHostingView = NSHostingView(rootView: toolbarView)
        toolbarHostingView.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(toolbarHostingView)

        // Setup snap constraints
        snapTopConstraint = toolbarHostingView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 40)
        snapBottomConstraint = toolbarHostingView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -40)
        snapLeadingConstraint = toolbarHostingView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 40)
        snapTrailingConstraint = toolbarHostingView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -40)
        snapCenterXConstraint = toolbarHostingView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor)
        snapCenterYConstraint = toolbarHostingView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)

        // Setup drag constraints (active during drag)
        toolbarLeftConstraint = toolbarHostingView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 0)
        toolbarTopConstraint = toolbarHostingView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 40)

        // Start by applying the saved edge state
        applyEdgeConstraints(edge: SettingsStore.shared.toolbarEdge, animate: false)

        toolbarHostingView.isHidden = true

        // Setup Clear Prompt (centered)
        let clearPrompt = ClearPromptView(
            onClear: { [weak self] in
                self?.clearCanvas()
                self?.hideClearPrompt()
            },
            onCancel: { [weak self] in
                self?.hideClearPrompt()
            }
        )
        clearPromptHostingView = NSHostingView(rootView: clearPrompt)
        clearPromptHostingView.translatesAutoresizingMaskIntoConstraints = false

        let shortcutHelp = ShortcutHelpView(
            onDismiss: { [weak self] in
                self?.hideShortcutHelp()
            }
        )
        shortcutHelpHostingView = NSHostingView(rootView: shortcutHelp)
        shortcutHelpHostingView.translatesAutoresizingMaskIntoConstraints = false
    }

    private var clearPromptHostingView: NSHostingView<ClearPromptView>!
    private var shortcutHelpHostingView: NSHostingView<ShortcutHelpView>!

    private static func overlayFrame(for screen: NSScreen?) -> NSRect {
        let screen = screen ?? NSScreen.main
        let screenFrame = screen?.frame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let visibleFrame = screen?.visibleFrame ?? screenFrame
        let menuBarHeight = max(0, screenFrame.maxY - visibleFrame.maxY)
        var overlayFrame = screenFrame
        overlayFrame.size.height -= menuBarHeight
        return overlayFrame
    }

    private static func screenContainingMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main
    }

    private func moveOverlayToCursorScreen() {
        guard let window = self.window else { return }
        let targetFrame = Self.overlayFrame(for: Self.screenContainingMouse())
        window.setFrame(targetFrame, display: true)
        window.contentView?.frame = NSRect(origin: .zero, size: targetFrame.size)
    }

    func showClearPrompt() {
        guard let contentView = window?.contentView else { return }
        if clearPromptHostingView.superview == nil {
            contentView.addSubview(clearPromptHostingView)
            NSLayoutConstraint.activate([
                clearPromptHostingView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
                clearPromptHostingView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
            ])
        }
        clearPromptHostingView.isHidden = false
    }

    func hideClearPrompt() {
        clearPromptHostingView.isHidden = true
        clearPromptHostingView.removeFromSuperview()
        canvasView.window?.makeFirstResponder(canvasView)
    }

    func showShortcutHelp(markAsSeen: Bool = false) {
        guard let contentView = window?.contentView else { return }
        if shortcutHelpHostingView.superview == nil {
            contentView.addSubview(shortcutHelpHostingView)
            NSLayoutConstraint.activate([
                shortcutHelpHostingView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
                shortcutHelpHostingView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
            ])
        }
        shortcutHelpHostingView.isHidden = false
        if markAsSeen {
            SettingsStore.shared.hasShownShortcutHelp = true
        }
    }

    func hideShortcutHelp() {
        shortcutHelpHostingView.isHidden = true
        shortcutHelpHostingView.removeFromSuperview()
        canvasView.window?.makeFirstResponder(canvasView)
    }

    func toggleOverlay() {
        isOverlayActive.toggle()

        guard let window = self.window else { return }

        if isOverlayActive {
            moveOverlayToCursorScreen()
            window.ignoresMouseEvents = false
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            toolbarHostingView.isHidden = false
            window.makeFirstResponder(canvasView)

            if !SettingsStore.shared.hasShownShortcutHelp {
                showShortcutHelp(markAsSeen: true)
            }
        } else {
            window.ignoresMouseEvents = true
            toolbarHostingView.isHidden = true
            hideShortcutHelp()
            hideClearPrompt()

            // Clear annotations if setting is on
            if SettingsStore.shared.clearOnExit {
                clearCanvas()
            }

            window.orderOut(nil)

            // Deactivate and return focus to previous app
            NSApp.hide(nil)
        }
    }

    func hideOverlayForSettings() {
        guard let window = self.window else { return }
        isOverlayActive = false
        window.ignoresMouseEvents = true
        toolbarHostingView.isHidden = true
        hideShortcutHelp()
        hideClearPrompt()
        window.orderOut(nil)
    }

    func clearCanvas() {
        canvasView.clear()
    }

    func undoLast() {
        canvasView.undo()
    }

    func redoLast() {
        canvasView.redo()
    }

    func exportAnnotations() {
        guard PermissionManager.shared.hasScreenRecordingPermission else {
            requestScreenRecordingPermissionForExport()
            return
        }

        canvasView.exportAnnotations()
    }

    private func requestScreenRecordingPermissionForExport() {
        let wasOverlayActive = isOverlayActive
        suspendOverlayForSystemPrompt()

        DispatchQueue.main.async {
            let granted = PermissionManager.shared.requestScreenRecordingPermissionIfNeeded()

            if granted {
                if wasOverlayActive {
                    self.resumeOverlayAfterSystemPrompt()
                }
                self.canvasView.exportAnnotations()
            } else {
                self.showScreenRecordingPermissionAlert(resumeOverlay: wasOverlayActive)
            }
        }
    }

    private func showScreenRecordingPermissionAlert(resumeOverlay: Bool) {
        let alert = NSAlert()
        alert.messageText = "Screen Recording Permission Needed"
        alert.informativeText = "Export PNG needs Screen Recording permission to capture the screen behind your annotations."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Cancel")

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            isOverlayActive = false
            PermissionManager.shared.openScreenRecordingSettings()
        } else if resumeOverlay {
            resumeOverlayAfterSystemPrompt()
        }
    }

    private func suspendOverlayForSystemPrompt() {
        guard isOverlayActive, let window = self.window else { return }
        window.ignoresMouseEvents = true
        toolbarHostingView.isHidden = true
        window.orderOut(nil)
        NSApp.hide(nil)
    }

    private func resumeOverlayAfterSystemPrompt() {
        guard isOverlayActive, let window = self.window else { return }
        moveOverlayToCursorScreen()
        window.ignoresMouseEvents = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        toolbarHostingView.isHidden = false
        window.makeFirstResponder(canvasView)
    }

    func updateSelectedFillStyle(_ style: ShapeFillStyle) {
        canvasView.updateSelectedFillStyle(style)
    }

    @objc func colorPanelColorDidChange(_ sender: NSColorPanel) {
        SettingsStore.shared.lastSelectedColor = sender.color
    }

    private var dragMouseOffset: CGSize = .zero
    private var isDraggingToPill: Bool = false

    func beginToolbarDrag(convertingToPill: Bool) {
        guard let window = self.window, let contentView = window.contentView else { return }
        let mouseLoc = window.mouseLocationOutsideOfEventStream

        isDraggingToPill = convertingToPill

        if !convertingToPill {
            // Keep the relative grab position if not changing size
            let mouseX = mouseLoc.x
            let mouseY = contentView.bounds.height - mouseLoc.y
            let center = CGPoint(x: toolbarHostingView.frame.midX,
                                 y: contentView.bounds.height - toolbarHostingView.frame.midY)
            dragMouseOffset = CGSize(width: center.x - mouseX, height: center.y - mouseY)
        } else {
            // Center the pill exactly on the mouse cursor
            dragMouseOffset = .zero
        }

        if !toolbarLeftConstraint.isActive {
            let currentFrame = toolbarHostingView.frame
            toolbarLeftConstraint.constant = currentFrame.minX
            toolbarTopConstraint.constant = contentView.bounds.height - currentFrame.maxY

            NSLayoutConstraint.deactivate([
                snapTopConstraint, snapBottomConstraint, snapLeadingConstraint, snapTrailingConstraint,
                snapCenterXConstraint, snapCenterYConstraint
            ])
            NSLayoutConstraint.activate([toolbarLeftConstraint, toolbarTopConstraint])
        }
    }

    func updateToolbarDrag() {
        guard let window = self.window, let contentView = window.contentView else { return }

        let mouseLoc = window.mouseLocationOutsideOfEventStream
        let mouseX = mouseLoc.x
        let mouseY = contentView.bounds.height - mouseLoc.y
        let currentSize = toolbarHostingView.frame.size

        toolbarLeftConstraint.constant = mouseX + dragMouseOffset.width - currentSize.width / 2
        toolbarTopConstraint.constant = mouseY + dragMouseOffset.height - currentSize.height / 2

        // Simple bounds check based on current frame size
        guard let window = self.window, let contentView = window.contentView else { return }

        let maxX = contentView.bounds.width - currentSize.width / 2
        let minX = -currentSize.width / 2

        if toolbarLeftConstraint.constant > maxX { toolbarLeftConstraint.constant = maxX }
        if toolbarLeftConstraint.constant < minX { toolbarLeftConstraint.constant = minX }

        let maxY = contentView.bounds.height - currentSize.height / 2
        let minY = -currentSize.height / 2

        if toolbarTopConstraint.constant > maxY { toolbarTopConstraint.constant = maxY }
        if toolbarTopConstraint.constant < minY { toolbarTopConstraint.constant = minY }
    }

    func snapToNearestEdge() {
        guard let window = self.window, let contentView = window.contentView else { return }
        let bounds = contentView.bounds
        let frame = toolbarHostingView.frame

        let centerX = frame.midX
        let centerY = frame.midY

        // Distance to edges from center
        let distTop = bounds.height - centerY
        let distBottom = centerY
        let distLeft = centerX
        let distRight = bounds.width - centerX

        let minEdge = min(distTop, distBottom, distLeft, distRight)

        var targetEdge: ToolbarEdge = .top
        if minEdge == distTop { targetEdge = .top }
        else if minEdge == distBottom { targetEdge = .bottom }
        else if minEdge == distLeft { targetEdge = .left }
        else { targetEdge = .right }

        applyEdgeConstraints(edge: targetEdge, animate: true)
    }

    private func applyEdgeConstraints(edge: ToolbarEdge, animate: Bool) {
        SettingsStore.shared.toolbarEdge = edge

        NSLayoutConstraint.deactivate([
            toolbarLeftConstraint, toolbarTopConstraint,
            snapTopConstraint, snapBottomConstraint, snapLeadingConstraint, snapTrailingConstraint,
            snapCenterXConstraint, snapCenterYConstraint
        ])

        var toActivate: [NSLayoutConstraint] = []

        switch edge {
        case .top:
            toActivate = [snapTopConstraint, snapCenterXConstraint]
        case .bottom:
            toActivate = [snapBottomConstraint, snapCenterXConstraint]
        case .left:
            toActivate = [snapLeadingConstraint, snapCenterYConstraint]
        case .right:
            toActivate = [snapTrailingConstraint, snapCenterYConstraint]
        }

        NSLayoutConstraint.activate(toActivate)

        if animate {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.3
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window?.contentView?.animator().layoutSubtreeIfNeeded()
            })
        }
    }
}

struct ClearPromptView: View {
    let onClear: () -> Void
    let onCancel: () -> Void

    @State private var focusedButton: Int = 1 // 0 for Clear, 1 for Cancel
    @State private var eventMonitor: Any?

    var body: some View {
        VStack(spacing: 16) {
            Text("Clear all annotations?")
                .font(.headline)
                .foregroundColor(.primary)

            Text("This action cannot be undone.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            HStack(spacing: 12) {
                Button(action: onCancel) {
                    Text("Cancel")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(BorderedButtonStyle())
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.accentColor, lineWidth: focusedButton == 1 ? 2 : 0)
                )

                Button(action: onClear) {
                    Text("Clear")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(BorderedProminentButtonStyle())
                .tint(.red)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.accentColor, lineWidth: focusedButton == 0 ? 2 : 0)
                )
            }
            .padding(.top, 8)
        }
        .padding(24)
        .frame(width: 320)
        .background(
            VisualEffectView(material: .popover, blendingMode: .behindWindow)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: Color.black.opacity(0.15), radius: 20, x: 0, y: 10)
        )
        .onAppear {
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.keyCode == 123 || event.keyCode == 124 { // Left or Right arrow
                    focusedButton = (focusedButton == 0) ? 1 : 0
                    return nil
                } else if event.keyCode == 36 { // Enter
                    if focusedButton == 0 {
                        onClear()
                    } else {
                        onCancel()
                    }
                    return nil
                } else if event.keyCode == 53 { // Escape
                    onCancel()
                    return nil
                }
                return event
            }
        }
        .onDisappear {
            if let monitor = eventMonitor {
                NSEvent.removeMonitor(monitor)
                eventMonitor = nil
            }
        }
    }
}

struct ShortcutHelpView: View {
    let onDismiss: () -> Void

    private let shortcutSections: [(String, [(String, String)])] = [
        ("Tools", [
            ("V / S", "Select"),
            ("P", "Pen"),
            ("L", "Line"),
            ("A", "Arrow"),
            ("R", "Rectangle"),
            ("O", "Oval"),
            ("T", "Text"),
            ("B / W", "Laser (Beam/Wand)")
        ]),
        ("Actions", [
            ("Cmd+Z", "Undo"),
            ("Cmd+Shift+Z", "Redo"),
            ("Cmd+D", "Duplicate"),
            ("Cmd+A", "Select all"),
            ("F", "Cycle fill style"),
            ("C", "Clear"),
            ("H", "Hide toolbar"),
            ("Esc", "Close overlay")
        ])
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Quick shortcuts")
                        .font(.system(size: 18, weight: .semibold))
                    Text("Shown once. Hover toolbar buttons for hints later.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                }
                .buttonStyle(PlainButtonStyle())
                .foregroundColor(.secondary)
            }

            HStack(alignment: .top, spacing: 18) {
                ForEach(shortcutSections, id: \.0) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(section.0)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)

                        ForEach(section.1, id: \.0) { shortcut in
                            HStack(spacing: 8) {
                                Text(shortcut.0)
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                    .frame(width: 92, alignment: .center)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(Color.secondary.opacity(0.16)))

                                Text(shortcut.1)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)

                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .frame(width: 190, alignment: .leading)
                }
            }

            HStack {
                Label("Export PNG from the toolbar", systemImage: "square.and.arrow.up")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                Button("Got it", action: onDismiss)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 440)
        .background(
            VisualEffectView(material: .popover, blendingMode: .behindWindow)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.18), lineWidth: 1))
                .shadow(color: Color.black.opacity(0.18), radius: 24, x: 0, y: 14)
        )
    }
}
