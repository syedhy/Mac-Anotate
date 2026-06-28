import SwiftUI
import Cocoa

class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()
    
    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 550),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Anotate Settings"
        window.titlebarAppearsTransparent = true
        window.center()
        window.setFrameAutosaveName("SettingsWindow")
        
        let hostingView = NSHostingView(rootView: SettingsView().frame(minWidth: 480, minHeight: 550))
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
            
            Form {
                Section(header: Text("General").font(.headline).padding(.bottom, 4)) {
                    Toggle("Clear annotations on exit", isOn: $settings.clearOnExit)
                        .toggleStyle(.switch)
                }
                .padding(.bottom, 16)
                
                Section(header: Text("Appearance").font(.headline).padding(.bottom, 4)) {
                    ColorPicker("Default Color", selection: Binding(
                        get: { Color(nsColor: settings.lastSelectedColor) },
                        set: { settings.lastSelectedColor = NSColor($0) }
                    ))
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Default Stroke Width: \(Int(settings.lastSelectedStrokeWidth))")
                        Slider(value: $settings.lastSelectedStrokeWidth, in: 2...20, step: 1)
                            .frame(maxWidth: 200)
                    }
                    .padding(.top, 4)
                }
                .padding(.bottom, 16)
                
                Section(header: Text("Shortcuts").font(.headline).padding(.bottom, 4)) {
                    HStack {
                        Text("Global Activation Shortcut:")
                        Spacer()
                        Text("⌥ ⇧ L")
                            .font(.system(.body, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.2))
                            .cornerRadius(6)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tool Shortcuts (when active):")
                            .padding(.top, 8)
                        
                        LazyVGrid(columns: [GridItem(.fixed(120)), GridItem(.flexible())], alignment: .leading, spacing: 6) {
                            ShortcutRow(key: "P", action: "Pen")
                            ShortcutRow(key: "A", action: "Arrow")
                            ShortcutRow(key: "R", action: "Rectangle")
                            ShortcutRow(key: "O", action: "Oval")
                            ShortcutRow(key: "T", action: "Text")
                            ShortcutRow(key: "L", action: "Laser")
                            ShortcutRow(key: "C", action: "Clear All")
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .formStyle(.grouped)
            .padding(.horizontal, 16)
            
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
