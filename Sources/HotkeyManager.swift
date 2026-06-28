import Cocoa
import Carbon

class HotkeyManager {
    static let shared = HotkeyManager()
    
    var onHotkeyPressed: (() -> Void)?
    
    private var hotKeyRef: EventHotKeyRef?
    
    private init() {}
    
    func registerGlobalHotkey() {
        // Unregister first if already registered
        unregisterGlobalHotkey()
        
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = fourCharCode("ANOT")
        hotKeyID.id = 1
        
        var eventType = EventTypeSpec()
        eventType.eventClass = OSType(kEventClassKeyboard)
        eventType.eventKind = OSType(kEventHotKeyPressed)
        
        let handler: EventHandlerUPP = { (nextHandler, theEvent, userData) -> OSStatus in
            print("Anotate: Hotkey pressed!")
            HotkeyManager.shared.onHotkeyPressed?()
            return noErr
        }
        
        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, nil, nil)
        
        let keyCode = SettingsStore.shared.globalShortcutKeyCode
        let modifiers = SettingsStore.shared.globalShortcutModifiers
        
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        
        if status != noErr {
            print("Error registering global hotkey: \(status)")
        } else {
            print("Global hotkey registered successfully.")
        }
    }
    
    func unregisterGlobalHotkey() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }
}

extension String {
    var fourCharCodeValue: Int {
        var result: Int = 0
        if let data = self.data(using: String.Encoding.macOSRoman) {
            for (index, byte) in data.enumerated() {
                let shiftAmount = UInt(3 - index) * 8
                result = result + (Int(byte) << shiftAmount)
            }
        }
        return result
    }
}

func fourCharCode(_ string: String) -> OSType {
    return OSType(string.fourCharCodeValue)
}
