import SwiftUI

struct FloatingToolbarView: View {
    weak var overlayController: OverlayWindowController?
    @ObservedObject var toolManager: ToolManager
    @ObservedObject var settings = SettingsStore.shared
    
    let colors: [NSColor] = [
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
        HStack(spacing: 12) {
            // Tools
            ForEach(ToolType.allCases, id: \.self) { tool in
                ToolButton(tool: tool, isActive: toolManager.activeTool == tool) {
                    toolManager.activeTool = tool
                }
            }
            
            Divider()
                .frame(height: 24)
            
            // Colors
            HStack(spacing: 8) {
                ForEach(colors, id: \.self) { color in
                    Circle()
                        .fill(Color(nsColor: color))
                        .frame(width: 20, height: 20)
                        .overlay(
                            Circle()
                                .stroke(Color.white, lineWidth: settings.lastSelectedColor.hexString == color.hexString ? 2 : 0)
                        )
                        .shadow(radius: 1)
                        .onTapGesture {
                            settings.lastSelectedColor = color
                        }
                }
            }
            
            Divider()
                .frame(height: 24)
            
            // Stroke Width
            Menu {
                Button("Thin (4pt)") { settings.lastSelectedStrokeWidth = 4 }
                Button("Medium (8pt)") { settings.lastSelectedStrokeWidth = 8 }
                Button("Thick (12pt)") { settings.lastSelectedStrokeWidth = 12 }
                Button("Extra Thick (20pt)") { settings.lastSelectedStrokeWidth = 20 }
            } label: {
                Image(systemName: "lineweight")
            }
            .frame(width: 40)
            
            Divider()
                .frame(height: 24)
            
            // Actions
            Button(action: {
                overlayController?.undoLast()
            }) {
                Image(systemName: "arrow.uturn.backward")
            }
            .buttonStyle(PlainButtonStyle())
            .help("Undo (Cmd+Z)")
            
            Button(action: {
                overlayController?.clearCanvas()
            }) {
                Image(systemName: "trash")
            }
            .buttonStyle(PlainButtonStyle())
            .help("Clear (C)")
            
            Button(action: {
                overlayController?.toggleOverlay()
            }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.gray)
            }
            .buttonStyle(PlainButtonStyle())
            .help("Close (Esc)")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
                .shadow(color: Color.black.opacity(0.2), radius: 15, x: 0, y: 8)
        )
        // Ensure SwiftUI handles mouse clicks properly on the Mac transparent window
        .onHover { _ in NSCursor.arrow.push() }
    }
}

// Helper to use NSVisualEffectView in SwiftUI
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

struct ToolButton: View {
    let tool: ToolType
    let isActive: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: tool.iconName)
                .font(.system(size: 16, weight: isActive ? .bold : .regular))
                .foregroundColor(isActive ? .white : .primary)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(isActive ? Color.accentColor : Color.clear)
                )
        }
        .buttonStyle(PlainButtonStyle())
        .help("\(tool.rawValue.capitalized) (\(tool.keyEquivalent.uppercased()))")
    }
}
