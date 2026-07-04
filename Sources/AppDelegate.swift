import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    
    var menuBarController: MenuBarController?
    var overlayWindowController: OverlayWindowController?
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        print("Mac Annotate: applicationDidFinishLaunching called.")
        // Create the overlay window controller
        overlayWindowController = OverlayWindowController()
        
        // Setup menu bar
        menuBarController = MenuBarController(overlayController: overlayWindowController)
        print("Mac Annotate: MenuBarController initialized.")
        
        // Initialize HotkeyManager to listen for the global shortcut
        HotkeyManager.shared.onHotkeyPressed = { [weak self] in
            self?.overlayWindowController?.toggleOverlay()
        }
        HotkeyManager.shared.registerGlobalHotkey()
        
        // Make sure it doesn't show in dock
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        HotkeyManager.shared.unregisterGlobalHotkey()
    }
}
