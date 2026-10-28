import SwiftUI

import MooringsCore
import MooringsEngine

// SettingsView is the settings window's content: shortcuts, sizes, workspaces, layout, snapping, behavior,
// menu and general choices.
struct SettingsView: View {
    // model holds the choices and saves each change.
    @ObservedObject var model: SettingsModel

    // body lays the tabs out above the restore defaults button every tab shares.
    var body: some View {
        VStack(spacing: 0) {
            tabs
                .padding([.top, .horizontal])
            HStack {
                Spacer()
                Button("Restore defaults…") { confirmRestore = true }
            }
            .padding()
        }
        .frame(width: 840, height: 640)
        .confirmationDialog("Restore the default settings?", isPresented: $confirmRestore) {
            Button("Restore defaults", role: .destructive) { model.change { $0 = $0.restoringDefaults() } }
        } message: {
            Text("Shortcuts, snapping and behavior go back to their defaults. Anchored apps, strip "
                + "sizes, ignored apps, custom sizes, workspaces, chains and app rules stay.")
        }
    }

    // confirmRestore reports whether the restore defaults question is showing.
    @State private var confirmRestore = false

    // tabs lays the sections out as tabs.
    private var tabs: some View {
        TabView {
            shortcuts.tabItem { Label("Shortcuts", systemImage: "keyboard") }
            sizes.tabItem { Label("Sizes", systemImage: "aspectratio") }
            workspaces.tabItem { Label("Workspaces", systemImage: "rectangle.3.group") }
            layout.tabItem { Label("Layout", systemImage: "rectangle.split.3x1") }
            snapping.tabItem { Label("Snapping", systemImage: "square.on.square.dashed") }
            behavior.tabItem { Label("Behavior", systemImage: "arrow.triangle.2.circlepath") }
            menu.tabItem { Label("Menu", systemImage: "list.bullet") }
            general.tabItem { Label("General", systemImage: "gearshape") }
        }
    }

    // actionNames lists every action that can take a shortcut, in menu order.
    private var actionNames: [String] {
        ActionRunner.families.flatMap { $0.names + $0.groups.flatMap(\.names) } + Tile.names
    }

    // runNames lists every action a shortcut or mouse button can run: the window actions, the menu
    // at the pointer and the chains.
    private var runNames: [String] {
        actionNames + [Keymaps.menuName, Keymaps.stripsName] + model.choices.chains.map(\.actionName)
    }

    // shortcuts lists every action with its shortcut, a recorder, and a way back to the keymap's.
    private var shortcuts: some View {
        let map = model.bindings.map
        return List(runNames, id: \.self) { name in
            HStack {
                Text(Keymaps.label(name))
                Spacer()
                ShortcutRecorder(current: map[name], suspend: model.suspend) { sc in
                    model.change { $0.shortcuts[name] = .some(sc) }
                }
                Button("Clear") { model.change { $0.shortcuts[name] = .some(nil) } }
                    .help("Turn this action's shortcut off.")
                Button("Reset") { model.change { $0.shortcuts[name] = nil } }
                    .help("Use the keymap's shortcut again.")
                    .disabled(model.choices.shortcuts[name] == nil)
            }
        }
    }

    // sizes edits the custom sizes: shares of the area, each with a shortcut.
    private var sizes: some View {
        let problems = Keymaps.sizes(model.choices.sizes.map(\.entry)).problems
        return VStack(alignment: .leading) {
            Text("Each size takes a share of the area: x and y place its top left corner, w and h set its size, "
                + "all from 0 to 1.").font(.callout)
            let n = model.choices.sizes.count
            List(model.choices.sizes.indices, id: \.self) { i in
                SizeRow(size: model.choices.sizes[i], shortcut: model.bindings.map[Keymaps.sizePrefix + model.choices.sizes[i].title],
                        suspend: model.suspend,
                        save: { s in model.change { if $0.sizes.still(i, of: n) { $0.sizes[i] = s } } },
                        delete: { model.change { if $0.sizes.still(i, of: n) { $0.sizes.remove(at: i) } } })
            }
            ForEach(problems, id: \.self) { Text($0).foregroundStyle(.red).font(.callout) }
            Button("Add size") {
                model.change { $0.sizes.append(StoredSize(title: "Size \($0.sizes.count + 1)", x: 0.25, y: 0, w: 0.5, h: 1)) }
            }
        }
    }

    // workspaces renames, ties and deletes the saved workspaces.
    private var workspaces: some View {
        let names = model.choices.workspaces.keys.sorted()
        return Form {
            Section("Workspaces") {
                if names.isEmpty {
                    Text("No workspaces yet. Save one from the Workspaces folder in the menu.").font(.callout)
                }
                ForEach(names, id: \.self) { name in
                    WorkspaceRow(name: name, tied: model.app.workspaces.tied(name),
                                 rename: { new in
                                     model.change {
                                         guard let ws = $0.workspaces.removeValue(forKey: name) else { return }
                                         var renamed = ws
                                         renamed.name = new
                                         $0.workspaces[new] = renamed
                                         for i in $0.profiles.indices {
                                             $0.profiles[i].workspaces = $0.profiles[i].workspaces.map { $0 == name ? new : $0 }
                                         }
                                     }
                                 },
                                 tie: { model.app.workspaces.tie(name); model.reload() },
                                 delete: { model.change {
                                     $0.workspaces[name] = nil
                                     for i in $0.profiles.indices { $0.profiles[i].workspaces.removeAll { $0 == name } }
                                 } })
                    if let ws = model.choices.workspaces[name] {
                        HStack {
                            Toggle("Open missing apps", isOn: Binding(
                                get: { !ws.windows.isEmpty && ws.windows.allSatisfy { $0.launchBundle != nil } },
                                set: { v in model.change {
                                    guard var w = $0.workspaces[name] else { return }
                                    for i in w.windows.indices {
                                        w.windows[i].launchBundle = v ? w.windows[i].bundle : nil
                                    }
                                    $0.workspaces[name] = w
                                } }))
                            Toggle("Recall on any display change", isOn: Binding(
                                get: { ws.recallOnDisplayChange },
                                set: { v in model.change { $0.workspaces[name]?.recallOnDisplayChange = v } }))
                        }
                        .toggleStyle(.checkbox)
                    }
                }
            }
            Section("App rules") {
                Text("A rule places an app's first window when it appears: when the app opens, or when it shows a "
                    + "window again after having none. Anchored apps keep their slots.")
                    .font(.callout).foregroundStyle(.secondary)
                ForEach(Array(model.choices.appRules.enumerated()), id: \.offset) { i, rule in
                    HStack {
                        Text(model.app.appName(rule.bundle))
                        Spacer()
                        Picker("", selection: Binding(get: { rule.action ?? "" }, set: { v in model.change {
                            guard $0.appRules.still(i, holding: rule) else { return }
                            $0.appRules[i].action = v.isEmpty ? nil : v
                            $0.appRules[i].frame = nil
                        } })) {
                            if rule.frame != nil {
                                Text("Saved frame").tag("")
                            }
                            ForEach(snapTargets, id: \.self) { Text(Keymaps.label($0)).tag($0) }
                        }
                        .frame(width: 220)
                        Button("Remove") { model.change { $0.appRules.remove(i, holding: rule) } }
                    }
                }
                Picker("Add a rule for", selection: Binding(get: { "" }, set: { b in
                    if !b.isEmpty { model.change { $0.appRules.append(AppRule(bundle: b, action: "center")) } }
                })) {
                    Text("Choose…").tag("")
                    ForEach(runningApps.filter { b in !model.choices.appRules.contains { $0.bundle == b } }, id: \.self) {
                        Text(model.app.appName($0)).tag($0)
                    }
                }
            }
            profiles(names)
        }
        .formStyle(.grouped)
    }

    // profiles lists the saved profiles, each with its name, shortcut, the workspaces it recalls in order,
    // and buttons to switch to it, save the current settings into it, or delete it.
    private func profiles(_ workspaces: [String]) -> some View {
        Section {
            ForEach(Array(model.choices.profiles.enumerated()), id: \.element.name) { i, p in
                VStack(alignment: .leading) {
                    HStack {
                        WorkspaceNameField(name: p.name) { new in
                            guard !model.choices.profiles.contains(where: { $0.name == new }) else { return }
                            model.change {
                                if $0.profiles.indices.contains(i), $0.profiles[i].name == p.name {
                                    $0.renameProfile(at: i, to: new)
                                }
                            }
                        }
                        if model.choices.activeProfile == p.name {
                            Text("Active").font(.callout).foregroundStyle(.secondary)
                        }
                        ShortcutRecorder(current: model.bindings.map[p.actionName], suspend: model.suspend) { sc in
                            model.change { $0.shortcuts[p.actionName] = .some(sc) }
                        }
                    }
                    HStack {
                        Text("Recalls").font(.callout)
                        ForEach(workspaces, id: \.self) { ws in
                            Toggle(ws, isOn: Binding(get: { p.workspaces.contains(ws) }, set: { on in model.change {
                                guard $0.profiles.indices.contains(i), $0.profiles[i].name == p.name else { return }
                                $0.profiles[i].workspaces.removeAll { $0 == ws }
                                if on { $0.profiles[i].workspaces.append(ws) }
                            } }))
                        }
                        if workspaces.isEmpty {
                            Text("no workspaces saved").font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        Button("Switch to it") { model.app.workspaces.applyProfile(p.name); model.reload() }
                        Button("Save current settings into it") { model.app.workspaces.saveProfile(p.name); model.reload() }
                        Button("Delete") { model.change {
                            $0.profiles.remove(at: i)
                            $0.shortcuts[p.actionName] = nil
                            $0.menu.order.removeAll { $0 == p.actionName }
                            if $0.activeProfile == p.name { $0.activeProfile = nil }
                        } }
                    }
                }
            }
            Button("Save current as profile…") {
                if let name = WorkspaceKeeper.askName("Save profile", "Name these settings. Switching to the profile later "
                    + "brings them back, and anchored apps stay where they are.") {
                    model.app.workspaces.saveProfile(name)
                    model.reload()
                }
            }
        } header: {
            Text("Profiles")
        } footer: {
            Text("A profile holds shortcuts, keymap, sizes, gap, snapping, behavior, stacking, chains, the menu, app "
                + "rules, mouse buttons, title bar clicks. Switching applies them and recalls the ticked "
                + "workspaces in the order they were ticked. Anchored apps and strip sizes stay.")
                .font(.callout)
        }
    }

    // stripsSection edits the strip widths and top row heights.
    private var stripsSection: some View {
        Section("Strips") {
            widthRow("Left width", .left)
            widthRow("Right width", .right)
            heightRow("Left top row", .left)
            heightRow("Right top row", .right)
        }
    }

    // presetsSection lists the saved width pairs and saves the current one.
    private var presetsSection: some View {
        Section("Saved width presets") {
            ForEach(Array(model.choices.widthPresets.enumerated()), id: \.offset) { i, w in
                HStack {
                    Text("Left \(Int(w.left))%, right \(Int(w.right))%")
                    Spacer()
                    Button("Remove") { model.change { $0.widthPresets.remove(i, holding: w) } }
                }
            }
            Button("Save current widths") {
                let w = model.app.anchors.widths
                model.change { if !$0.widthPresets.contains(w) { $0.widthPresets.append(w) } }
            }
        }
    }

    // widthRow edits one strip's width with a field, a stepper and the points it covers.
    private func widthRow(_ title: String, _ side: Side) -> some View {
        let anchors = model.app.anchors
        let w = anchors.widths
        let minPoints = anchors.minWidth(side)
        let screenWidth = Screens.current().wide?.w
        let pct = side == .left ? w.left : w.right
        let range = Layout.widthRange(w, side, minPoints: minPoints, screenWidth: screenWidth)
        let value = Binding(get: { pct }, set: { v in
            let next = Layout.clamped(w, side, v, minPoints: minPoints, screenWidth: screenWidth)
            model.change { $0.widths = next }
        })
        return VStack(alignment: .leading) {
            percentRow(title, value, range) {
                if let screenWidth {
                    Text("\(Int(Layout.points(pct, screenWidth: screenWidth))) pt").foregroundStyle(.secondary)
                }
            }
            if minPoints > 0 {
                let name = anchors.minBy[side].map { model.app.appName($0) } ?? "An app"
                let floorPct = Int(range.lowerBound)
                Text("\(name) needs \(Int(minPoints)) pt, so the \(side == .left ? "left" : "right") strip is "
                    + "at least \(floorPct)%.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    // heightRow edits one strip's top row height.
    private func heightRow(_ title: String, _ side: Side) -> some View {
        let h = model.app.anchors.heights
        let value = Binding(get: { h[side] }, set: { v in
            let top = Layout.clampedTop(v)
            model.change {
                var next = $0.heights ?? h
                next[side] = top
                $0.heights = next
            }
        })
        return percentRow(title, value, Layout.minRowPct...(100 - Layout.minRowPct)) { EmptyView() }
    }

    // percentRow draws a title, a whole-percent field, a percent sign, a stepper and trailing content.
    private func percentRow<T: View>(_ title: String, _ value: SwiftUI.Binding<Double>, _ range: ClosedRange<Double>,
                                     @ViewBuilder trailing: () -> T) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(title, value: value, format: .number.precision(.fractionLength(0)))
                .labelsHidden().multilineTextAlignment(.trailing).frame(width: 52)
            Text("%")
            Stepper("", value: value, in: range, step: 1).labelsHidden()
            trailing()
        }
    }

    // layout picks the keymap, snapping and the gap.
    private var layout: some View {
        Form {
            stripsSection
            Section("Adjust strips on screen") {
                HStack {
                    Text("Step, type or drag the strips on the display")
                    Spacer()
                    ShortcutRecorder(current: model.bindings.map[Keymaps.stripsName], suspend: model.suspend) { sc in
                        model.change { $0.shortcuts[Keymaps.stripsName] = .some(sc) }
                    }
                    Button("Clear") { model.change { $0.shortcuts[Keymaps.stripsName] = .some(nil) } }
                        .help("Turn this shortcut off.")
                    Button("Open") { model.app.strips.show() }
                }
            }
            presetsSection
            Picker("Keymap", selection: Binding(get: { model.choices.keymap },
                                                set: { v in model.change { $0.keymap = v; $0.shortcuts = [:] } })) {
                ForEach(Keymap.allCases, id: \.rawValue) { Text($0.rawValue.capitalized).tag($0.rawValue) }
            }
            Toggle("Snap windows by dragging", isOn: Binding(get: { model.choices.snap },
                                                              set: { v in model.change { $0.snap = v } }))
            Stepper(value: Binding(get: { model.choices.gapPx },
                                   set: { v in model.change { $0.gapPx = min(max(v, 0), Keymaps.maxGap) } }),
                    in: 0...Keymaps.maxGap, step: 2) {
                Text("Gap around windows: \(Int(model.choices.gapPx)) pt")
            }
            Section("Mouse buttons") {
                ForEach([(2, "Middle"), (3, "Back"), (4, "Forward"), (5, "Button 6")], id: \.0) { button, title in
                    Picker(title, selection: Binding(get: { model.choices.mouseButtons[String(button)] ?? "" },
                                                     set: { v in model.change { $0.mouseButtons[String(button)] = v.isEmpty ? nil : v } })) {
                        Text("Nothing").tag("")
                        ForEach(runNames, id: \.self) { Text(Keymaps.label($0)).tag($0) }
                    }
                }
            }
            Section("Title bar buttons") {
                ForEach([(WindowButton.red, "Red (close)"), (.yellow, "Yellow (minimize)"), (.green, "Green (zoom)")],
                        id: \.0) { button, title in
                    DisclosureGroup(title) {
                        ForEach([("", "Click"), ("shift", "Shift-click"), ("option", "Option-click"),
                                 ("command", "Command-click")], id: \.0) { modifier, label in
                            let key = ButtonClicks.key(button, modifier)
                            Picker(label, selection: Binding(get: { model.choices.buttonClicks[key] ?? "" },
                                                             set: { v in model.change { $0.buttonClicks[key] = v.isEmpty ? nil : v } })) {
                                Text("The button's own").tag("")
                                ForEach(runNames, id: \.self) { Text(Keymaps.label($0)).tag($0) }
                            }
                        }
                    }
                }
            }
            Toggle("Fullscreen fills the channel", isOn: Binding(get: { model.choices.fullscreenFills },
                                                                  set: { v in model.change { $0.fullscreenFills = v } }))
            Toggle("Fullscreen keeps anchored apps in their slots",
                   isOn: Binding(get: { model.choices.pinFullscreenFills },
                                 set: { v in model.change { $0.pinFullscreenFills = v } }))
        }
    }

    // snapAreas lists the drag snap areas with their titles, in reading order.
    private static let snapAreas = [
        ("top-left", "Top left corner"), ("top", "Top edge"), ("top-right", "Top right corner"),
        ("left", "Left edge"), ("right", "Right edge"),
        ("bottom-left", "Bottom left corner"), ("bottom", "Bottom edge"), ("bottom-right", "Bottom right corner"),
    ]

    // snapCompounds lists the area values that pick an action from where the cursor sits, with their titles.
    private static let snapCompounds = [
        ("side-halves", "Side half, or a top or bottom half near a corner"), ("maximize-halves", "Maximize, or a half near a corner"),
        ("thirds-halves", "Thirds, or a half near a corner"), ("top-sixths", "Top sixths"),
        ("bottom-sixths", "Bottom sixths"),
    ]

    // snapping edits the drag snap areas, the keys that must be held, the edge margins and the footprint.
    private var snapping: some View {
        let s = model.choices.snapping
        return Form {
            Text("On the ultrawide, the strips and the channel keep their own zones. The keys to hold still apply.")
                .font(.callout)
            areaSection("Landscape displays", \.landscapeSnapAreas)
            areaSection("Portrait displays", \.portraitSnapAreas)
            Section("Hold these keys to snap") {
                HStack {
                    ForEach(["shift", "control", "option", "command"], id: \.self) { key in
                        Toggle(key.capitalized, isOn: Binding(get: { s.snapModifiers.contains(key) },
                                                              set: { v in model.change {
                                                                  $0.snapping.snapModifiers.removeAll { $0 == key }
                                                                  if v { $0.snapping.snapModifiers.append(key) }
                                                              } }))
                        .toggleStyle(.checkbox)
                    }
                    Spacer()
                }
            }
            Section("Custom areas") {
                Text("A custom area is a part of a display, as shares from 0 to 1, that snaps a window dropped in it. "
                    + "Custom areas come before the edges and do not apply on the ultrawide.")
                    .font(.callout).foregroundStyle(.secondary)
                let n = s.customAreas.count
                ForEach(s.customAreas.indices, id: \.self) { i in
                    SnapAreaRow(area: s.customAreas[i], actions: snapTargets,
                                save: { a in model.change {
                                    if $0.snapping.customAreas.still(i, of: n) { $0.snapping.customAreas[i] = a }
                                } },
                                delete: { model.change {
                                    if $0.snapping.customAreas.still(i, of: n) { $0.snapping.customAreas.remove(at: i) }
                                } })
                }
                Button("Add area") {
                    model.change {
                        $0.snapping.customAreas.append(CustomSnapArea(x: 0.4, y: 0.4, w: 0.2, h: 0.2, action: "center"))
                    }
                }
            }
            Section("Snap panel") {
                Toggle("Pause while dragging to show a panel of targets near the pointer",
                       isOn: Binding(get: { s.snapPanel }, set: { v in model.change { $0.snapping.snapPanel = v } }))
                ForEach(Array(s.panelActions.enumerated()), id: \.offset) { i, name in
                    HStack {
                        Text(Keymaps.label(name))
                        Spacer()
                        Button("Left") { model.change { $0.snapping.panelActions.move(i, holding: name, to: i - 1) } }
                            .disabled(i == 0)
                        Button("Right") { model.change { $0.snapping.panelActions.move(i, holding: name, to: i + 1) } }
                            .disabled(i == s.panelActions.count - 1)
                        Button("Remove") { model.change { $0.snapping.panelActions.remove(i, holding: name) } }
                    }
                }
                adder("Add a target", snapTargets.filter { !s.panelActions.contains($0) }) { name in
                    model.change { $0.snapping.panelActions.append(name) }
                }
                Text("Drop the window on a target to apply it.").font(.callout).foregroundStyle(.secondary)
            }
            Section("Edges") {
                snapStepper("Snap before the edge", \.snapBeforeReachingEdges, 0...100, 5)
                snapStepper("Top margin", \.edgeMarginTop, 0...50, 1)
                snapStepper("Bottom margin", \.edgeMarginBottom, 0...50, 1)
                snapStepper("Left margin", \.edgeMarginLeft, 0...50, 1)
                snapStepper("Right margin", \.edgeMarginRight, 0...50, 1)
                snapStepper("Corner size", \.cornerSize, 0...300, 5)
                snapStepper("Half size on an edge", \.shortEdgeSize, 0...600, 5)
            }
            Section("Footprint") {
                Stepper(value: Binding(get: { s.footprint.alpha },
                                       set: { v in model.change { $0.snapping.footprint.alpha = min(max(v, 0), 1) } }),
                        in: 0...1, step: 0.05) {
                    Text("Fill opacity: \(Int((s.footprint.alpha * 100).rounded()))%")
                }
                snapStepper("Border width", \.footprint.borderWidth, 0...10, 1)
                TextField("Color, #rrggbb, empty for the default",
                          text: Binding(get: { s.footprint.color ?? "" },
                                        set: { v in model.change {
                                            let t = v.trimmingCharacters(in: .whitespaces)
                                            $0.snapping.footprint.color = t.isEmpty ? nil : t
                                        } }))
                if let c = s.footprint.color, RGB(hex: c) == nil {
                    Text("Not a #rrggbb color, so the default color is used.").foregroundStyle(.red).font(.callout)
                }
                Toggle("Fade in and out", isOn: Binding(get: { s.footprint.fade },
                                                        set: { v in model.change { $0.snapping.footprint.fade = v } }))
                Stepper(value: Binding(get: { s.footprint.animationSpeed },
                                       set: { v in model.change { $0.snapping.footprint.animationSpeed = min(max(v, 0), 5) } }),
                        in: 0...5, step: 0.5) {
                    Text("Fade time: \(s.footprint.animationSpeed == 0 ? "standard" : "\(s.footprint.animationSpeed)x")")
                }
                .disabled(!s.footprint.fade)
                Toggle("Tap the trackpad when the footprint moves",
                       isOn: Binding(get: { s.footprint.haptic },
                                     set: { v in model.change { $0.snapping.footprint.haptic = v } }))
            }
        }
        .formStyle(.grouped)
    }

    // repeatLabels names each choice for what a shortcut pressed again does.
    private static let repeatLabels: [(SubsequentExecution, String)] = [
        (.cycleSizes, "Cycle sizes"), (.traverseDisplays, "Move to the next display"), (.none, "Nothing more"),
        (.traverseAndCycle, "Move across displays, then cycle sizes"), (.cycleDisplays, "Cycle through displays"),
        (.cycleQuadrants, "Cycle corners"), (.switchSides, "Switch sides"),
    ]

    // enhancedUILabels names each way of handling apps whose Enhanced UI slows moves.
    private static let enhancedUILabels: [(EnhancedUIMode, String)] = [
        (.automatic, "Automatic"), (.disableEnable, "Turn off while moving, then back on"),
        (.disableOnly, "Turn off while moving"), (.frontmostDisable, "Turn off when an app comes to the front"),
    ]

    // orderLabels names each way of numbering displays.
    private static let orderLabels: [(ScreenOrdering, String)] = [
        (.yThenMinX, "Top row first, then left to right"), (.minX, "By left edge"), (.midX, "By center"),
    ]

    // behavior edits how actions behave: repeat presses, sizes, gaps, the pointer, title bars and displays.
    private var behavior: some View {
        let b = model.choices.behavior
        return Form {
            Section("Pressed again") {
                Picker("A shortcut pressed again", selection: Binding(
                    get: { b.subsequentExecution }, set: { v in model.change { $0.behavior.subsequentExecution = v } })) {
                    ForEach(Self.repeatLabels, id: \.0) { Text($0.1).tag($0.0) }
                }
                behaviorToggle("Maximize pressed again restores the window", \.repeatedMaximizeRestores)
                behaviorToggle("Center half cycles sizes like the sides", \.centerHalfCycles)
                behaviorToggle("Halves keep the window's size on the other axis", \.halvesPreserveOtherAxis)
            }
            Section("Sizes") {
                behaviorShare("Smallest width when shrinking", \.minimumWindowWidth)
                behaviorShare("Smallest height when shrinking", \.minimumWindowHeight)
                behaviorStepper("Specified width", \.specifiedWidth, 100...10000, 10)
                behaviorStepper("Specified height", \.specifiedHeight, 100...10000, 10)
            }
            Section("Screen edge gaps") {
                behaviorStepper("Top", \.screenEdgeGapTop, 0...200, 1)
                behaviorStepper("Bottom", \.screenEdgeGapBottom, 0...200, 1)
                behaviorStepper("Left", \.screenEdgeGapLeft, 0...200, 1)
                behaviorStepper("Right", \.screenEdgeGapRight, 0...200, 1)
                Stepper(value: Binding(get: { b.screenEdgeGapTopNotch },
                                       set: { v in model.change { $0.behavior.screenEdgeGapTopNotch = min(max(v, -1), 200) } }),
                        in: -1...200, step: 1) {
                    Text("Top on a display with a notch: "
                        + (b.screenEdgeGapTopNotch < 0 ? "same as top" : "\(Int(b.screenEdgeGapTopNotch)) pt"))
                }
                behaviorToggle("Gaps on the main display only", \.gapsOnMainOnly)
                behaviorToggle("Gaps apply to maximize", \.applyGapsToMaximize)
            }
            Section("Pointer and title bar") {
                behaviorToggle("Move the pointer with the window", \.moveCursor)
                behaviorToggle("Dragging a snapped window gives back its size", \.unsnapRestore)
                behaviorToggle("Double-click a title bar to maximize", \.doubleClickTitleBar)
                TextField("Apps the double-click leaves alone, bundle IDs, comma separated",
                          text: Binding(get: { b.doubleClickIgnoredApps.joined(separator: ", ") },
                                        set: { v in model.change {
                                            $0.behavior.doubleClickIgnoredApps = v.split(separator: ",")
                                                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                                        } }))
                    .disabled(!b.doubleClickTitleBar)
                Text("The double-click only acts when macOS is set to do nothing on a title bar double-click.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Displays and apps") {
                Picker("Number displays", selection: Binding(
                    get: { b.screensOrderedByX }, set: { v in model.change { $0.behavior.screensOrderedByX = v } })) {
                    ForEach(Self.orderLabels, id: \.0) { Text($0.1).tag($0.0) }
                }
                Picker("Enhanced UI", selection: Binding(
                    get: { b.enhancedUI }, set: { v in model.change { $0.behavior.enhancedUI = v } })) {
                    ForEach(Self.enhancedUILabels, id: \.0) { Text($0.1).tag($0.0) }
                }
                behaviorToggle("Always leave room for the Stage Manager strip", \.alwaysAccountForStage)
                behaviorStepper("Stage Manager strip width", \.stageSize, 0...600, 10)
                behaviorToggle("Hide the menu bar icon", \.hideMenuBarIcon)
                behaviorToggle("Animate window moves (experimental)", \.animate)
            }
            Section("Stacked windows") {
                Toggle("A slot holds all of an app's windows",
                       isOn: Binding(get: { model.choices.slotStacks },
                                     set: { v in model.change { $0.slotStacks = v } }))
                Toggle("Show how many windows are stacked when the pointer rests at a window's corner",
                       isOn: Binding(get: { model.choices.stacking.badge },
                                     set: { v in model.change { $0.stacking.badge = v } }))
                Toggle("Stack and cycle only windows of the same size",
                       isOn: Binding(get: { model.choices.stacking.sameSizeOnly },
                                     set: { v in model.change { $0.stacking.sameSizeOnly = v } }))
            }
            Section("Throw with a held key") {
                Picker("Hold to throw", selection: Binding(
                    get: { model.choices.overlay.trigger }, set: { v in model.change { $0.overlay.trigger = v } })) {
                    ForEach(OverlayTrigger.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Stepper(value: Binding(get: { model.choices.overlay.gridColumns },
                                       set: { v in model.change { $0.overlay.gridColumns = v } }),
                        in: OverlayChoices.gridRange) {
                    Text("Grid columns: \(model.choices.overlay.gridColumns)")
                }
                Stepper(value: Binding(get: { model.choices.overlay.gridRows },
                                       set: { v in model.change { $0.overlay.gridRows = v } }),
                        in: OverlayChoices.gridRange) {
                    Text("Grid rows: \(model.choices.overlay.gridRows)")
                }
                Text("While the key is held, move the pointer toward a half, a corner or an edge and let go to send "
                    + "the window under the pointer there. Go farther for thirds, sixths, maximize and center. Arrow "
                    + "keys pick cells on the grid instead, Shift-arrows grow the pick, and Return or letting go "
                    + "applies it. Escape cancels. While the key is held, its arrow, Return and Escape keys go to "
                    + "Moorings.")
                    .font(.callout).foregroundStyle(.secondary)
                if model.choices.overlay.triggerMeetsTiling {
                    optionTilingNote
                }
                if model.choices.overlay.gridMeetsSpaces {
                    Text("Under Right Control the grid's arrow keys do not reach Moorings, because macOS keeps "
                        + "Control-arrow keys for Mission Control and Spaces. Moving the pointer still throws. Pick "
                        + "Right Option or Right Command to use the grid.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            Section("Move and resize by hovering") {
                hoverKeys("Move with", \.hoverMove)
                hoverKeys("Resize with", \.hoverResize)
                Text("Hold these keys and move the pointer, no click needed, to move the window under the pointer, "
                    + "or to resize it from its nearest corner. Pick at least Control, Option or Command, and give "
                    + "resize a different set from move, such as the same keys plus Shift. Anchored windows stay put.")
                    .font(.callout).foregroundStyle(.secondary)
                if model.choices.overlay.hoverMeetsTiling {
                    optionTilingNote
                }
                hoverKeys("Shared edge with", \.edgeResize)
                Text("Hold these keys and drag the edge two side by side windows share to resize both at once.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // optionTilingNote warns that macOS tiles a window dragged with Option held and names the switch
    // that turns it off.
    private var optionTilingNote: some View {
        Text("Hold Option with no mouse button down. Dragging a window while Option is held starts macOS "
            + "tiling instead. To turn that off, open System Settings > Desktop & Dock and switch off "
            + "\u{201C}Hold \u{2325} key while dragging windows to tile.\u{201D}")
            .font(.callout).foregroundStyle(.secondary)
    }

    // hoverKeys shows a checkbox per modifier for the hover modifier set at path.
    private func hoverKeys(_ title: String, _ path: WritableKeyPath<OverlayChoices, [Modifier]>) -> some View {
        HStack {
            Text(title)
            Spacer()
            ForEach(Modifier.allCases, id: \.self) { m in
                Toggle(m.word, isOn: Binding(get: { model.choices.overlay[keyPath: path].contains(m) },
                                             set: { v in model.change {
                                                 var mods = Set($0.overlay[keyPath: path])
                                                 if v { mods.insert(m) } else { mods.remove(m) }
                                                 $0.overlay[keyPath: path] = mods.sorted()
                                             } }))
                    .toggleStyle(.checkbox)
            }
        }
    }

    // behaviorToggle switches the behavior choice at path.
    private func behaviorToggle(_ title: String, _ path: WritableKeyPath<Behaviors, Bool>) -> some View {
        Toggle(title, isOn: Binding(get: { model.choices.behavior[keyPath: path] },
                                    set: { v in model.change { $0.behavior[keyPath: path] = v } }))
    }

    // behaviorStepper edits the behavior choice at path in points, clamped to range.
    private func behaviorStepper(_ title: String, _ path: WritableKeyPath<Behaviors, Double>, _ range: ClosedRange<Double>,
                                 _ step: Double) -> some View {
        Stepper(value: Binding(get: { model.choices.behavior[keyPath: path] },
                               set: { v in model.change { $0.behavior[keyPath: path] = min(max(v, range.lowerBound), range.upperBound) } }),
                in: range, step: step) {
            Text("\(title): \(Int(model.choices.behavior[keyPath: path])) pt")
        }
    }

    // behaviorShare edits the behavior choice at path as a share of the area, in steps of 5%.
    private func behaviorShare(_ title: String, _ path: WritableKeyPath<Behaviors, Double>) -> some View {
        Stepper(value: Binding(get: { model.choices.behavior[keyPath: path] },
                               set: { v in model.change { $0.behavior[keyPath: path] = min(max(v, 0.05), 1) } }),
                in: 0.05...1, step: 0.05) {
            Text("\(title): \(Int((model.choices.behavior[keyPath: path] * 100).rounded()))%")
        }
    }

    // runningApps lists the bundle IDs of the running apps that show in the Dock, sorted.
    private var runningApps: [String] {
        Set(NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
            .compactMap(\.bundleIdentifier)).subtracting(["com.dcadolph.moorings"]).sorted()
    }

    // snapTargets lists the actions a custom snap area can take.
    private var snapTargets: [String] {
        actionNames.filter(ActionRunner.placesFrame)
            + model.bindings.sizes.map(\.name)
    }

    // areaSection picks the action for each snap area in the map at path, and whether the area never snaps.
    private func areaSection(_ title: String, _ path: WritableKeyPath<SnapChoices, [String: String]>) -> some View {
        Section(title) {
            ForEach(Self.snapAreas, id: \.0) { area, label in
                HStack {
                    Picker(label, selection: Binding(get: { model.choices.snapping[keyPath: path][area] ?? "" },
                                                     set: { v in model.change { $0.snapping[keyPath: path][area] = v } })) {
                        Text("Nothing").tag("")
                        ForEach(Self.snapCompounds, id: \.0) { Text($0.1).tag($0.0) }
                        ForEach(actionNames.filter(ActionRunner.placesFrame),
                                id: \.self) {
                            Text(Keymaps.label($0)).tag($0)
                        }
                    }
                    Toggle("Never", isOn: Binding(get: { model.choices.snapping.ignoredSnapAreas.contains(area) },
                                                  set: { v in model.change {
                                                      $0.snapping.ignoredSnapAreas.removeAll { $0 == area }
                                                      if v { $0.snapping.ignoredSnapAreas.append(area) }
                                                  } }))
                        .help("Never snap in this area on any display.")
                }
            }
        }
    }

    // snapStepper edits the snap choice at path in points, clamped to range.
    private func snapStepper(_ title: String, _ path: WritableKeyPath<SnapChoices, Double>, _ range: ClosedRange<Double>,
                             _ step: Double) -> some View {
        Stepper(value: Binding(get: { model.choices.snapping[keyPath: path] },
                               set: { v in model.change { $0.snapping[keyPath: path] = min(max(v, range.lowerBound), range.upperBound) } }),
                in: range, step: step) {
            Text("\(title): \(Int(model.choices.snapping[keyPath: path])) pt")
        }
    }

    // menu edits the Window folder: the actions pinned to its top, the hidden ones, and the chains.
    private var menu: some View {
        let m = model.choices.menu
        let chains = model.choices.chains
        let extra = Set(model.bindings.sizes.map(\.name))
        let problems = chains.flatMap { $0.validate(extra: extra) }
        return Form {
            Section("Menu at the pointer") {
                HStack {
                    Text("Open the Moorings menu under the pointer")
                    Spacer()
                    ShortcutRecorder(current: model.bindings.map[Keymaps.menuName], suspend: model.suspend) { sc in
                        model.change { $0.shortcuts[Keymaps.menuName] = .some(sc) }
                    }
                    Button("Clear") { model.change { $0.shortcuts[Keymaps.menuName] = .some(nil) } }
                        .help("Turn this shortcut off.")
                }
            }
            Section("Pinned to the top of the Window folder") {
                ForEach(Array(m.order.enumerated()), id: \.offset) { i, name in
                    HStack {
                        Text(Keymaps.label(name))
                        Spacer()
                        Button("Up") { model.change { $0.menu.order.move(i, holding: name, to: i - 1) } }
                            .disabled(i == 0)
                        Button("Down") { model.change { $0.menu.order.move(i, holding: name, to: i + 1) } }
                            .disabled(i == m.order.count - 1)
                        Button("Remove") { model.change { $0.menu.order.remove(i, holding: name) } }
                    }
                }
                adder("Pin an action", runNames.filter { $0 != Keymaps.menuName && $0 != Keymaps.stripsName && !m.order.contains($0) }) { name in
                    model.change { $0.menu.order.append(name) }
                }
            }
            Section("Hidden from the Window folder") {
                ForEach(m.hidden, id: \.self) { name in
                    HStack {
                        Text(Keymaps.label(name))
                        Spacer()
                        Button("Show") { model.change { $0.menu.hidden.removeAll { $0 == name } } }
                    }
                }
                adder("Hide an action", (actionNames + model.bindings.sizes.map(\.name)).filter { !m.hidden.contains($0) }) { name in
                    model.change { $0.menu.hidden.append(name) }
                }
            }
            Section("Chains") {
                Text("A chain runs one step per press on the same window. Give it a shortcut in the Shortcuts tab.")
                    .font(.callout)
                let n = chains.count
                ForEach(chains.indices, id: \.self) { i in
                    ChainRow(chain: chains[i], steps: actionNames + model.bindings.sizes.map(\.name),
                             save: { c in model.change { if $0.chains.still(i, of: n) { $0.chains[i] = c } } },
                             rename: { new in model.change {
                                 if $0.chains.still(i, of: n) { $0.renameChain(at: i, to: new) }
                             } },
                             delete: { model.change { if $0.chains.still(i, of: n) { $0.chains.remove(at: i) } } })
                }
                ForEach(problems, id: \.self) { Text($0).foregroundStyle(.red).font(.callout) }
                Button("Add chain") {
                    model.change { $0.chains.append(Chain(name: "Chain \($0.chains.count + 1)")) }
                }
            }
        }
        .formStyle(.grouped)
    }

    // adder is a picker that hands the chosen action name to add and then shows its prompt again.
    private func adder(_ prompt: String, _ names: [String], add: @escaping (String) -> Void) -> some View {
        Picker(prompt, selection: Binding(get: { "" }, set: { v in if !v.isEmpty { add(v) } })) {
            Text("Choose…").tag("")
            ForEach(names, id: \.self) { Text(Keymaps.label($0)).tag($0) }
        }
    }

    // general holds launch at login, the update check, export and import, and the Rectangle import.
    private var general: some View {
        Form {
            Toggle("Launch at login", isOn: Binding(get: { model.app.launchAtLogin },
                                                    set: { v in model.app.setLaunchAtLogin(v); model.reload() }))
            Toggle("Check for updates every few hours", isOn: Binding(get: { model.choices.checkUpdates },
                                                                 set: { v in model.change { $0.checkUpdates = v } }))
            HStack {
                Button("Export settings…") { model.exportSettings() }
                Button("Import settings…") { model.importSettings() }
            }
            Button("Import from Rectangle…") { model.importRectangle() }
            if !model.message.isEmpty {
                Text(model.message).font(.callout)
            }
        }
    }
}

// SizeRow edits one custom size.
struct SizeRow: View {
    // size is the size as saved.
    let size: StoredSize
    // shortcut is the size's shortcut in effect.
    let shortcut: Shortcut?
    // suspend turns the window shortcuts off while recording.
    let suspend: (Bool) -> Void
    // save stores an edited size.
    let save: (StoredSize) -> Void
    // delete removes the size.
    let delete: () -> Void

    // body shows the title, the four shares, the recorder and Delete.
    var body: some View {
        HStack {
            TextField("Title", text: Binding(get: { size.title }, set: { var s = size; s.title = $0; save(s) }))
                .frame(width: 110)
            share("x", \.x)
            share("y", \.y)
            share("w", \.w)
            share("h", \.h)
            ShortcutRecorder(current: shortcut, suspend: suspend) { sc in
                var s = size
                s.shortcut = sc
                save(s)
            }
            Button("Delete", action: delete)
        }
    }

    // share edits one share of the size.
    private func share(_ label: String, _ path: WritableKeyPath<StoredSize, Double?>) -> some View {
        TextField(label, value: Binding(get: { size[keyPath: path] }, set: { var s = size; s[keyPath: path] = $0; save(s) }),
                  format: .number)
            .frame(width: 48)
    }
}

// SnapAreaRow edits one custom snap area: its four shares, its action and Delete.
struct SnapAreaRow: View {
    // area is the area as saved.
    let area: CustomSnapArea
    // actions lists the actions the area can take.
    let actions: [String]
    // save stores an edited area.
    let save: (CustomSnapArea) -> Void
    // delete removes the area.
    let delete: () -> Void

    // body shows the shares, the action picker and Delete.
    var body: some View {
        HStack {
            share("x", \.x)
            share("y", \.y)
            share("w", \.w)
            share("h", \.h)
            Picker("", selection: Binding(get: { area.action }, set: { var a = area; a.action = $0; save(a) })) {
                Text("Nothing").tag("")
                ForEach(actions, id: \.self) { Text(Keymaps.label($0)).tag($0) }
            }
            Button("Delete", action: delete)
        }
    }

    // share edits one share of the area, clamped from 0 to 1.
    private func share(_ label: String, _ path: WritableKeyPath<CustomSnapArea, Double>) -> some View {
        TextField(label, value: Binding(get: { area[keyPath: path] },
                                        set: { var a = area; a[keyPath: path] = min(max($0, 0), 1); save(a) }),
                  format: .number)
            .frame(width: 48)
    }
}

// WorkspaceRow renames, ties and deletes one workspace.
struct WorkspaceRow: View {
    // name is the workspace's name.
    let name: String
    // tied reports whether it comes back with the displays attached now.
    let tied: Bool
    // rename stores a new name.
    let rename: (String) -> Void
    // tie ties or unties it to the displays attached now.
    let tie: () -> Void
    // delete forgets it.
    let delete: () -> Void

    // body shows the name field, the tie switch and Delete.
    var body: some View {
        HStack {
            WorkspaceNameField(name: name, rename: rename)
            Toggle("With these displays", isOn: Binding(get: { tied }, set: { _ in tie() }))
            Button("Delete", action: delete)
        }
    }
}

// ChainRow edits one chain: its name, whether it loops, and its steps.
struct ChainRow: View {
    // chain is the chain as saved.
    let chain: Chain
    // steps lists the action names a step may run.
    let steps: [String]
    // save stores the edited chain.
    let save: (Chain) -> Void
    // rename stores a new name.
    let rename: (String) -> Void
    // delete removes the chain.
    let delete: () -> Void

    // draft is the name being typed.
    @State private var draft = ""

    // body shows the name field, the loop switch, each step and a picker to add one.
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                TextField("Name", text: $draft)
                    .onAppear { draft = chain.name }
                    .onSubmit {
                        let new = draft.trimmingCharacters(in: .whitespaces)
                        if !new.isEmpty && new != chain.name {
                            rename(new)
                        }
                    }
                Toggle("Loop", isOn: Binding(get: { chain.loops }, set: { var c = chain; c.loops = $0; save(c) }))
                    .help("After the last step, the next press starts over.")
                Button("Delete", action: delete)
            }
            ForEach(Array(chain.steps.enumerated()), id: \.offset) { i, step in
                HStack {
                    Text("\(i + 1). \(Keymaps.label(step))")
                    Spacer()
                    Button("Remove") { var c = chain; c.steps.remove(at: i); save(c) }
                }
            }
            Picker("Add step", selection: Binding(get: { "" }, set: { v in
                if !v.isEmpty { var c = chain; c.steps.append(v); save(c) }
            })) {
                Text("Choose…").tag("")
                ForEach(steps, id: \.self) { Text(Keymaps.label($0)).tag($0) }
            }
        }
    }
}

// WorkspaceNameField edits a saved name and stores it on Return when it changed and is not empty.
struct WorkspaceNameField: View {
    // name is the name as saved.
    let name: String
    // rename stores a new name.
    let rename: (String) -> Void

    // draft is the name being typed.
    @State private var draft = ""

    // body shows the field.
    var body: some View {
        TextField("Name", text: $draft)
            .onAppear { draft = name }
            .onSubmit {
                let new = draft.trimmingCharacters(in: .whitespaces)
                if !new.isEmpty && new != name {
                    rename(new)
                }
            }
    }
}
