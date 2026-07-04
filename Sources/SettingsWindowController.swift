import SwiftUI
import Cocoa
import Carbon

class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()
    
    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Mac Annotate Settings"
        window.titlebarAppearsTransparent = true
        window.center()
        window.setFrameAutosaveName("SettingsWindow")
        
        let hostingView = NSHostingView(rootView: SettingsView().frame(minWidth: 480, minHeight: 600))
        window.contentView = hostingView
        
        super.init(window: window)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct SettingsView: View {
    @ObservedObject var settings = SettingsStore.shared
    
    let availableColors: [NSColor] = [
        NSColor(hex: "#FF3B30") ?? .systemRed,
        NSColor(hex: "#FF9500") ?? .systemOrange,
        NSColor(hex: "#FFCC00") ?? .systemYellow,
        NSColor(hex: "#34C759") ?? .systemGreen,
        NSColor(hex: "#007AFF") ?? .systemBlue,
        NSColor(hex: "#AF52DE") ?? .systemPurple,
        .white,
        .black
    ]
    
    let strokeWidths: [(name: String, width: CGFloat)] = [
        ("Thin", 4),
        ("Medium", 8),
        ("Thick", 12),
        ("Extra Thick", 20)
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Preferences")
                    .font(.title)
                    .fontWeight(.bold)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, 16)
            
            Divider()
            
            ScrollView {
                VStack(spacing: 20) {
                    
                    // General Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("General")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        VStack {
                            Toggle("Clear annotations on exit", isOn: $settings.clearOnExit)
                                .toggleStyle(.switch)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(16)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.1), lineWidth: 1))
                    }
                    
                    // Appearance Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Appearance")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        VStack(alignment: .leading, spacing: 20) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Default Color:")
                                HStack(spacing: 12) {
                                    ForEach(availableColors, id: \.self) { color in
                                        Circle()
                                            .fill(Color(nsColor: color))
                                            .frame(width: 24, height: 24)
                                            .overlay(
                                                Circle()
                                                    .stroke(Color.primary, lineWidth: settings.lastSelectedColor.hexString == color.hexString ? 3 : 0)
                                            )
                                            .shadow(radius: 1)
                                            .onTapGesture {
                                                settings.lastSelectedColor = color
                                            }
                                    }
                                }
                            }
                            
                            Divider()
                            
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("Default Stroke Width:")
                                    Spacer()
                                    Text(String(format: "%.0f", settings.lastSelectedStrokeWidth))
                                        .font(.system(size: 14, weight: .bold, design: .rounded))
                                        .foregroundColor(.secondary)
                                }
                                
                                TaperedStrokeSlider(value: $settings.lastSelectedStrokeWidth, isVertical: false)
                                    .frame(height: 32)
                                    .padding(.horizontal, 10)
                            }
                        }
                        .padding(16)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.1), lineWidth: 1))
                    }
                    
                    // Shortcuts Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Shortcuts")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Text("Global Activation:")
                                Spacer()
                                ShortcutRecorderView(
                                    keyCode: $settings.globalShortcutKeyCode,
                                    modifiers: $settings.globalShortcutModifiers
                                ) {
                                    HotkeyManager.shared.registerGlobalHotkey()
                                }
                            }
                            
                            Divider()
                            
                            Text("Tool Shortcuts (when active):")
                            
                            LazyVGrid(columns: [GridItem(.fixed(120)), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                                ShortcutRow(key: "P", action: "Pen")
                                ShortcutRow(key: "A", action: "Arrow")
                                ShortcutRow(key: "R", action: "Rectangle")
                                ShortcutRow(key: "O", action: "Oval")
                                ShortcutRow(key: "T", action: "Text")
                                ShortcutRow(key: "L", action: "Laser")
                                ShortcutRow(key: "C", action: "Clear All")
                            }
                        }
                        .padding(16)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.1), lineWidth: 1))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            
            Divider()
            
            HStack {
                Spacer()
                Button("Done") {
                    SettingsWindowController.shared.close()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct ShortcutRecorderView: View {
    @Binding var keyCode: UInt32
    @Binding var modifiers: UInt32
    var onShortcutChanged: () -> Void
    
    @State private var isRecording = false
    
    var body: some View {
        Button(action: {
            isRecording.toggle()
        }) {
            Text(isRecording ? "Recording..." : shortcutString(keyCode: keyCode, modifiers: modifiers))
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isRecording ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.2))
                .foregroundColor(isRecording ? .accentColor : .primary)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isRecording ? Color.accentColor : Color.clear, lineWidth: 2)
                )
        }
        .buttonStyle(PlainButtonStyle())
        .background(ShortcutEventMonitor(isRecording: $isRecording, keyCode: $keyCode, modifiers: $modifiers, onChanged: onShortcutChanged))
        .onChange(of: isRecording) { recording in
            if recording {
                // Unregister so we can actually capture the keys
                HotkeyManager.shared.unregisterGlobalHotkey()
            } else {
                // It will be re-registered in onChanged
                onShortcutChanged()
            }
        }
    }
    
    private func shortcutString(keyCode: UInt32, modifiers: UInt32) -> String {
        var result = ""
        let mods = Int(modifiers)
        if (mods & controlKey) != 0 { result += "⌃ " }
        if (mods & optionKey) != 0 { result += "⌥ " }
        if (mods & shiftKey) != 0 { result += "⇧ " }
        if (mods & cmdKey) != 0 { result += "⌘ " }
        
        if let char = keyString(for: keyCode) {
            result += char.uppercased()
        }
        return result.isEmpty ? "Click to record" : result
    }
    
    private func keyString(for keyCode: UInt32) -> String? {
        let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource().takeRetainedValue()
        let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        
        guard let data = layoutData else { return nil }
        
        let keyboardLayout = unsafeBitCast(data, to: CFData.self)
        var keysDown: UInt32 = 0
        var chars: [UniChar] = [0, 0, 0, 0]
        var length = 0
        
        UCKeyTranslate(
            unsafeBitCast(CFDataGetBytePtr(keyboardLayout), to: UnsafePointer<UCKeyboardLayout>.self),
            UInt16(keyCode),
            UInt16(kUCKeyActionDown),
            0,
            UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysBit),
            &keysDown,
            4,
            &length,
            &chars
        )
        
        if length > 0 {
            return String(utf16CodeUnits: chars, count: length)
        }
        return nil
    }
}

struct ShortcutEventMonitor: NSViewRepresentable {
    @Binding var isRecording: Bool
    @Binding var keyCode: UInt32
    @Binding var modifiers: UInt32
    var onChanged: () -> Void
    
    func makeNSView(context: Context) -> NSView {
        return MonitorView()
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        if let view = nsView as? MonitorView {
            view.onKeyDown = { event in
                if isRecording {
                    let flags = event.modifierFlags
                    
                    var carbonModifiers: Int = 0
                    if flags.contains(.control) { carbonModifiers |= controlKey }
                    if flags.contains(.option) { carbonModifiers |= optionKey }
                    if flags.contains(.shift) { carbonModifiers |= shiftKey }
                    if flags.contains(.command) { carbonModifiers |= cmdKey }
                    
                    // Handle Escape to cancel
                    if event.keyCode == 53 && carbonModifiers == 0 {
                        DispatchQueue.main.async { isRecording = false }
                        return true
                    }
                    
                    // Disallow keys without modifiers
                    if carbonModifiers == 0 {
                        return true
                    }
                    
                    DispatchQueue.main.async {
                        keyCode = UInt32(event.keyCode)
                        modifiers = UInt32(carbonModifiers)
                        isRecording = false
                        onChanged()
                    }
                    return true
                }
                return false
            }
        }
    }
    
    class MonitorView: NSView {
        var onKeyDown: ((NSEvent) -> Bool)?
        private var monitor: Any?
        
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    let consumed = self?.onKeyDown?(event) ?? false
                    return consumed ? nil : event
                }
            } else if let monitor = monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}

struct ShortcutRow: View {
    let key: String
    let action: String
    
    var body: some View {
        HStack {
            Text(key)
                .font(.system(.caption, design: .monospaced))
                .bold()
                .frame(minWidth: 20)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.2))
                .cornerRadius(4)
            Text(action)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
