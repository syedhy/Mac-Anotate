import Cocoa
import SwiftUI

class SettingsStore: ObservableObject {
    static let shared = SettingsStore()
    
    private let defaults = UserDefaults.standard
    
    private let colorKey = "lastSelectedColorHex"
    private let strokeWidthKey = "lastSelectedStrokeWidth"
    private let clearOnExitKey = "clearOnExit"
    private let globalShortcutKeyCodeKey = "globalShortcutKeyCode"
    private let globalShortcutModifiersKey = "globalShortcutModifiers"
    
    @Published var lastSelectedColor: NSColor {
        didSet {
            defaults.set(lastSelectedColor.hexString, forKey: colorKey)
        }
    }
    
    @Published var lastSelectedStrokeWidth: CGFloat {
        didSet {
            defaults.set(Double(lastSelectedStrokeWidth), forKey: strokeWidthKey)
        }
    }
    
    @Published var clearOnExit: Bool {
        didSet {
            defaults.set(clearOnExit, forKey: clearOnExitKey)
        }
    }
    
    @Published var globalShortcutKeyCode: UInt32 {
        didSet {
            defaults.set(Int(globalShortcutKeyCode), forKey: globalShortcutKeyCodeKey)
        }
    }
    
    @Published var globalShortcutModifiers: UInt32 {
        didSet {
            defaults.set(Int(globalShortcutModifiers), forKey: globalShortcutModifiersKey)
        }
    }
    
    private init() {
        // Default color: Bright Red
        let defaultColorHex = "#FF3B30"
        let savedHex = defaults.string(forKey: colorKey) ?? defaultColorHex
        self.lastSelectedColor = NSColor(hex: savedHex) ?? NSColor.systemRed
        
        let savedStroke = defaults.object(forKey: strokeWidthKey) as? Double
        self.lastSelectedStrokeWidth = CGFloat(savedStroke ?? 8.0)
        
        if defaults.object(forKey: clearOnExitKey) == nil {
            self.clearOnExit = true
            defaults.set(true, forKey: clearOnExitKey)
        } else {
            self.clearOnExit = defaults.bool(forKey: clearOnExitKey)
        }
        
        if defaults.object(forKey: globalShortcutKeyCodeKey) == nil {
            self.globalShortcutKeyCode = 37 // L
            defaults.set(37, forKey: globalShortcutKeyCodeKey)
        } else {
            self.globalShortcutKeyCode = UInt32(defaults.integer(forKey: globalShortcutKeyCodeKey))
        }
        
        if defaults.object(forKey: globalShortcutModifiersKey) == nil {
            // optionKey | shiftKey = 2048 | 512 = 2560
            let defaultMods: UInt32 = 2560 // 2048 + 512
            self.globalShortcutModifiers = defaultMods
            defaults.set(Int(defaultMods), forKey: globalShortcutModifiersKey)
        } else {
            self.globalShortcutModifiers = UInt32(defaults.integer(forKey: globalShortcutModifiersKey))
        }
    }
}

// MARK: - NSColor Extension for Hex
extension NSColor {
    var hexString: String {
        guard let rgbColor = usingColorSpace(.deviceRGB) else { return "#000000" }
        let red = Int(round(rgbColor.redComponent * 0xFF))
        let green = Int(round(rgbColor.greenComponent * 0xFF))
        let blue = Int(round(rgbColor.blueComponent * 0xFF))
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
    
    convenience init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt64 = 0
        
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }
        
        let r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(rgb & 0x0000FF) / 255.0
        
        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
}
