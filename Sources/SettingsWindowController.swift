import SwiftUI
import Cocoa

class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()
    
    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Anotate Settings"
        window.center()
        window.setFrameAutosaveName("SettingsWindow")
        
        let hostingView = NSHostingView(rootView: SettingsView())
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
    
    // For MVP we just use text fields for shortcuts, but a proper shortcut recorder would be better later
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Settings")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GroupBox(label: Text("General")) {
                        VStack(alignment: .leading) {
                            Toggle("Clear annotations on exit", isOn: $settings.clearOnExit)
                        }
                        .padding()
                    }
                    
                    GroupBox(label: Text("Appearance")) {
                        VStack(alignment: .leading) {
                            ColorPicker("Default Color", selection: Binding(
                                get: { Color(nsColor: settings.lastSelectedColor) },
                                set: { settings.lastSelectedColor = NSColor($0) }
                            ))
                            
                            VStack(alignment: .leading) {
                                Text("Default Stroke Width: \(Int(settings.lastSelectedStrokeWidth))")
                                Slider(value: $settings.lastSelectedStrokeWidth, in: 2...20, step: 1)
                            }
                        }
                        .padding()
                    }
                    
                    GroupBox(label: Text("Shortcuts")) {
                        VStack(alignment: .leading) {
                            Text("Global Activation Shortcut:")
                                .font(.caption)
                            Text("Option + Shift + L")
                                .bold()
                                .padding(4)
                                .background(Color.secondary.opacity(0.2))
                                .cornerRadius(4)
                            
                            Text("Tool Shortcuts (when active):")
                                .font(.caption)
                                .padding(.top, 4)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("P - Pen")
                                Text("A - Arrow")
                                Text("R - Rectangle")
                                Text("O - Oval")
                                Text("T - Text")
                                Text("L - Laser")
                                Text("C - Clear All")
                            }.font(.caption2).foregroundColor(.secondary)
                        }
                        .padding()
                    }
                }
            }
            .padding()
            
            Spacer()
            
            HStack {
                Spacer()
                Button("Done") {
                    SettingsWindowController.shared.close()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 400, height: 450)
    }
}
