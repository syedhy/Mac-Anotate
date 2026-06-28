import SwiftUI

struct CustomTooltipModifier: ViewModifier {
    let text: String
    @State private var isHovered = false
    
    func body(content: Content) -> some View {
        content
            .onHover { hovered in
                withAnimation(.easeInOut(duration: 0.1)) {
                    isHovered = hovered
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)) { _ in
                withAnimation(.easeInOut(duration: 0.1)) {
                    isHovered = false
                }
            }
            .overlay(
                Group {
                    if isHovered {
                        Text(text)
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                VisualEffectView(material: .popover, blendingMode: .withinWindow)
                            )
                            .foregroundColor(.primary)
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                            .fixedSize()
                            .offset(y: 38)
                            .transition(.opacity)
                            .zIndex(100)
                    }
                }
                , alignment: .bottom
            )
    }
}

extension View {
    func customTooltip(_ text: String) -> some View {
        self.modifier(CustomTooltipModifier(text: text))
    }
}

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
                .customTooltip("\(tool.name) (\(tool.keyEquivalent))")
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
                                .stroke(Color.white, lineWidth: settings.lastSelectedColor == color ? 2 : 0)
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
            HStack(spacing: 8) {
                Image(systemName: "lineweight")
                    .foregroundColor(.secondary)
                    .font(.system(size: 14))
                
                TaperedStrokeSlider(value: Binding(
                    get: { settings.lastSelectedStrokeWidth },
                    set: { settings.lastSelectedStrokeWidth = $0 }
                ), range: 1...50)
                .frame(width: 80)
            }
            .customTooltip("Stroke Width")
            
            Divider()
                .frame(height: 24)
                
            // Fill Style
            Menu {
                Button(action: { 
                    settings.lastSelectedFillStyle = .hollow
                    overlayController?.updateSelectedFillStyle(.hollow)
                }) {
                    HStack {
                        Text("Hollow")
                        if settings.lastSelectedFillStyle == .hollow {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                Button(action: { 
                    settings.lastSelectedFillStyle = .translucent
                    overlayController?.updateSelectedFillStyle(.translucent)
                }) {
                    HStack {
                        Text("Translucent")
                        if settings.lastSelectedFillStyle == .translucent {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                Button(action: { 
                    settings.lastSelectedFillStyle = .filled
                    overlayController?.updateSelectedFillStyle(.filled)
                }) {
                    HStack {
                        Text("Filled")
                        if settings.lastSelectedFillStyle == .filled {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            } label: {
                Image(systemName: "square.fill.on.square")
            }
            .frame(width: 40)
            .customTooltip("Fill Style")
            
            Divider()
                .frame(height: 24)
            
            // Actions
            Button(action: {
                overlayController?.undoLast()
            }) {
                Image(systemName: "arrow.uturn.backward")
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .customTooltip("Undo (Cmd+Z)")
            
            Button(action: {
                overlayController?.clearCanvas()
            }) {
                Image(systemName: "trash")
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .customTooltip("Clear (C)")
            
            Button(action: {
                overlayController?.toggleOverlay()
            }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.primary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .customTooltip("Close (Esc)")
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
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct TaperedStrokeSlider: View {
    @Binding var value: CGFloat
    var range: ClosedRange<CGFloat> = 1...50
    var activeColor: Color = .accentColor
    var onEditingChanged: ((Bool) -> Void)? = nil
    
    @State private var isDragging: Bool = false
    
    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            let h = geometry.size.height
            let minThickness: CGFloat = 2.0
            let maxThickness: CGFloat = h * 0.8
            
            ZStack(alignment: .leading) {
                // Background Track
                Path { path in
                    path.move(to: CGPoint(x: 0, y: h/2 - minThickness/2))
                    path.addLine(to: CGPoint(x: w, y: h/2 - maxThickness/2))
                    path.addArc(center: CGPoint(x: w, y: h/2), radius: maxThickness/2, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false)
                    path.addLine(to: CGPoint(x: 0, y: h/2 + minThickness/2))
                    path.addArc(center: CGPoint(x: 0, y: h/2), radius: minThickness/2, startAngle: .degrees(90), endAngle: .degrees(-90), clockwise: false)
                    path.closeSubpath()
                }
                .fill(Color.primary.opacity(0.4))
                
                // Active Track
                let progress = max(0, min(1, (value - range.lowerBound) / (range.upperBound - range.lowerBound)))
                let activeWidth = w * progress
                let activeThickness = minThickness + (maxThickness - minThickness) * progress
                
                Path { path in
                    path.move(to: CGPoint(x: 0, y: h/2 - minThickness/2))
                    path.addLine(to: CGPoint(x: activeWidth, y: h/2 - activeThickness/2))
                    path.addArc(center: CGPoint(x: activeWidth, y: h/2), radius: activeThickness/2, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false)
                    path.addLine(to: CGPoint(x: 0, y: h/2 + minThickness/2))
                    path.addArc(center: CGPoint(x: 0, y: h/2), radius: minThickness/2, startAngle: .degrees(90), endAngle: .degrees(-90), clockwise: false)
                    path.closeSubpath()
                }
                .fill(activeColor)
                
                // Thumb
                Circle()
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 1)
                    .overlay(Circle().stroke(Color.gray.opacity(0.2), lineWidth: 0.5))
                    .frame(width: h, height: h)
                    .offset(x: activeWidth - h/2)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { gesture in
                                if !isDragging {
                                    isDragging = true
                                    onEditingChanged?(true)
                                }
                                let p = gesture.location.x / w
                                let clamped = max(0, min(1, p))
                                value = range.lowerBound + clamped * (range.upperBound - range.lowerBound)
                            }
                            .onEnded { _ in
                                isDragging = false
                                onEditingChanged?(false)
                            }
                    )
            }
        }
        .frame(height: 16)
    }
}
