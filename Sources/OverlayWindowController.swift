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
    
    var isOverlayActive: Bool = false
    
    init() {
        let screenRect = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        
        let overlayWindow = OverlayWindow(
            contentRect: screenRect,
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
        
        NSLayoutConstraint.activate([
            toolbarHostingView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 40),
            toolbarHostingView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor)
        ])
        
        toolbarHostingView.isHidden = true
    }
    
    func toggleOverlay() {
        isOverlayActive.toggle()
        
        guard let window = self.window else { return }
        
        if isOverlayActive {
            window.ignoresMouseEvents = false
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            toolbarHostingView.isHidden = false
            canvasView.becomeFirstResponder()
        } else {
            window.ignoresMouseEvents = true
            toolbarHostingView.isHidden = true
            
            // Clear annotations if setting is on
            if SettingsStore.shared.clearOnExit {
                clearCanvas()
            }
            
            // Deactivate and return focus to previous app
            NSApp.hide(nil)
        }
    }
    
    func clearCanvas() {
        canvasView.clear()
    }
    
    func undoLast() {
        canvasView.undo()
    }
}
