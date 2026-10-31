import Foundation

// WorkspaceWindow is a window as workspaces sees it: its ID, app, title and frame.
public struct WorkspaceWindow: Equatable, Sendable {
    // id is the window's ID.
    public var id: WindowID
    // bundle is the owning app's bundle ID.
    public var bundle: String
    // title is the window's title.
    public var title: String
    // frame is the window's frame.
    public var frame: Frame

    // init builds a workspace window.
    public init(id: WindowID, bundle: String, title: String, frame: Frame) {
        self.id = id
        self.bundle = bundle
        self.title = title
        self.frame = frame
    }
}

// SavedWindow is a free window's frame saved under its app and title.
public struct SavedWindow: Equatable, Sendable, Codable {
    // bundle is the owning app's bundle ID.
    public var bundle: String
    // title is the title the window had when saved.
    public var title: String
    // frame is the frame the window had when saved.
    public var frame: Frame
    // launchBundle is the bundle ID to launch when no window matches, nil to leave the entry alone.
    public var launchBundle: String?
    // openTarget is the URL or file the launch opens, nil for none.
    public var openTarget: String?

    // init builds a saved window.
    public init(
        bundle: String, title: String, frame: Frame, launchBundle: String? = nil, openTarget: String? = nil
    ) {
        self.bundle = bundle
        self.title = title
        self.frame = frame
        self.launchBundle = launchBundle
        self.openTarget = openTarget
    }
}

// LaunchRequest is an app to launch because no live window matches a workspace entry.
public struct LaunchRequest: Equatable, Sendable {
    // bundle is the bundle ID to launch.
    public var bundle: String
    // target is the URL or file to open with it, nil for none.
    public var target: String?

    // init builds a launch request.
    public init(bundle: String, target: String? = nil) {
        self.bundle = bundle
        self.target = target
    }
}

// AppRule is a per-app rule applied when the app's first window appears: an action name or a frame.
public struct AppRule: Equatable, Sendable, Codable {
    // bundle is the bundle ID the rule applies to.
    public var bundle: String
    // action is the action name to run, nil when the rule sets a frame.
    public var action: String?
    // frame is the frame to set, nil when the rule runs an action.
    public var frame: Frame?

    // init builds an app rule.
    public init(bundle: String, action: String? = nil, frame: Frame? = nil) {
        self.bundle = bundle
        self.action = action
        self.frame = frame
    }

    // valid reports whether the rule has a bundle and exactly one target, a known action or a frame.
    public var valid: Bool {
        guard !bundle.isEmpty else { return false }
        switch (action, frame) {
        case let (name?, nil): return Keymaps.known(name)
        case (nil, .some): return true
        default: return false
        }
    }
}

// Workspace is a named layout: the slots, the widths, the heights and every free window's frame.
public struct Workspace: Equatable, Sendable, Codable {
    // name is the workspace's name.
    public var name: String
    // slots maps each chosen slot to a bundle ID.
    public var slots: [SlotKey: String]
    // widths is the saved strip widths, nil when none were chosen.
    public var widths: Widths?
    // heights is the saved top row heights, nil when none were chosen.
    public var heights: Heights?
    // windows holds the free windows' frames keyed by bundle and title.
    public var windows: [SavedWindow]
    // setup is the display signature the workspace comes back for, nil when untied.
    public var setup: String?
    // displays lists the full frames of the screens attached when the workspace was saved, empty for a
    // workspace saved before they were kept.
    public var displays: [Frame]
    // recallOnDisplayChange reports whether the workspace comes back on any display change, tied or not.
    public var recallOnDisplayChange: Bool

    // init builds a workspace.
    public init(
        name: String, slots: [SlotKey: String] = [:], widths: Widths? = nil, heights: Heights? = nil,
        windows: [SavedWindow] = [], setup: String? = nil, displays: [Frame] = [],
        recallOnDisplayChange: Bool = false
    ) {
        self.name = name
        self.slots = slots
        self.widths = widths
        self.heights = heights
        self.windows = windows
        self.setup = setup
        self.displays = displays
        self.recallOnDisplayChange = recallOnDisplayChange
    }

    // CodingKeys names the saved fields.
    private enum CodingKeys: String, CodingKey {
        case name, slots, widths, heights, windows, setup, displays, recallOnDisplayChange
    }

    // init decodes a workspace, reading slots keyed by slot name and skipping unknown slots.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        let raw = (try? c.decodeIfPresent([String: String].self, forKey: .slots)) ?? [:]
        slots = Dictionary(uniqueKeysWithValues: raw.compactMap { k, v in SlotKey(rawValue: k).map { ($0, v) } })
        widths = try? c.decodeIfPresent(Widths.self, forKey: .widths)
        heights = try? c.decodeIfPresent(Heights.self, forKey: .heights)
        windows = (try? c.decodeIfPresent([SavedWindow].self, forKey: .windows)) ?? []
        setup = try? c.decodeIfPresent(String.self, forKey: .setup)
        displays = (try? c.decodeIfPresent([Frame].self, forKey: .displays)) ?? []
        recallOnDisplayChange = (try? c.decodeIfPresent(Bool.self, forKey: .recallOnDisplayChange)) ?? false
    }

    // encode writes the workspace with slots keyed by slot name, and its displays only when it has
    // any, so a file saved before they were kept reads back the same.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(Dictionary(uniqueKeysWithValues: slots.map { ($0.key.rawValue, $0.value) }), forKey: .slots)
        try c.encodeIfPresent(widths, forKey: .widths)
        try c.encodeIfPresent(heights, forKey: .heights)
        try c.encode(windows, forKey: .windows)
        try c.encodeIfPresent(setup, forKey: .setup)
        if !displays.isEmpty {
            try c.encode(displays, forKey: .displays)
        }
        try c.encode(recallOnDisplayChange, forKey: .recallOnDisplayChange)
    }
}

// ScreenAreas pairs a display's full frame with its usable area.
public struct ScreenAreas: Equatable, Sendable {
    // full is the display's full frame.
    public var full: Frame
    // area is the display's usable area.
    public var area: Frame

    // init builds a pair.
    public init(full: Frame, area: Frame) {
        self.full = full
        self.area = area
    }
}

// Workspaces holds the pure parts of saved workspaces: display signatures, window matching and
// fitting a saved frame to the displays.
public enum Workspaces {
    // signature names a display setup from its screens' full frames, the same whatever order the
    // screens come in.
    public static func signature(_ frames: [Frame]) -> String {
        frames.map { "\(Int($0.w))x\(Int($0.h))@\(Int($0.x)),\(Int($0.y))" }.sorted().joined(separator: " ")
    }

    // match pairs saved windows with live windows of the same app. A window whose title matches
    // wins, then any unused window of the app. It maps saved index to live index.
    public static func match(_ saved: [SavedWindow], _ live: [WorkspaceWindow]) -> [Int: Int] {
        var used = Set<Int>()
        var out: [Int: Int] = [:]
        for pass in 1...2 {
            for (i, e) in saved.enumerated() where out[i] == nil {
                for (j, l) in live.enumerated() where !used.contains(j) {
                    if l.bundle == e.bundle && (pass == 2 || l.title == e.title) {
                        used.insert(j)
                        out[i] = j
                        break
                    }
                }
            }
        }
        return out
    }

    // fit returns f clamped into the area of the screen holding its center. When no screen holds it,
    // f is mapped from bounds, the frame the saved setup spanned, onto the area of the first screen,
    // the main one, in proportion, and clamped there. It returns nil when no screen holds f and bounds
    // is nil or empty.
    public static func fit(_ f: Frame, _ screens: [ScreenAreas], from bounds: Frame? = nil) -> Frame? {
        let cx = f.x + f.w / 2
        let cy = f.y + f.h / 2
        for s in screens
        where cx >= s.full.x && cx < s.full.x + s.full.w && cy >= s.full.y && cy < s.full.y + s.full.h {
            return Geometry.clamp(f, s.area)
        }
        guard let b = bounds, b.w > 0, b.h > 0, let a = screens.first?.area else { return nil }
        let mapped = Frame(x: a.x + (f.x - b.x) * a.w / b.w, y: a.y + (f.y - b.y) * a.h / b.h, w: f.w, h: f.h)
        return Geometry.clamp(mapped, a)
    }

    // bounds returns the frame ws spanned when saved: the union of its displays, else of its windows'
    // frames, nil when it holds neither.
    public static func bounds(_ ws: Workspace) -> Frame? {
        let frames = ws.displays.isEmpty ? ws.windows.map(\.frame) : ws.displays
        guard let first = frames.first else { return nil }
        var minX = first.x
        var minY = first.y
        var maxX = first.x + first.w
        var maxY = first.y + first.h
        for f in frames.dropFirst() {
            minX = min(minX, f.x)
            minY = min(minY, f.y)
            maxX = max(maxX, f.x + f.w)
            maxY = max(maxY, f.y + f.h)
        }
        return Frame(x: minX, y: minY, w: maxX - minX, h: maxY - minY)
    }

    // launches returns the apps to launch for a workspace: each entry with a launch bundle that no
    // live window matches.
    public static func launches(_ ws: Workspace, _ live: [WorkspaceWindow]) -> [LaunchRequest] {
        let matched = match(ws.windows, live)
        return ws.windows.enumerated().compactMap { i, e in
            guard matched[i] == nil, let b = e.launchBundle, !b.isEmpty else { return nil }
            return LaunchRequest(bundle: b, target: e.openTarget)
        }
    }

    // rule returns the first valid rule for the bundle of a newly appeared first window, or nil.
    public static func rule(_ bundle: String, _ rules: [AppRule]) -> AppRule? {
        rules.first { $0.bundle == bundle && $0.valid }
    }

    // recalling returns the workspaces marked to come back on a display change, sorted by name.
    public static func recalling(_ all: [String: Workspace]) -> [Workspace] {
        all.values.filter(\.recallOnDisplayChange).sorted { $0.name < $1.name }
    }
}
