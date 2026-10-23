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

    // init builds a saved window.
    public init(bundle: String, title: String, frame: Frame) {
        self.bundle = bundle
        self.title = title
        self.frame = frame
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

    // init builds a workspace.
    public init(
        name: String, slots: [SlotKey: String] = [:], widths: Widths? = nil, heights: Heights? = nil,
        windows: [SavedWindow] = [], setup: String? = nil
    ) {
        self.name = name
        self.slots = slots
        self.widths = widths
        self.heights = heights
        self.windows = windows
        self.setup = setup
    }

    // CodingKeys names the saved fields.
    private enum CodingKeys: String, CodingKey {
        case name, slots, widths, heights, windows, setup
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
    }

    // encode writes the workspace with slots keyed by slot name.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(Dictionary(uniqueKeysWithValues: slots.map { ($0.key.rawValue, $0.value) }), forKey: .slots)
        try c.encodeIfPresent(widths, forKey: .widths)
        try c.encodeIfPresent(heights, forKey: .heights)
        try c.encode(windows, forKey: .windows)
        try c.encodeIfPresent(setup, forKey: .setup)
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

    // fit returns f clamped into the area of the screen holding its center, or nil when no screen
    // holds it.
    public static func fit(_ f: Frame, _ screens: [ScreenAreas]) -> Frame? {
        let cx = f.x + f.w / 2
        let cy = f.y + f.h / 2
        for s in screens
        where cx >= s.full.x && cx < s.full.x + s.full.w && cy >= s.full.y && cy < s.full.y + s.full.h {
            return Geometry.clamp(f, s.area)
        }
        return nil
    }
}
