import Cocoa
import Carbon
import SwiftUI

enum ToolbarEdge: String, Codable {
    case top, bottom, left, right
}

class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    private let defaults = UserDefaults.standard

    private let colorKey = "lastSelectedColorHex"
    private let strokeWidthKey = "lastSelectedStrokeWidth"
    private let clearOnExitKey = "clearOnExit"
    private let globalShortcutKeyCodeKey = "globalShortcutKeyCode"
    private let globalShortcutModifiersKey = "globalShortcutModifiers"
    private let toolbarEdgeKey = "toolbarEdge"
    private let hasShownShortcutHelpKey = "hasShownShortcutHelp"

    @Published var lastSelectedColor: NSColor {
        didSet {
            defaults.set(lastSelectedColor.hexString, forKey: colorKey)
        }
    }

    @Published var toolbarEdge: ToolbarEdge {
        didSet {
            defaults.set(toolbarEdge.rawValue, forKey: toolbarEdgeKey)
        }
    }

    @Published var lastSelectedStrokeWidth: CGFloat {
        didSet {
            defaults.set(Double(lastSelectedStrokeWidth), forKey: strokeWidthKey)
        }
    }

    @Published var isToolbarHidden: Bool = false

    @Published var hasShownShortcutHelp: Bool {
        didSet {
            defaults.set(hasShownShortcutHelp, forKey: hasShownShortcutHelpKey)
        }
    }

    private let fillStyleKey = "lastSelectedFillStyle"

    @Published var lastSelectedFillStyle: ShapeFillStyle {
        didSet {
            defaults.set(lastSelectedFillStyle.rawValue, forKey: fillStyleKey)
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

        if defaults.object(forKey: fillStyleKey) == nil {
            self.lastSelectedFillStyle = .hollow
            defaults.set(ShapeFillStyle.hollow.rawValue, forKey: fillStyleKey)
        } else {
            self.lastSelectedFillStyle = ShapeFillStyle(rawValue: defaults.integer(forKey: fillStyleKey)) ?? .hollow
        }

        if defaults.object(forKey: clearOnExitKey) == nil {
            self.clearOnExit = true
            defaults.set(true, forKey: clearOnExitKey)
        } else {
            self.clearOnExit = defaults.bool(forKey: clearOnExitKey)
        }

        self.hasShownShortcutHelp = defaults.bool(forKey: hasShownShortcutHelpKey)

        if let savedString = defaults.string(forKey: toolbarEdgeKey), let edge = ToolbarEdge(rawValue: savedString) {
            self.toolbarEdge = edge
        } else {
            self.toolbarEdge = .top
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

    var globalShortcutKeyEquivalent: String {
        Self.keyString(for: globalShortcutKeyCode)?.lowercased() ?? ""
    }

    var globalShortcutModifierFlags: NSEvent.ModifierFlags {
        Self.modifierFlags(fromCarbonModifiers: globalShortcutModifiers)
    }

    static func shortcutString(keyCode: UInt32, modifiers: UInt32) -> String {
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

    private static func modifierFlags(fromCarbonModifiers modifiers: UInt32) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        let mods = Int(modifiers)
        if (mods & controlKey) != 0 { flags.insert(.control) }
        if (mods & optionKey) != 0 { flags.insert(.option) }
        if (mods & shiftKey) != 0 { flags.insert(.shift) }
        if (mods & cmdKey) != 0 { flags.insert(.command) }
        return flags
    }

    static func keyString(for keyCode: UInt32) -> String? {
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
