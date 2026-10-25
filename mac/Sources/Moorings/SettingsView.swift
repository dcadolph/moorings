import SwiftUI

import MooringsCore

// SettingsView is the settings window's content: shortcuts, sizes, workspaces, layout, snapping, behavior,
// menu, appearance and general choices.
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
            Text("Shortcuts, snapping, appearance and behavior go back to their defaults. Anchored apps, strip "
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
            appearance.tabItem { Label("Appearance", systemImage: "paintpalette") }
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
        actionNames + [Keymaps.menuName] + model.choices.chains.map(\.actionName)
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
            List(model.choices.sizes.indices, id: \.self) { i in
                SizeRow(size: model.choices.sizes[i], shortcut: model.bindings.map[Keymaps.sizePrefix + model.choices.sizes[i].title],
                        suspend: model.suspend,
                        save: { s in model.change { $0.sizes[i] = s } },
                        delete: { model.change { $0.sizes.remove(at: i) } })
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
                    WorkspaceRow(name: name, tied: model.app.organizer.tied(name),
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
                                 tie: { model.app.organizer.tie(name); model.reload() },
                                 delete: { model.change {
                                     $0.workspaces[name] = nil
                                     for i in $0.profiles.indices { $0.profiles[i].workspaces.removeAll { $0 == name } }
                                 } })
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
                            model.change { $0.renameProfile(at: i, to: new) }
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
                                $0.profiles[i].workspaces.removeAll { $0 == ws }
                                if on { $0.profiles[i].workspaces.append(ws) }
                            } }))
                        }
                        if workspaces.isEmpty {
                            Text("no workspaces saved").font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        Button("Switch to it") { model.app.organizer.applyProfile(p.name); model.reload() }
                        Button("Save current settings into it") { model.app.organizer.saveProfile(p.name); model.reload() }
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
                if let name = Organizer.askName("Save profile", "Name these settings. Switching to the profile later "
                    + "brings them back, and anchored apps stay where they are.") {
                    model.app.organizer.saveProfile(name)
                    model.reload()
                }
            }
        } header: {
            Text("Profiles")
        } footer: {
            Text("A profile holds shortcuts, keymap, sizes, gap, snapping, behavior, stacking, chains, the menu, app "
                + "rules, mouse buttons, title bar clicks and theme. Switching applies them and recalls the ticked "
                + "workspaces in the order they were ticked. Anchored apps and strip sizes stay.")
                .font(.callout)
        }
    }

    // layout picks the keymap, snapping and the gap.
    private var layout: some View {
        Form {
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
                TextField("Color, #rrggbb, empty for the theme",
                          text: Binding(get: { s.footprint.color ?? "" },
                                        set: { v in model.change {
                                            let t = v.trimmingCharacters(in: .whitespaces)
                                            $0.snapping.footprint.color = t.isEmpty ? nil : t
                                        } }))
                if let c = s.footprint.color, RGB(hex: c) == nil {
                    Text("Not a #rrggbb color, so the theme's accent is used.").foregroundStyle(.red).font(.callout)
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
            }
        }
        .formStyle(.grouped)
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

    // areaSection picks the action for each snap area in the map at path, and whether the area never snaps.
    private func areaSection(_ title: String, _ path: WritableKeyPath<SnapChoices, [String: String]>) -> some View {
        Section(title) {
            ForEach(Self.snapAreas, id: \.0) { area, label in
                HStack {
                    Picker(label, selection: Binding(get: { model.choices.snapping[keyPath: path][area] ?? "" },
                                                     set: { v in model.change { $0.snapping[keyPath: path][area] = v } })) {
                        Text("Nothing").tag("")
                        ForEach(Self.snapCompounds, id: \.0) { Text($0.1).tag($0.0) }
                        ForEach(actionNames.filter { !Keymaps.windowNames.contains($0) && !Actions.arrowNames.contains($0) },
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
                        Button("Up") { model.change { $0.menu.order.swapAt(i, i - 1) } }.disabled(i == 0)
                        Button("Down") { model.change { $0.menu.order.swapAt(i, i + 1) } }.disabled(i == m.order.count - 1)
                        Button("Remove") { model.change { _ = $0.menu.order.remove(at: i) } }
                    }
                }
                adder("Pin an action", runNames.filter { $0 != Keymaps.menuName && !m.order.contains($0) }) { name in
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
                ForEach(chains.indices, id: \.self) { i in
                    ChainRow(chain: chains[i], steps: actionNames + model.bindings.sizes.map(\.name),
                             save: { c in model.change { $0.chains[i] = c } },
                             rename: { new in model.change { $0.renameChain(at: i, to: new) } },
                             delete: { model.change { $0.chains.remove(at: i) } })
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

    // appearance picks the theme.
    private var appearance: some View {
        Form {
            Picker("Theme", selection: Binding(get: { model.choices.theme }, set: { v in model.change { $0.theme = v } })) {
                ForEach(ThemeName.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.radioGroup)
        }
    }

    // general holds launch at login, the update check, export and import, and the Rectangle import.
    private var general: some View {
        Form {
            Toggle("Launch at login", isOn: Binding(get: { model.app.launchAtLogin },
                                                    set: { v in model.app.setLaunchAtLogin(v); model.reload() }))
            Toggle("Check for updates once a day", isOn: Binding(get: { model.choices.checkUpdates },
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
