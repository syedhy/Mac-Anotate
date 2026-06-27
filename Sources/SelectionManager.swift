import Cocoa

class SelectionManager {
    static let shared = SelectionManager()
    
    var selectedAnnotationID: UUID?
    var hitResult: AnnotationHitTester.HitResult = .none
    
    private init() {}
    
    func clearSelection() {
        selectedAnnotationID = nil
        hitResult = .none
    }
}
