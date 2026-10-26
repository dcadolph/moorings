import AppKit
import SwiftUI
import os

import MooringsCore

// StripField names a value the strip editor edits.
enum StripField: Hashable {
    case leftWidth, rightWidth, leftTop, rightTop

    // side returns the strip the field belongs to.
    var side: Side { self == .leftWidth || self == .leftTop ? .left : .right }

    // isWidth reports whether the field is a strip width rather than a row line.
    var isWidth: Bool { self == .leftWidth || self == .rightWidth }
}

// StripState holds what the strip editor shows: the widths and heights being edited, the typed
// drafts, and the limits the apps set.
@MainActor
final class StripState: ObservableObject {
    // widths is the strip widths being edited.
    @Published private(set) var widths: Widths
    // heights is the top row heights being edited.
    @Published private(set) var heights: Heights
    // drafts holds each field's text, refreshed whenever a value changes.
    @Published var drafts: [StripField: String] = [:]
    // screenWidth is the ultrawide's usable width in points.
    let screenWidth: Double
    // minPoints holds the learned minimum width of each side's anchored app, zero when none.
    let minPoints: [Side: Double]
    // minNames names the app that sets each side's minimum.
    let minNames: [Side: String]
    // empty lists the sides with nothing anchored.
    let empty: [Side]
    // split lists the sides holding two anchored apps, the only ones with a row line.
    let split: [Side]
    // presets lists the built-in and saved width pairs offered as quick picks.
    let presets: [Widths]
    // changed is told about every new pair of widths and heights.
    var changed: (Widths, Heights) -> Void = { _, _ in }
    // finish is told whether to keep the edits when the editor closes.
    var finish: (Bool) -> Void = { _ in }
    // dropped is told when a drag ends, so the windows follow once the mouse is up.
    var dropped: () -> Void = {}

    // init builds the state from the values in effect and the limits on them.
    init(widths: Widths, heights: Heights, screenWidth: Double, minPoints: [Side: Double], minNames: [Side: String],
         empty: [Side], split: [Side], presets: [Widths]) {
        self.widths = widths
        self.heights = heights
        self.screenWidth = screenWidth
        self.minPoints = minPoints
        self.minNames = minNames
        self.empty = empty
        self.split = split
        self.presets = presets
        refreshDrafts()
    }

    // value returns field's current percent.
    func value(_ field: StripField) -> Double {
        switch field {
        case .leftWidth: widths.left
        case .rightWidth: widths.right
        case .leftTop: heights.left
        case .rightTop: heights.right
        }
    }

    // range returns the percentages side's width may take.
    func range(_ side: Side) -> ClosedRange<Double> {
        Layout.widthRange(widths, side, minPoints: minPoints[side] ?? 0, screenWidth: screenWidth)
    }

    // shown returns the share side's strip covers on screen: its chosen width, or more when an
    // anchored app there will not shrink to it.
    func shown(_ side: Side) -> Double {
        let pct = side == .left ? widths.left : widths.right
        guard !empty.contains(side), screenWidth > 0 else { return pct }
        return max(pct, (minPoints[side] ?? 0) * 100 / screenWidth)
    }

    // channel returns the share the channel covers on screen, which takes an empty side.
    var channel: Double {
        100 - [Side.left, .right].filter { !empty.contains($0) }.map(shown).reduce(0, +)
    }

    // points returns how many points side's strip covers on screen.
    func points(_ side: Side) -> Double {
        Layout.points(shown(side), screenWidth: screenWidth)
    }

    // set puts field at pct, kept inside its limits, and passes the change on when it moved.
    func set(_ field: StripField, _ pct: Double) {
        if field.isWidth {
            let w = Layout.clamped(widths, field.side, pct, minPoints: minPoints[field.side] ?? 0,
                                   screenWidth: screenWidth)
            guard w != widths else { return refreshDrafts() }
            widths = w
        } else {
            let v = Layout.clampedTop(pct)
            guard v != heights[field.side] else { return refreshDrafts() }
            heights[field.side] = v
        }
        refreshDrafts()
        changed(widths, heights)
    }

    // step moves field by delta percent.
    func step(_ field: StripField, _ delta: Double) {
        set(field, value(field) + delta)
    }

    // pick sets both widths to preset, each kept inside its limits.
    func pick(_ preset: Widths) {
        var w = Layout.clamped(widths, .left, preset.left, minPoints: minPoints[.left] ?? 0, screenWidth: screenWidth)
        w = Layout.clamped(w, .right, preset.right, minPoints: minPoints[.right] ?? 0, screenWidth: screenWidth)
        w = Layout.clamped(w, .left, preset.left, minPoints: minPoints[.left] ?? 0, screenWidth: screenWidth)
        guard w != widths else { return }
        widths = w
        refreshDrafts()
        changed(widths, heights)
    }

    // commit reads field's draft and applies it, putting the draft back when it is not a number.
    func commit(_ field: StripField) {
        let text = (drafts[field] ?? "").trimmingCharacters(in: CharacterSet(charactersIn: " %"))
        guard let pct = Double(text) else { return refreshDrafts() }
        set(field, pct)
    }

    // refreshDrafts writes every field's value into its draft.
    private func refreshDrafts() {
        for field in [StripField.leftWidth, .rightWidth, .leftTop, .rightTop] {
            drafts[field] = String(format: "%.0f", value(field))
        }
    }
}

// StripPanel is the editor's borderless panel. It takes the keyboard without activating Moorings.
final class StripPanel: NSPanel {
    // canBecomeKey lets the fields take typing.
    override var canBecomeKey: Bool { true }
    // canBecomeMain keeps the front app's main window where it is.
    override var canBecomeMain: Bool { false }

    // performKeyEquivalent gives the fields select all, copy, cut and paste, which Moorings has no
    // Edit menu to supply.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let actions: [String: Selector] = ["a": #selector(NSText.selectAll(_:)), "c": #selector(NSText.copy(_:)),
                                           "x": #selector(NSText.cut(_:)), "v": #selector(NSText.paste(_:))]
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           let key = event.charactersIgnoringModifiers, let action = actions[key],
           NSApp.sendAction(action, to: nil, from: self) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

// StripEditorView draws the strips over the ultrawide with a handle on each inner edge and row line.
struct StripEditorView: View {
    // state holds the values being edited.
    @ObservedObject var state: StripState
    // focus is the field taking the keyboard.
    @FocusState private var focus: StripField?

    // accent is the harbor accent.
    private static let accent = color(Palette.harbor.accent)
    // surface is the harbor surface.
    private static let surface = color(Palette.harbor.surface)
    // muted is the harbor muted text.
    private static let muted = color(Palette.harbor.muted)
    // space names the editor's coordinate space for drags.
    private static let space = "strips"

    // body lays the strips, the handles and the header over the screen.
    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let lx = size.width * state.shown(.left) / 100
            let rx = size.width - size.width * state.shown(.right) / 100
            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.3)
                strip(.left, x: 0, width: lx, size: size)
                strip(.right, x: rx, width: size.width - rx, size: size)
                if state.split.contains(.left) {
                    rowLine(.leftTop, x: 0, width: lx, size: size)
                }
                if state.split.contains(.right) {
                    rowLine(.rightTop, x: rx, width: size.width - rx, size: size)
                }
                edge(.leftWidth, x: lx, size: size)
                edge(.rightWidth, x: rx, size: size)
                header
                    .position(x: (lx + rx) / 2, y: 110)
            }
            .coordinateSpace(name: Self.space)
        }
        .onExitCommand { state.finish(false) }
        .onAppear { focus = .leftWidth }
        .onChange(of: focus) { old, new in
            if let old {
                state.commit(old)
            }
            if new != nil {
                DispatchQueue.main.async { NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil) }
            }
        }
    }

    // header shows the channel share, the quick picks, the keys and the buttons.
    private var header: some View {
        VStack(spacing: 12) {
            Text(String(format: "Channel %.0f%%", state.channel))
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
            HStack(spacing: 8) {
                ForEach(Array(state.presets.enumerated()), id: \.offset) { _, p in
                    Button(String(format: "%.0f / %.0f", p.left, p.right)) { state.pick(p) }
                        .buttonStyle(.bordered)
                }
            }
            Text("Arrows step 1%, Shift-arrows 5%. Type a number and press Tab. Drag an edge or a row line. "
                + "Return keeps, Escape puts it back.")
                .font(.system(size: 13))
                .foregroundStyle(Self.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            HStack(spacing: 12) {
                Button("Cancel") { state.finish(false) }
                    .keyboardShortcut(.cancelAction)
                Button("Done") { state.finish(true) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 12).fill(Self.surface.opacity(0.92)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Self.accent.opacity(0.5), lineWidth: 1))
    }

    // strip shades side's strip, marking it when nothing is anchored there.
    private func strip(_ side: Side, x: Double, width: Double, size: CGSize) -> some View {
        let empty = state.empty.contains(side)
        return Rectangle()
            .fill(Self.accent.opacity(empty ? 0.06 : 0.16))
            .overlay(Rectangle().stroke(Self.accent.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: empty ? [8, 6] : [])))
            .overlay(alignment: .bottom) {
                if empty {
                    Text("Nothing anchored: the channel uses this side")
                        .font(.system(size: 12))
                        .foregroundStyle(Self.muted)
                        .padding(.bottom, 16)
                }
            }
            .frame(width: max(0, width), height: size.height)
            .offset(x: x)
    }

    // edge draws a strip's inner edge as a drag bar with its arrows, its field and its points.
    private func edge(_ field: StripField, x: Double, size: CGSize) -> some View {
        let side = field.side
        let toLeft = side == .left ? -1.0 : 1.0
        let drag = DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space)).onChanged { v in
            let pct = side == .left ? v.location.x / size.width * 100 : (size.width - v.location.x) / size.width * 100
            state.set(field, pct)
        }.onEnded { _ in state.dropped() }
        let bar = Rectangle()
            .fill(Self.accent)
            .frame(width: 6, height: size.height)
            .contentShape(Rectangle().inset(by: -8))
            .gesture(drag)
            .onHover { inside in
                if inside {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .offset(x: x - 3)
        let box = VStack(spacing: 6) {
            Text(side == .left ? "Left strip" : "Right strip")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Self.muted)
            HStack(spacing: 6) {
                arrow("chevron.left") { state.step(field, toLeft) }
                numberField(field)
                arrow("chevron.right") { state.step(field, -toLeft) }
            }
            Text(String(format: "%.0f pt", state.points(side)))
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(Self.muted)
            if let caption = minCaption(side) {
                Text(caption)
                    .font(.system(size: 11))
                    .foregroundStyle(Self.accent)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 200)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Self.surface.opacity(0.92)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Self.accent.opacity(0.6), lineWidth: 1))
        .fixedSize()
        .position(x: x, y: size.height / 2)
        return ZStack(alignment: .topLeading) {
            bar
            box
        }
    }

    // rowLine draws the line between a strip's two rows as a drag bar with its arrows and its field.
    private func rowLine(_ field: StripField, x: Double, width: Double, size: CGSize) -> some View {
        let y = size.height * state.value(field) / 100
        let drag = DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space)).onChanged { v in
            state.set(field, v.location.y / size.height * 100)
        }.onEnded { _ in state.dropped() }
        let line = Rectangle()
            .fill(Self.accent.opacity(0.8))
            .frame(width: max(0, width), height: 4)
            .contentShape(Rectangle().inset(by: -8))
            .gesture(drag)
            .onHover { inside in
                if inside {
                    NSCursor.resizeUpDown.push()
                } else {
                    NSCursor.pop()
                }
            }
            .offset(x: x, y: y - 2)
        let box = HStack(spacing: 6) {
            arrow("chevron.up") { state.step(field, -1) }
            VStack(spacing: 2) {
                Text("Top row")
                    .font(.system(size: 11))
                    .foregroundStyle(Self.muted)
                numberField(field)
            }
            arrow("chevron.down") { state.step(field, 1) }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Self.surface.opacity(0.92)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Self.accent.opacity(0.6), lineWidth: 1))
        .fixedSize()
        .position(x: x + width / 2, y: y)
        return ZStack(alignment: .topLeading) {
            line
            box
        }
    }

    // numberField is field's typed percent. Arrow keys step it, Shift by five, and Return keeps
    // every edit.
    private func numberField(_ field: StripField) -> some View {
        HStack(spacing: 2) {
            TextField("", text: Binding(get: { state.drafts[field] ?? "" }, set: { state.drafts[field] = $0 }))
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center)
                .font(.system(size: 15).monospacedDigit())
                .frame(width: 52)
                .focused($focus, equals: field)
                .onSubmit {
                    state.commit(field)
                    state.finish(true)
                }
                .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow]) { press in
                    state.commit(field)
                    state.step(field, Self.delta(field, press.key) * (press.modifiers.contains(.shift) ? 5 : 1))
                    return .handled
                }
            Text("%")
                .foregroundStyle(.white)
        }
    }

    // delta returns which way key moves field: up and down raise and lower a width, left and right
    // move a width's edge that way, and up and down move a row line that way.
    private static func delta(_ field: StripField, _ key: KeyEquivalent) -> Double {
        if !field.isWidth {
            return key == .upArrow || key == .leftArrow ? -1 : 1
        }
        switch key {
        case .upArrow: return 1
        case .downArrow: return -1
        case .leftArrow: return field.side == .left ? -1 : 1
        default: return field.side == .left ? 1 : -1
        }
    }

    // arrow is a small button showing symbol that runs act.
    private func arrow(_ symbol: String, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.bordered)
        .focusable(false)
    }

    // minCaption says which app keeps side wider, nil when none does.
    private func minCaption(_ side: Side) -> String? {
        guard let pts = state.minPoints[side], pts > 0 else { return nil }
        let name = state.minNames[side] ?? "An app"
        return String(format: "%@ needs %.0f pt, so this strip is at least %.0f%%.", name, pts,
                      state.range(side).lowerBound)
    }

    // color returns rgb as a SwiftUI color.
    private static func color(_ rgb: RGB) -> Color {
        Color(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

// StripEditor shows the strips over the ultrawide with a handle on each inner edge and row line, so
// the widths and heights can be stepped, typed or dragged while the windows follow. Done keeps the
// edits and Escape puts back the widths and heights from when it opened.
@MainActor
final class StripEditor {
    // app is the running app delegate.
    private unowned let app: AppDelegate
    // logger writes why the editor did not open.
    private let logger = Logger(subsystem: "com.dcadolph.moorings", category: "strips")
    // panel is the editor, nil while closed.
    private var panel: StripPanel?
    // state holds the values being edited, nil while closed.
    private var state: StripState?
    // start holds the saved widths and heights from when the editor opened.
    private var start: (widths: Widths?, heights: Heights?)

    // init builds a strip editor for app.
    init(app: AppDelegate) {
        self.app = app
    }

    // showing reports whether the editor is open.
    var showing: Bool { panel != nil }

    // show opens the editor over the ultrawide and reports whether it opened. It brings an open
    // editor forward instead of opening another.
    @discardableResult
    func show() -> Bool {
        if let panel {
            panel.makeKeyAndOrderFront(nil)
            return true
        }
        guard let wide = Screens.current().wide else {
            logger.notice("strips: no ultrawide attached")
            return false
        }
        let anchors = app.anchors
        start = (anchors.choices.widths, anchors.choices.heights)
        var mins: [Side: Double] = [:]
        var names: [Side: String] = [:]
        for side in [Side.left, .right] {
            mins[side] = anchors.minWidth(side)
            names[side] = anchors.minBy[side].map { app.appName($0) }
        }
        let presets = Layout.presets + anchors.choices.widthPresets.filter { !Layout.presets.contains($0) }
        let s = StripState(widths: anchors.widths, heights: anchors.heights, screenWidth: wide.w, minPoints: mins,
                           minNames: names, empty: anchors.emptySides(), split: anchors.splitSides(),
                           presets: presets)
        s.changed = { [unowned self] w, h in preview(w, h) }
        s.finish = { [unowned self] keep in close(keep: keep) }
        s.dropped = { [unowned self, unowned s] in preview(s.widths, s.heights) }
        state = s
        let primary = NSScreen.screens.first?.frame.height ?? 0
        let rect = NSRect(x: wide.x, y: primary - wide.y - wide.h, width: wide.w, height: wide.h)
        let p = StripPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
                           defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        p.isReleasedWhenClosed = false
        p.contentView = NSHostingView(rootView: StripEditorView(state: s))
        panel = p
        p.makeKeyAndOrderFront(nil)
        return true
    }

    // close puts the editor away, keeping the edits or putting back the ones from when it opened,
    // and saves so the windows settle where the kept values put them.
    func close(keep: Bool) {
        guard let p = panel else { return }
        panel = nil
        state = nil
        p.orderOut(nil)
        if !keep {
            app.anchors.choices.widths = start.widths
            app.anchors.choices.heights = start.heights
        }
        app.save()
    }

    // preview applies w and h without saving them, so the windows follow while the editor is open.
    private func preview(_ w: Widths, _ h: Heights) {
        app.anchors.setWidths(w)
        app.anchors.choices.heights = h
        app.moor()
    }
}
