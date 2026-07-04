import SwiftUI

struct CustomTooltipModifier: ViewModifier {
    let text: String
    @State private var isHovered = false
    @ObservedObject var settings = SettingsStore.shared

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
                            .offset(
                                x: settings.toolbarEdge == .left ? 64 : (settings.toolbarEdge == .right ? -64 : 0),
                                y: (settings.toolbarEdge == .top || settings.toolbarEdge == .bottom) ? 38 : 0
                            )
                            .transition(.opacity)
                            .zIndex(100)
                            .allowsHitTesting(false)
                    }
                }
                , alignment: .center
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

    @State private var dragOffset = CGSize.zero
    @State private var isDragging: Bool = false
    @State private var wasToolbarBeforeDrag: Bool = false

    private var isVertical: Bool {
        settings.toolbarEdge == .left || settings.toolbarEdge == .right
    }

    @ViewBuilder
    func orientationDivider() -> some View {
        if isVertical {
            Divider().frame(width: 24)
        } else {
            Divider().frame(height: 24)
        }
    }

    var body: some View {
        Group {
            if settings.isToolbarHidden {
                // Compact Pill
                Image(systemName: "pawprint.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.primary)
                    .frame(width: 48, height: 48)
                    .contentShape(Circle())
                    .background(
                        VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                            .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)
                    )
                    .onTapGesture {
                        settings.isToolbarHidden = false
                    }
            } else {
                // Full Toolbar
                let layout = isVertical ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
                let innerLayout = isVertical ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))

                layout {
            // Drag Handle
            DragHandleView(isVertical: isVertical)
                .padding(.horizontal, isVertical ? 0 : 4)
                .padding(.vertical, isVertical ? 4 : 0)

            // Tools
            ForEach(ToolType.allCases, id: \.self) { tool in
                ToolButton(tool: tool, isActive: toolManager.activeTool == tool) {
                    toolManager.activeTool = tool
                }
                .customTooltip("\(tool.name) (\(tool.keyEquivalent))")
            }

            orientationDivider()

            // Colors
            innerLayout {
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

            orientationDivider()

            // Stroke Width
            innerLayout {
                Image(systemName: "lineweight")
                    .foregroundColor(.secondary)
                    .font(.system(size: 14))

                TaperedStrokeSlider(value: Binding(
                    get: { settings.lastSelectedStrokeWidth },
                    set: { settings.lastSelectedStrokeWidth = $0 }
                ), range: 2...20, isVertical: isVertical)
                .frame(width: isVertical ? 20 : 80, height: isVertical ? 80 : 20)
            }
            .customTooltip("Stroke Width")

            orientationDivider()

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

            orientationDivider()

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
                overlayController?.redoLast()
            }) {
                Image(systemName: "arrow.uturn.forward")
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .customTooltip("Redo (Cmd+Shift+Z)")

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
                overlayController?.exportAnnotations()
            }) {
                Image(systemName: "square.and.arrow.up")
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .customTooltip("Export PNG")

            Button(action: {
                overlayController?.showShortcutHelp()
            }) {
                Image(systemName: "questionmark.circle")
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .customTooltip("Shortcuts")

            Button(action: {
                settings.isToolbarHidden = true
            }) {
                Image(systemName: "eye.slash.fill")
                    .foregroundColor(.primary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .customTooltip("Hide Toolbar (H)")

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
        .padding(.horizontal, isVertical ? 12 : 20)
        .padding(.vertical, isVertical ? 20 : 12)
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
                .shadow(color: Color.black.opacity(0.2), radius: 15, x: 0, y: 8)
        )
            } // Close else
        } // Close Group
        .gesture(
            DragGesture(minimumDistance: 5, coordinateSpace: .global)
                .onChanged { _ in
                    if !isDragging {
                        isDragging = true
                        wasToolbarBeforeDrag = !settings.isToolbarHidden

                        if wasToolbarBeforeDrag {
                            settings.isToolbarHidden = true
                            overlayController?.beginToolbarDrag(convertingToPill: true)
                        } else {
                            overlayController?.beginToolbarDrag(convertingToPill: false)
                        }
                    }
                    overlayController?.updateToolbarDrag()
                }
                .onEnded { _ in
                    if wasToolbarBeforeDrag {
                        settings.isToolbarHidden = false
                    }
                    isDragging = false
                    wasToolbarBeforeDrag = false
                    overlayController?.snapToNearestEdge()
                }
        )
        // Ensure SwiftUI handles mouse clicks properly on the Mac transparent window
        .onHover { _ in NSCursor.arrow.push() }
    }
}

struct DragHandleView: View {
    var isVertical: Bool

    var body: some View {
        HStack(spacing: 4) {
            VStack(spacing: 4) {
                Circle().frame(width: 3, height: 3)
                Circle().frame(width: 3, height: 3)
                Circle().frame(width: 3, height: 3)
            }
            VStack(spacing: 4) {
                Circle().frame(width: 3, height: 3)
                Circle().frame(width: 3, height: 3)
                Circle().frame(width: 3, height: 3)
            }
        }
        .foregroundColor(.secondary.opacity(0.6))
        .rotationEffect(.degrees(isVertical ? 90 : 0))
        .frame(width: isVertical ? 24 : 14, height: isVertical ? 14 : 24)
        .contentShape(Rectangle()) // Make it easily grabbable
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
    var range: ClosedRange<CGFloat> = 2...20
    var activeColor: Color = .accentColor
    var isVertical: Bool = false
    var onEditingChanged: ((Bool) -> Void)? = nil

    @State private var isDragging: Bool = false

    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            let h = geometry.size.height
            let minThickness: CGFloat = 2.0

            if isVertical {
                let maxThickness: CGFloat = w * 0.8
                let progress = max(0, min(1, (value - range.lowerBound) / (range.upperBound - range.lowerBound)))
                let activeHeight = h * progress
                let activeThickness = minThickness + (maxThickness - minThickness) * progress

                ZStack(alignment: .top) {
                    // Background Track
                    Path { path in
                        path.move(to: CGPoint(x: w/2 - minThickness/2, y: 0))
                        path.addLine(to: CGPoint(x: w/2 - maxThickness/2, y: h))
                        path.addArc(center: CGPoint(x: w/2, y: h), radius: maxThickness/2, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: true)
                        path.addLine(to: CGPoint(x: w/2 + minThickness/2, y: 0))
                        path.addArc(center: CGPoint(x: w/2, y: 0), radius: minThickness/2, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: true)
                        path.closeSubpath()
                    }
                    .fill(Color.primary.opacity(0.4))

                    // Active Track
                    Path { path in
                        path.move(to: CGPoint(x: w/2 - minThickness/2, y: 0))
                        path.addLine(to: CGPoint(x: w/2 - activeThickness/2, y: activeHeight))
                        path.addArc(center: CGPoint(x: w/2, y: activeHeight), radius: activeThickness/2, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: true)
                        path.addLine(to: CGPoint(x: w/2 + minThickness/2, y: 0))
                        path.addArc(center: CGPoint(x: w/2, y: 0), radius: minThickness/2, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: true)
                        path.closeSubpath()
                    }
                    .fill(activeColor)

                    // Thumb
                    Circle()
                        .fill(Color.white)
                        .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 1)
                        .overlay(Circle().stroke(Color.gray.opacity(0.2), lineWidth: 0.5))
                        .overlay(
                            Text(String(format: "%.0f", value))
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color(nsColor: .windowBackgroundColor)).shadow(radius: 2))
                                .fixedSize()
                                .offset(x: -30)
                                .opacity(isDragging ? 1 : 0)
                                .animation(.easeInOut(duration: 0.1), value: isDragging)
                        )
                        .frame(width: w, height: w)
                        .offset(y: activeHeight - w/2)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { gesture in
                                    if !isDragging {
                                        isDragging = true
                                        onEditingChanged?(true)
                                    }
                                    let p = gesture.location.y / h
                                    let clamped = max(0, min(1, p))
                                    value = range.lowerBound + clamped * (range.upperBound - range.lowerBound)
                                }
                                .onEnded { _ in
                                    isDragging = false
                                    onEditingChanged?(false)
                                }
                        )
                }
            } else {
                let maxThickness: CGFloat = h * 0.8
                let progress = max(0, min(1, (value - range.lowerBound) / (range.upperBound - range.lowerBound)))
                let activeWidth = w * progress
                let activeThickness = minThickness + (maxThickness - minThickness) * progress

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
                        .overlay(
                            Text(String(format: "%.0f", value))
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color(nsColor: .windowBackgroundColor)).shadow(radius: 2))
                                .fixedSize()
                                .offset(y: -30)
                                .opacity(isDragging ? 1 : 0)
                                .animation(.easeInOut(duration: 0.1), value: isDragging)
                        )
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
        }
    }
}
