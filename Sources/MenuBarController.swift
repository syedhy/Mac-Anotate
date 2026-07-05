import Cocoa
import Combine

class MenuBarController {
    var statusItem: NSStatusItem!
    weak var overlayController: OverlayWindowController?
    private var activateMenuItem: NSMenuItem?
    private var shortcutObserver: AnyCancellable?
    
    init(overlayController: OverlayWindowController?) {
        self.overlayController = overlayController
        setupMenu()
        shortcutObserver = SettingsStore.shared.$globalShortcutKeyCode
            .combineLatest(SettingsStore.shared.$globalShortcutModifiers)
            .sink { [weak self] _, _ in
                self?.updateActivationShortcut()
            }
    }
    
    private func setupMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        if let button = statusItem.button {
            if let image = NSImage(systemSymbolName: "pencil", accessibilityDescription: "Mac Annotate") {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "✎" // Fallback if image fails to load
            }
        }
        
        let menu = NSMenu()
        
        let activateItem = NSMenuItem(title: "Activate Annotate Mode", action: #selector(toggleAnnotation), keyEquivalent: "")
        activateMenuItem = activateItem
        menu.addItem(activateItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))
        
        // Ensure actions are forwarded to this controller
        for item in menu.items {
            item.target = self
        }
        
        statusItem.menu = menu
        updateActivationShortcut()
    }

    private func updateActivationShortcut() {
        guard let activateMenuItem else { return }
        activateMenuItem.keyEquivalent = SettingsStore.shared.globalShortcutKeyEquivalent
        activateMenuItem.keyEquivalentModifierMask = SettingsStore.shared.globalShortcutModifierFlags
    }
    
    @objc private func toggleAnnotation() {
        overlayController?.toggleOverlay()
    }
    
    @objc private func openSettings() {
        SettingsWindowController.shared.showWindow(nil)
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
