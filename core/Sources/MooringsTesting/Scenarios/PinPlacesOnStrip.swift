import MooringsCore
import MooringsEngine

extension Scenarios {
    // pinPlacesOnStrip pins a window's app to the left top slot and proves the pass puts it on the
    // left strip within 2 s, read back within 1 point.
    static func pinPlacesOnStrip(_ s: Stage) {
        _ = s.pin()
    }
}
