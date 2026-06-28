import Cocoa

class SelectionManager {
    static let shared = SelectionManager()
    
    var selectedAnnotationIDs: Set<UUID> = []
    var hitResult: AnnotationHitTester.HitResult = .none
    
    private init() {}
    
    func clearSelection() {
        selectedAnnotationIDs.removeAll()
        hitResult = .none
    }
}
