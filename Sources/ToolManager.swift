import Foundation
import SwiftUI

enum ToolType: String, CaseIterable {
    case select
    case pen
    case arrow
    case rectangle
    case oval
    case text
    case laserPointer
    case laserPen
    var iconName: String {
        switch self {
        case .select: return "cursorarrow"
        case .pen: return "paintbrush.pointed"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .oval: return "oval"
        case .text: return "textformat"
        case .laserPointer: return "smallcircle.filled.circle"
        case .laserPen: return "wand.and.rays"
        }
    }
    
    var name: String {
        switch self {
        case .select: return "Select"
        case .pen: return "Pen"
        case .arrow: return "Arrow"
        case .rectangle: return "Rectangle"
        case .oval: return "Oval"
        case .text: return "Text"
        case .laserPointer: return "Laser Pointer"
        case .laserPen: return "Laser Pen"
        }
    }
    
    var keyEquivalent: String {
        switch self {
        case .select: return "v"
        case .pen: return "p"
        case .arrow: return "a"
        case .rectangle: return "r"
        case .oval: return "o"
        case .text: return "t"
        case .laserPointer: return "l"
        case .laserPen: return "l"
        }
    }
}

class ToolManager: ObservableObject {
    static let shared = ToolManager()
    
    @Published var activeTool: ToolType = .pen
    
    private init() {}
    
    func handleKeyPress(_ characters: String) -> Bool {
        let char = characters.lowercased()
        
        if char == "l" {
            if activeTool == .laserPointer {
                activeTool = .laserPen
            } else {
                activeTool = .laserPointer
            }
            return true
        }
        
        for tool in ToolType.allCases {
            if tool.keyEquivalent == char {
                activeTool = tool
                return true
            }
        }
        return false
    }
}
