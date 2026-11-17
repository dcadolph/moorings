import MooringsCore

// ScreenSource reads the attached displays.
public protocol ScreenSource: AnyObject {
    // current returns the attached displays.
    func current() -> Screens
    // quirks is what ActionTarget needs beyond frames: notched screens, Stage Manager strips.
    // Windows returns .none.
    func quirks(_ screens: Screens) -> ScreenQuirks
    // displaySetKey names the set of displays in screens, the same whatever order they come in, so a
    // workspace can be tied to it.
    func displaySetKey(_ screens: Screens) -> String
    // facts describes each display in screens, in the same order, for the line a screen change logs.
    func facts(_ screens: Screens) -> [DisplayFacts]
}

extension ScreenSource {
    // displaySetKey keys the displays by their full frames, which is what the Mac uses.
    public func displaySetKey(_ screens: Screens) -> String {
        Workspaces.signature(screens.full)
    }

    // facts knows only the frames: no name, vendor or model, and a pixel for every point.
    public func facts(_ screens: Screens) -> [DisplayFacts] {
        screens.full.map { DisplayFacts(points: $0, pixelWidth: $0.w, pixelHeight: $0.h, scale: 1) }
    }
}

// DisplayFacts is what a log line says about one display: who made it, its frame in points, and its
// size in pixels.
public struct DisplayFacts: Equatable, Sendable {
    // name is the name the system shows for the display, empty when it gives none.
    public var name: String
    // vendor names the maker as the system reports it, empty when it gives none.
    public var vendor: String
    // model names the model as the system reports it, empty when it gives none.
    public var model: String
    // points is the display's full frame in points.
    public var points: Frame
    // pixelWidth is the display's width in pixels.
    public var pixelWidth: Double
    // pixelHeight is the display's height in pixels.
    public var pixelHeight: Double
    // scale is how many pixels make one point.
    public var scale: Double

    // init builds the facts for one display.
    public init(
        name: String = "", vendor: String = "", model: String = "", points: Frame, pixelWidth: Double,
        pixelHeight: Double, scale: Double
    ) {
        self.name = name
        self.vendor = vendor
        self.model = model
        self.points = points
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.scale = scale
    }

    // line describes the display at index i.
    public func line(_ i: Int) -> String {
        let n = Self.number
        let named = name.isEmpty ? "" : " \"\(name)\""
        return "\(i)\(named) vendor \(vendor.isEmpty ? "-" : vendor) model \(model.isEmpty ? "-" : model)"
            + " points \(n(points.x)),\(n(points.y)) \(n(points.w))x\(n(points.h))"
            + " pixels \(n(pixelWidth))x\(n(pixelHeight)) scale \(n(scale))"
    }

    // pnp splits a Windows monitor device id, such as MONITOR\DEL4127\{...}\0004, into its three
    // letter maker code and four digit product code, both empty when the id has another shape.
    public static func pnp(_ id: String) -> (vendor: String, model: String) {
        let parts = id.split(separator: "\\")
        guard parts.count > 1, parts[0] == "MONITOR", parts[1].count == 7 else { return ("", "") }
        return (String(parts[1].prefix(3)), String(parts[1].suffix(4)))
    }

    // number writes a whole value without a fraction and any other to two places.
    public static func number(_ v: Double) -> String {
        if v.isFinite, v == v.rounded(), abs(v) < 1e15 {
            return String(Int(v))
        }
        return String((v * 100).rounded() / 100)
    }
}
