import Foundation
import SwiftUI

enum ToolType: String, CaseIterable {
    case select
    case pen
    case arrow
    case rectangle
    case oval
    case text
    case laser
    
    var iconName: String {
        switch self {
        case .select: return "cursorarrow"
        case .pen: return "paintbrush.pointed"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .oval: return "oval"
        case .text: return "textformat"
        case .laser: return "wand.and.rays"
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
        case .laser: return "l"
        }
    }
}

class ToolManager: ObservableObject {
    static let shared = ToolManager()
    
    @Published var activeTool: ToolType = .pen
    
    private init() {}
    
    func handleKeyPress(_ characters: String) -> Bool {
        let char = characters.lowercased()
        for tool in ToolType.allCases {
            if tool.keyEquivalent == char {
                activeTool = tool
                return true
            }
        }
        return false
    }
}
