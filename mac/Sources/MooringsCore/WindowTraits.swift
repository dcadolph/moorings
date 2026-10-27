// WindowTraits is what one Accessibility read says about a window, enough to decide whether moorings
// may move it.
public struct WindowTraits: Equatable, Sendable {
    // role is the window's AXRole, nil when it cannot be read.
    public var role: String?
    // subrole is the window's AXSubrole, nil when it cannot be read.
    public var subrole: String?
    // minimized is whether the window is in the Dock.
    public var minimized: Bool
    // fullScreen is whether the window is in its own full screen space.
    public var fullScreen: Bool
    // identifier is the window's AXIdentifier, which AppKit sets on open and save panels.
    public var identifier: String?
    // hasZoomButton is whether the window has a green zoom button.
    public var hasZoomButton: Bool
    // frame is the window's position and size, nil when either cannot be read.
    public var frame: Frame?

    // init makes traits, with every value missing or false unless given.
    public init(
        role: String? = nil, subrole: String? = nil, minimized: Bool = false, fullScreen: Bool = false,
        identifier: String? = nil, hasZoomButton: Bool = false, frame: Frame? = nil
    ) {
        self.role = role
        self.subrole = subrole
        self.minimized = minimized
        self.fullScreen = fullScreen
        self.identifier = identifier
        self.hasZoomButton = hasZoomButton
        self.frame = frame
    }

    // document reports whether the window is a document window: a standard window, or a dialog with a
    // zoom button, which is how TextEdit's documents report themselves.
    public var document: Bool {
        switch subrole {
        case "AXStandardWindow": true
        case "AXDialog": hasZoomButton
        default: false
        }
    }

    // filePanel reports whether the window is an open or save panel.
    public var filePanel: Bool {
        identifier == "open-panel" || identifier == "save-panel"
    }

    // eligible reports whether a scan would keep the window by its kind: a document window or a file
    // panel.
    public var eligible: Bool {
        document || filePanel
    }

    // movable reports whether moorings may move the window: a document window that is not minimized
    // and whose frame is known.
    public var movable: Bool {
        role == "AXWindow" && document && !minimized && frame != nil
    }
}
