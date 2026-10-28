import MooringsCore
import MooringsEngine

// FakeKeys is a Keys that keeps the grabbed keys and delivers a press a test makes.
public final class FakeKeys: Keys {
    // shortcutsOn reports whether shortcuts are on; tests turn it off.
    public var shortcutsOn = true
    // grabbed lists the keys the current grab holds.
    public private(set) var grabbed: [GrabKey] = []
    // handler is the current grab's handler, nil when nothing is grabbed.
    private var handler: ((String) -> Void)?

    // init builds keys with nothing grabbed.
    public init() {}

    // grab replaces the grab with keys and handler and returns how many were taken.
    public func grab(_ keys: [GrabKey], _ handler: @escaping (String) -> Void) -> Int {
        grabbed = keys
        self.handler = handler
        return keys.count
    }

    // ungrab lets every key go.
    public func ungrab() {
        grabbed = []
        handler = nil
    }

    // spell writes the shortcut with its menu glyphs.
    public func spell(_ s: Shortcut) -> String {
        s.text
    }

    // press delivers the tag of a grabbed key matching key and its modifiers; a key not grabbed
    // delivers nothing.
    public func press(_ key: GrabKey) {
        guard let k = grabbed.first(where: { $0.key == key.key && $0.modifiers == key.modifiers }) else { return }
        handler?(k.tag)
    }
}
