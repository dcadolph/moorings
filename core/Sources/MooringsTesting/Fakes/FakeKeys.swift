import MooringsCore
import MooringsEngine

// FakeKeys is a Keys that keeps the bound shortcuts and the grabbed keys, and delivers a press a test
// makes: to the grab's handler by tag when a grabbed key matches, else to actions by name when a bound
// shortcut does.
public final class FakeKeys: Keys {
    // shortcutsOn reports whether shortcuts are on; tests turn it off.
    public var shortcutsOn = true
    // bound is the map the last bind registered.
    public private(set) var bound: [String: Shortcut] = [:]
    // actions lists the action names bound shortcuts delivered, in order.
    public private(set) var actions: [String] = []
    // grabbed lists the keys the current grab holds.
    public private(set) var grabbed: [GrabKey] = []
    // grabs counts the grabs.
    public private(set) var grabs = 0
    // ungrabs counts the ungrabs.
    public private(set) var ungrabs = 0
    // handler is the current grab's handler, nil when nothing is grabbed.
    private var handler: ((String) -> Void)?

    // init builds keys with nothing bound or grabbed.
    public init() {}

    // bind replaces the bound shortcuts with map.
    public func bind(_ map: [String: Shortcut]) {
        bound = map
    }

    // grab replaces the grab with keys and handler and returns how many were taken.
    public func grab(_ keys: [GrabKey], _ handler: @escaping (String) -> Void) -> Int {
        grabs += 1
        grabbed = keys
        self.handler = handler
        return keys.count
    }

    // ungrab lets every key go.
    public func ungrab() {
        ungrabs += 1
        grabbed = []
        handler = nil
    }

    // spell writes the shortcut with its menu glyphs.
    public func spell(_ s: Shortcut) -> String {
        s.text
    }

    // press delivers the tag of a grabbed key matching key and its modifiers, or else the name of a
    // bound shortcut on the same key and modifiers; a key neither holds delivers nothing.
    public func press(_ key: GrabKey) {
        if let k = grabbed.first(where: { $0.key == key.key && $0.modifiers == key.modifiers }) {
            handler?(k.tag)
            return
        }
        let mods = Set(key.modifiers.shortcut)
        if let name = bound.sorted(by: { $0.key < $1.key })
            .first(where: { $0.value.key == key.key && Set($0.value.mods) == mods })?.key
        {
            actions.append(name)
        }
    }
}
