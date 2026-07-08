import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    
    var menuBarController: MenuBarController?
    var overlayWindowController: OverlayWindowController?
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Create the overlay window controller
        overlayWindowController = OverlayWindowController()
        
        // Setup menu bar
        menuBarController = MenuBarController(overlayController: overlayWindowController)
        
        // Initialize HotkeyManager to listen for the global shortcut
        HotkeyManager.shared.onHotkeyPressed = { [weak self] in
            self?.overlayWindowController?.toggleOverlay()
        }
        HotkeyManager.shared.registerGlobalHotkey()
        
        // Make sure it doesn't show in dock
        NSApp.setActivationPolicy(.accessory)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            PermissionManager.shared.requestScreenRecordingPermissionOnFirstLaunch()
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        HotkeyManager.shared.unregisterGlobalHotkey()
    }
}

class PermissionManager {
    static let shared = PermissionManager()

    private let defaults = UserDefaults.standard
    private let screenRecordingPermissionRequestedKey = "screenRecordingPermissionRequested"

    private init() {}

    var hasScreenRecordingPermission: Bool {
        CGPreflightScreenCaptureAccess()
    }

    var hasRequestedScreenRecordingPermission: Bool {
        defaults.bool(forKey: screenRecordingPermissionRequestedKey)
    }

    func requestScreenRecordingPermissionOnFirstLaunch() {
        guard !hasScreenRecordingPermission, !hasRequestedScreenRecordingPermission else { return }
        requestScreenRecordingPermissionIfNeeded()
    }

    @discardableResult
    func requestScreenRecordingPermissionIfNeeded() -> Bool {
        guard !hasScreenRecordingPermission else { return true }
        guard !hasRequestedScreenRecordingPermission else { return false }
        defaults.set(true, forKey: screenRecordingPermissionRequestedKey)
        return CGRequestScreenCaptureAccess()
    }

    func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
