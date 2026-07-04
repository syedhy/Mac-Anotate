import Cocoa

class SelectionManager {
    static let shared = SelectionManager()
    
    var selectedAnnotationIDs: Set<UUID> = []
    var wasMarqueeSelected: Bool = false
    
    private init() {}
    
    func clearSelection() {
        selectedAnnotationIDs.removeAll()
        wasMarqueeSelected = false
    }
}
