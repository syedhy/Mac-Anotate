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

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            PermissionManager.shared.requestScreenRecordingPermissionIfNeeded()
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        HotkeyManager.shared.unregisterGlobalHotkey()
    }
}

class PermissionManager {
    static let shared = PermissionManager()

    private init() {}

    var hasScreenRecordingPermission: Bool {
        CGPreflightScreenCaptureAccess()
    }

    @discardableResult
    func requestScreenRecordingPermissionIfNeeded() -> Bool {
        guard !hasScreenRecordingPermission else { return true }
        return CGRequestScreenCaptureAccess()
    }
}
