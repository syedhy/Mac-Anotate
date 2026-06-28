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
        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let visibleFrame = NSScreen.main?.visibleFrame ?? screenFrame
        
        // Exclude the menu bar (which is at the top)
        let menuBarHeight = screenFrame.maxY - visibleFrame.maxY
        var overlayFrame = screenFrame
        overlayFrame.size.height -= menuBarHeight
        
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
    }
    
    private var clearPromptHostingView: NSHostingView<ClearPromptView>!
    
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
    
    func toggleOverlay() {
        isOverlayActive.toggle()
        
        guard let window = self.window else { return }
        
        if isOverlayActive {
            window.ignoresMouseEvents = false
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            toolbarHostingView.isHidden = false
            window.makeFirstResponder(canvasView)
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
