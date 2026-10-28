import MooringsCore
import MooringsEngine

extension Scenarios {
    // altDragParks drags a window by its title bar to the left edge with Option held, Alt on Windows,
    // and proves the drop parks it in the left top slot and the slot holds its app.
    static func altDragParks(_ s: Stage) {
        guard let wide = s.wide(), let full = s.full(), let (pad, _) = s.dragged(wide) else { return }
        guard s.drag(pad, to: edge(full), held: .option, "dragged window") else { return }
        let on = s.drops.last?.on
        if on != .park(SlotKey.leftTop.rawValue) {
            s.fail("Option held at the drop parks the window in left top", "dropped on \(String(describing: on))")
        }
        let holder = s.engine.anchors.choices.slots[.leftTop]
        s.measure("left top holds \(holder ?? "nothing")")
        if holder != pad.bundle {
            s.fail("the left top slot holds the parked window's app", "want \(pad.bundle), got \(holder ?? "nothing")")
        }
    }
}
