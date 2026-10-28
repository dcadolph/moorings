import AppKit

import MooringsCore
import MooringsEngine

// ActionItem is a menu item that runs a closure when chosen.
@MainActor
final class ActionItem: NSMenuItem {
    // run is what choosing the item does.
    private let run: @MainActor () -> Void

    // init builds an item with a title, a hover hint and an action.
    init(
        _ title: String, tip: String, checked: Bool = false, enabled: Bool = true, run: @escaping @MainActor () -> Void
    ) {
        self.run = run
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
        toolTip = tip
        state = checked ? .on : .off
        isEnabled = enabled
    }

    // init is unused: items are built in code.
    required init(coder: NSCoder) {
        fatalError("ActionItem is built in code")
    }

    // fire runs the item's action.
    @objc private func fire() {
        run()
    }
}

// MenuBuilder builds the menu bar menu from the current state: the anchor toggle, Re-moor now, the
// frontmost app's entry, Cast off, the Anchored apps, Widths and Heights folders, Launch at login
// and Quit.
@MainActor
struct MenuBuilder {
    // castTip is the hover hint on Cast off this window.
    static let castTip =
        "Let this window cover the strips, even a pinned app. It stays free until you close it "
        + "or click again, then it returns to the channel."

    // app is the running app delegate.
    let app: AppDelegate

    // anchors is the layout the menu shows and changes.
    private var anchors: Anchors { app.engine.anchors }

    // items returns the top-level entries.
    func items() -> [NSMenuItem] {
        var out: [NSMenuItem] = []
        if let update = app.update {
            out.append(
                ActionItem("Update available: \(update.tag)", tip: "Open the release page to download it.") {
                    NSWorkspace.shared.open(update.page)
                })
            out.append(.separator())
        }
        if !app.windows.trusted {
            out.append(
                ActionItem(
                    "⚠ Grant Accessibility access",
                    tip: "Moorings needs Accessibility access before it can move windows. This opens "
                        + "Privacy & Security."
                ) {
                    NSWorkspace.shared.open(AppDelegate.accessibilityPane)
                })
            out.append(.separator())
        }
        let paused = anchors.choices.paused
        out.append(
            ActionItem(
                paused ? "⚓ Drop anchor (hold the layout)" : "⚓ Weigh anchor (let windows drift)",
                tip: paused
                    ? "Hold anchored apps in their slots and free windows in the channel again."
                    : "Stop holding windows so you can arrange them freely."
            ) {
                anchors.choices.paused.toggle()
                app.engine.save()
            })
        out.append(
            ActionItem(
                "Re-moor now",
                tip: "Put every anchored window back in its slot and every free window "
                    + "in the channel, including windows left alone for fighting their place.", enabled: !paused
            ) {
                anchors.remoorNow()
                app.engine.wake()
                app.engine.moor()
            })
        let screens = Screens.current()
        let scan = app.windows.scan(screens)
        let focused = scan.focused
        if let front = frontItem() {
            out.append(front)
        }
        out.append(castItem(focused, wide: screens.wide))
        let pinned = scan.windows.filter { anchors.pinned($0) }
        for w in pinned where anchors.isReleased(w.id) {
            out.append(
                ActionItem(
                    "Re-moor \(appName(w.bundle))",
                    tip: "Put \(appName(w.bundle)) back in its slot. It was "
                        + "let go when you moved it by hand.", enabled: !paused
                ) {
                    anchors.remoor(w.id)
                    app.engine.wake()
                    app.engine.moor()
                })
        }
        out.append(.separator())
        out.append(folder("Anchored apps", anchoredItems(shows: Set(scan.windows.map(\.bundle)))))
        out.append(folder("Window", windowItems()))
        out.append(folder("Lift", liftItems(pinned)))
        out.append(folder("Workspaces", workspaceItems()))
        out.append(folder("Profiles", profileItems()))
        out.append(folder("Widths", widthItems(screens.wide)))
        out.append(folder("Heights", heightItems()))
        out.append(.separator())
        out.append(
            ActionItem(
                "Settings…",
                tip: "Shortcuts, custom sizes, workspaces, layout and settings "
                    + "export and import."
            ) {
                app.settings.show()
            })
        out.append(
            ActionItem("Launch at login", tip: "Open Moorings when you log in.", checked: app.launchAtLogin) {
                app.setLaunchAtLogin(!app.launchAtLogin)
            })
        out.append(
            ActionItem("Check for updates now", tip: "Ask GitHub for the latest release right away.") {
                app.checkUpdateNow()
            })
        out.append(
            ActionItem(
                "Check for updates automatically",
                tip: "Look for a new release every few hours and offer it here.",
                checked: anchors.choices.checkUpdates
            ) {
                anchors.choices.checkUpdates.toggle()
                app.engine.save()
            })
        out.append(.separator())
        if let tip = AppDelegate.supportURL {
            out.append(
                ActionItem("Tip the harbormaster…", tip: "Moorings is free. A tip keeps the harbor running.") {
                    NSWorkspace.shared.open(tip)
                })
        }
        out.append(
            ActionItem(
                "Quit Moorings",
                tip: "Stop Moorings until you open it again from Applications or "
                    + "next log in. Your slots, widths and heights are kept."
            ) {
                app.quit()
            })
        return out
    }

    // folder returns a submenu entry titled title holding items.
    private func folder(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu()
        for item in items {
            menu.addItem(item)
        }
        entry.submenu = menu
        return entry
    }

    // label returns a disabled entry that only informs.
    private func label(_ title: String, tip: String) -> NSMenuItem {
        ActionItem(title, tip: tip, enabled: false) {}
    }

    // appName returns the display name of the app with bundle, the bundle itself when not found.
    private func appName(_ bundle: String) -> String {
        if bundle.isEmpty {
            return "Empty"
        }
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first,
            let name = running.localizedName
        {
            return name
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else { return bundle }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    // frontItem builds the entry for the frontmost app, or nil when there is none: Unanchor while it
    // holds a slot, else Anchor with the four slots to pick from.
    private func frontItem() -> NSMenuItem? {
        guard let front = NSWorkspace.shared.frontmostApplication, let bundle = front.bundleIdentifier,
            bundle != Bundle.main.bundleIdentifier
        else { return nil }
        let picks = anchors.assignments()
        let name = front.localizedName ?? bundle
        let held = SlotKey.allCases.filter { picks[$0] == bundle }
        if !held.isEmpty {
            return ActionItem("Unanchor \(name)", tip: "Free the slot \(name) holds. Its window stays where it is.") {
                for key in held {
                    anchors.assign(key, "")
                }
                app.engine.save()
            }
        }
        let targets = SlotKey.allCases.map { key in
            let current = picks[key] ?? ""
            let tip =
                current.isEmpty
                ? "Anchor \(name) to this empty slot."
                : "Anchor \(name) here in place of \(appName(current))."
            return ActionItem(key.title, tip: tip) {
                anchors.assign(key, bundle)
                app.engine.save()
            } as NSMenuItem
        }
        return folder("Anchor \(name)", targets)
    }

    // castItem builds the Cast off entry for the focused window, checked while it is cast off and
    // disabled with the reason when it cannot be.
    private func castItem(_ focused: WindowInfo?, wide: Frame?) -> NSMenuItem {
        let on = focused.map { anchors.isCastOff($0.id) } ?? false
        let why = on ? nil : anchors.castReason(focused, ultrawide: wide)
        return ActionItem("Cast off this window", tip: why ?? Self.castTip, checked: on, enabled: why == nil) {
            anchors.toggleCastOff(focused, ultrawide: wide)
            app.engine.wake()
            app.engine.moor()
        }
    }

    // runningApps returns the running apps that can be anchored, sorted by name: Dock apps, and apps
    // in shows, which have no Dock icon but show a document window.
    private func runningApps(shows: Set<String>) -> [(bundle: String, name: String)] {
        var seen: Set<String> = []
        var out: [(bundle: String, name: String)] = []
        for running in NSWorkspace.shared.runningApplications {
            guard let bundle = running.bundleIdentifier, bundle != Bundle.main.bundleIdentifier,
                running.activationPolicy == .regular || shows.contains(bundle), seen.insert(bundle).inserted
            else { continue }
            out.append((bundle, running.localizedName ?? bundle))
        }
        return out.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // anchoredItems builds the Anchored apps folder: a row per slot that opens Empty, the running
    // apps and a file browser, then Unanchor all apps. A row names how many windows its slot holds
    // when it holds more than one. shows holds the apps with a document window.
    private func anchoredItems(shows: Set<String>) -> [NSMenuItem] {
        let picks = anchors.assignments()
        let apps = runningApps(shows: shows)
        let running = Set(apps.map(\.bundle))
        var out: [NSMenuItem] = []
        for key in SlotKey.allCases {
            let current = picks[key] ?? ""
            var choices: [NSMenuItem] = [
                ActionItem("Empty", tip: "Leave this slot free and open nothing.", checked: current.isEmpty) {
                    anchors.assign(key, "")
                    app.engine.save()
                }
            ]
            if !current.isEmpty && !running.contains(current) {
                choices.append(
                    ActionItem(
                        appName(current),
                        tip: "Anchored here but not running. Its first window "
                            + "will take the slot.", checked: true, enabled: false
                    ) {})
            }
            for entry in apps {
                choices.append(
                    ActionItem(
                        entry.name, tip: "Anchor this app to the slot and bring its window there.",
                        checked: entry.bundle == current
                    ) {
                        lock(key, entry.bundle)
                    })
            }
            choices.append(.separator())
            choices.append(
                ActionItem(
                    "Choose app…",
                    tip: "Pick any app in Applications, running or not, and open it "
                        + "in this slot."
                ) {
                    chooseApp(key)
                })
            let held = anchors.slotWindows(key).count
            out.append(folder("\(key.title): \(appName(current))" + (held > 1 ? " (\(held) windows)" : ""), choices))
        }
        out.append(
            ActionItem(
                "Unanchor all apps",
                tip: "Empty every slot so no app is held. Weigh anchor pauses "
                    + "instead.", enabled: picks.values.contains { !$0.isEmpty }
            ) {
                anchors.clearSlots()
                app.engine.save()
            })
        return out
    }

    // lock puts bundle in the slot key and opens it like a Dock click.
    private func lock(_ key: SlotKey, _ bundle: String) {
        anchors.lock(key, bundle, now: AppDelegate.now)
        app.engine.save()
        app.open(bundle, background: false)
    }

    // chooseApp asks for an app in Applications and locks it in the slot key.
    private func chooseApp(_ key: SlotKey) {
        let panel = NSOpenPanel()
        panel.title = "Choose an app to anchor"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let bundle = Bundle(url: url)?.bundleIdentifier, !bundle.isEmpty else {
            app.logger.notice("\(url.path, privacy: .public) is not an app with a bundle ID")
            return
        }
        lock(key, bundle)
    }

    // workspaceItems builds the Workspaces folder: Save workspace, then a folder per saved workspace
    // to recall, tie to the displays attached now, or delete it.
    private func workspaceItems() -> [NSMenuItem] {
        var out: [NSMenuItem] = [
            ActionItem(
                "Save workspace…",
                tip: "Save the slots, widths, heights and where each free "
                    + "window sits under a name."
            ) {
                if let name = NamePrompt.ask() {
                    app.engine.workspaces.saveWorkspace(name)
                }
            }
        ]
        let names = anchors.choices.workspaces.keys.sorted()
        if !names.isEmpty {
            out.append(.separator())
        }
        for name in names {
            let tied = app.engine.workspaces.tied(name)
            out.append(
                folder(
                    name,
                    [
                        ActionItem("Recall", tip: "Put this workspace's layout back.", enabled: !anchors.choices.paused)
                        {
                            app.engine.workspaces.recall(name)
                        },
                        ActionItem(
                            "Recall with these displays",
                            tip: "Recall this workspace whenever the displays attached now "
                                + "are plugged in.", checked: tied
                        ) {
                            app.engine.workspaces.tie(name)
                        },
                        ActionItem("Delete", tip: "Forget this workspace.") {
                            app.engine.workspaces.delete(name)
                        },
                    ]))
        }
        return out
    }

    // profileItems builds the Profiles folder: Save current as profile, then an entry per profile that
    // switches to it, checked on the active one.
    private func profileItems() -> [NSMenuItem] {
        var out: [NSMenuItem] = [
            ActionItem(
                "Save current as profile…",
                tip: "Save the shortcuts, snapping, behavior, "
                    + "menu and app rules under a name. Settings > Workspaces picks the workspaces it recalls."
            ) {
                if let name = NamePrompt.ask(
                    "Save profile",
                    "Name these settings. Switching to the profile later "
                        + "brings them back, and anchored apps stay where they are.")
                {
                    app.engine.workspaces.saveProfile(name)
                }
            }
        ]
        let profiles = anchors.choices.profiles
        if !profiles.isEmpty {
            out.append(.separator())
        }
        for p in profiles {
            out.append(
                ActionItem(
                    p.name, tip: "Switch to this profile.", checked: anchors.choices.activeProfile == p.name,
                    enabled: !anchors.choices.paused
                ) {
                    app.engine.workspaces.applyProfile(p.name)
                })
        }
        return out
    }

    // liftItems builds the Lift folder: an entry per pin with a window, checked while lifted, then
    // the two fullscreen switches.
    private func liftItems(_ pinned: [WindowInfo]) -> [NSMenuItem] {
        var out: [NSMenuItem] = pinned.map { w in
            ActionItem(
                appName(w.bundle),
                tip: "Lift this app over its strip and the channel, or lower it back. Its "
                    + "green button does the same.", checked: anchors.isLifted(w.id),
                enabled: !anchors.choices.paused
            ) {
                anchors.toggleLift(id: w.id)
                if anchors.isLifted(w.id) {
                    app.windows.raise(w.id)
                }
                app.engine.wake()
                app.engine.moor()
            }
        }
        if out.isEmpty {
            out.append(label("No anchored app has a window", tip: "Anchor an app to lift it here."))
        }
        out.append(.separator())
        out.append(
            ActionItem(
                "Fullscreen fills the channel",
                tip: "Turn native fullscreen on a free window into a "
                    + "channel fill, so the strips stay in view.", checked: anchors.choices.fullscreenFills
            ) {
                anchors.choices.fullscreenFills.toggle()
                app.engine.save()
            })
        out.append(
            ActionItem(
                "Fullscreen keeps anchored apps in their slots",
                tip: "Send an anchored app that goes "
                    + "native fullscreen back to its slot.", checked: anchors.choices.pinFullscreenFills
            ) {
                anchors.choices.pinFullscreenFills.toggle()
                app.engine.save()
            })
        return out
    }

    // gapPresets lists the gaps in points the Gap folder offers.
    static let gapPresets: [Double] = [0, 4, 8, 12, 16]

    // chainTip is the hover hint on every chain entry.
    static let chainTip =
        "Run the next step of this chain. Pressing it again on the same window runs the step "
        + "after."

    // windowItems builds the Window folder: the pinned actions, a folder per action family, the custom
    // sizes, the chains, the keymap, the gap, and the switch that turns the shortcuts off in the front
    // app. Each entry shows its shortcut, so the menu doubles as the cheat sheet. Hidden actions are
    // left out, and a folder left empty is dropped.
    private func windowItems() -> [NSMenuItem] {
        let bindings = Bindings(anchors.choices)
        let paused = anchors.choices.paused
        let menu = anchors.choices.menu
        let entry = { (name: String, hint: String?) -> NSMenuItem in
            var title = Keymaps.label(name)
            if let sc = bindings.map[name] {
                title += "  " + sc.text
            }
            return ActionItem(title, tip: hint ?? ActionRunner.hints[name] ?? "", enabled: !paused) {
                app.engine.actions.run(name)
            }
        }
        let entries = { (names: [String], hint: String?) -> [NSMenuItem] in
            menu.visible(names).map { entry($0, hint) }
        }
        var out: [NSMenuItem] = []
        let pinned = menu.pinned(app.engine.actions.runnable)
        if !pinned.isEmpty {
            out += pinned.map { entry($0, $0.hasPrefix(Chain.prefix) ? Self.chainTip : nil) }
            out.append(.separator())
        }
        for fam in ActionRunner.families {
            if fam.groups.isEmpty {
                let items = entries(fam.names, fam.hint)
                if !items.isEmpty {
                    out.append(folder(fam.title, items))
                }
            } else {
                let groups = fam.groups.compactMap { g -> NSMenuItem? in
                    let items = entries(g.names, fam.hint)
                    return items.isEmpty ? nil : folder(g.title, items)
                }
                if !groups.isEmpty {
                    out.append(folder(fam.title, groups))
                }
            }
        }
        var custom = entries(bindings.sizes.map(\.name), "Resize the front window to this size.")
        if custom.isEmpty {
            custom = [label("No custom sizes", tip: "Add sizes in Settings to list them here.")]
        }
        out.append(folder("Custom sizes", custom))
        var chains = entries(anchors.choices.chains.map(\.actionName), Self.chainTip)
        if chains.isEmpty {
            chains = [label("No chains", tip: "Add chains in Settings, Menu tab, to list them here.")]
        }
        out.append(folder("Chains", chains))
        var organize = entries(Tile.names, nil)
        organize.append(.separator())
        for n in Organizer.tidyCounts {
            organize.append(
                ActionItem(
                    "Tidy channel: \(n) front windows",
                    tip: "Line up the \(n) front-most free windows "
                        + "side by side in the channel, keeping their order.", enabled: !paused
                ) {
                    app.engine.organizer.tidy(n)
                })
        }
        organize.append(
            ActionItem(
                "Undo tidy",
                tip: "Put back every window a fill, tidy or window action moved, where it "
                    + "was before the first move.", enabled: !paused && anchors.canUndo
            ) {
                app.engine.organizer.undo()
            })
        out.append(folder("Organize", organize))
        var tiling = entries(
            Tiling.modeNames,
            "Keep the free windows of each display in this layout as windows come and go. "
                + "A window you drag floats until you choose a layout again.")
        let active = Keymaps.label(Tiling.modePrefix + anchors.choices.tiling.mode.rawValue)
        for item in tiling where item.title == active || item.title.hasPrefix(active + "  ") {
            item.state = .on
        }
        tiling.append(.separator())
        tiling += entries([Tiling.cycleName, "grow-main", "shrink-main"], nil)
        tiling += entries(Tiling.focusNames, "Bring the nearest window that way to the front.")
        tiling += entries(Tiling.swapNames, "Trade places with the nearest window that way. Anchored windows stay.")
        out.append(folder("Tiling", tiling))
        out.append(.separator())
        out.append(
            ActionItem(
                "Snap windows by dragging",
                tip: "Drag a window to a display edge or corner to snap it "
                    + "there. Hold Option over a strip on the ultrawide to anchor its app.",
                checked: anchors.choices.snap
            ) {
                anchors.choices.snap.toggle()
                app.engine.save()
            })
        out.append(
            folder(
                "Keymap",
                Keymap.allCases.map { km in
                    ActionItem(
                        km.rawValue.capitalized,
                        tip: "Use \(km.rawValue.capitalized)'s shortcuts for the window actions.",
                        checked: anchors.choices.keymap == km.rawValue
                    ) {
                        anchors.choices.keymap = km.rawValue
                        anchors.choices.shortcuts = [:]
                        app.engine.save()
                    } as NSMenuItem
                }))
        out.append(
            folder(
                "Gap",
                Self.gapPresets.map { px in
                    ActionItem(
                        px == 0 ? "No gap" : String(format: "%.0f pt", px),
                        tip: "Leave this many points around a window a window action places.",
                        checked: anchors.choices.gapPx == px
                    ) {
                        anchors.choices.gapPx = px
                        app.engine.save()
                    } as NSMenuItem
                }))
        if let front = NSWorkspace.shared.frontmostApplication, let bundle = front.bundleIdentifier,
            bundle != Bundle.main.bundleIdentifier
        {
            let name = front.localizedName ?? bundle
            let on = anchors.choices.ignores.contains(bundle)
            out.append(
                ActionItem(
                    "Ignore shortcuts in \(name)",
                    tip: "Turn the window shortcuts off while \(name) is in "
                        + "front, so its own shortcuts work.", checked: on
                ) {
                    if on {
                        anchors.choices.ignores.removeAll { $0 == bundle }
                    } else {
                        anchors.choices.ignores.append(bundle)
                    }
                    app.engine.save()
                })
        }
        return out
    }

    // widthItems builds the Widths folder: a status label for the shared display, a label per empty side and per
    // side held wider by its app, the Adjust strips action, and a Presets folder holding the built-in presets,
    // the saved presets and the save and remove actions.
    private func widthItems(_ wide: Frame?) -> [NSMenuItem] {
        let w = anchors.widths
        let use = wide != nil ? anchors.inUse(wide) : w
        var out = [
            label(
                String(
                    format: "Left %.0f%% · Channel %.0f%% · Right %.0f%%", use.left,
                    100 - use.left - use.right, use.right),
                tip: "How the display is shared right now.")
        ]
        for side in anchors.emptySides() {
            out.append(
                label(
                    "\(side == .left ? "Left" : "Right") side empty: part of the channel",
                    tip: "Nothing is anchored on this side, so free windows use it until an app is."))
        }
        for side in [Side.left, .right] where anchors.minWidth(side) > 0 && wide != nil {
            let name = anchors.minBy[side].map { appName($0) } ?? "An app"
            out.append(
                label(
                    String(
                        format: "%@ %.0f%% in use: %@ needs %.0f pt", side == .left ? "Left" : "Right",
                        side == .left ? use.left : use.right, name, anchors.minWidth(side)),
                    tip: "This app will not shrink to the chosen width, so its strip is wider."))
        }
        out.append(adjustStripsItem())
        let held = { (side: Side, pct: Double) -> Bool in
            guard let wide else { return false }
            return Layout.held(minPoints: anchors.minWidth(side), screenWidth: wide.w, pct: pct)
        }
        let presetItem = { (preset: Widths, tip: String) -> NSMenuItem in
            ActionItem(
                String(format: "Left %.0f%%, right %.0f%%", preset.left, preset.right), tip: tip,
                checked: preset == w, enabled: !held(.left, preset.left) && !held(.right, preset.right)
            ) {
                anchors.setWidths(preset)
                app.engine.save()
            }
        }
        var presets = Layout.presets.map { presetItem($0, "Set both strips to these shares of the display.") }
        let owned = anchors.choices.widthPresets
        if !owned.isEmpty {
            presets.append(.separator())
            presets += owned.map { presetItem($0, "Set both strips to this saved pair of shares.") }
        }
        presets.append(.separator())
        presets.append(
            ActionItem(
                "Save current as preset",
                tip: "Keep the current strip widths in this list for later.",
                enabled: !Layout.presets.contains(w) && !owned.contains(w)
            ) {
                anchors.choices.widthPresets.append(w)
                app.engine.save()
            })
        presets.append(
            ActionItem(
                "Remove current preset", tip: "Delete the current strip widths from the saved list.",
                enabled: owned.contains(w)
            ) {
                anchors.choices.widthPresets.removeAll { $0 == w }
                app.engine.save()
            })
        out.append(folder("Presets", presets))
        return out
    }

    // adjustStripsItem builds the action that opens the on-screen strip editor.
    private func adjustStripsItem() -> NSMenuItem {
        ActionItem(
            "Adjust strips…",
            tip: "Step, type or drag each strip's edge and row line on screen. "
                + "Windows follow as you go."
        ) {
            app.strips.show()
        }
    }

    // heightItems builds the Heights folder: the Adjust strips action, a label per side, the taller and
    // shorter steppers, and a folder of presets per side.
    private func heightItems() -> [NSMenuItem] {
        let h = anchors.heights
        var out: [NSMenuItem] = [adjustStripsItem()]
        for (name, side) in [("Left", Side.left), ("Right", .right)] {
            out.append(
                label(
                    String(format: "%@ top %g%%, bottom %g%%", name, h[side], 100 - h[side]),
                    tip: "How this strip's height splits between its two rows."))
        }
        for (title, side, delta) in [
            ("Left top taller", Side.left, Layout.heightStep),
            ("Left top shorter", .left, -Layout.heightStep),
            ("Right top taller", .right, Layout.heightStep),
            ("Right top shorter", .right, -Layout.heightStep),
        ] {
            let (pct, ok) = Layout.topStepped(h, side, delta)
            out.append(
                ActionItem(
                    title,
                    tip: String(
                        format: "Move the line between the top and bottom rows by %g "
                            + "percent.", Layout.heightStep), enabled: ok
                ) {
                    anchors.setTop(side, pct)
                    app.engine.save()
                })
        }
        for (name, side) in [("Left", Side.left), ("Right", .right)] {
            let presets = Layout.heightPresets.map { pct in
                ActionItem(
                    String(format: "Top %.0f%%, bottom %.0f%%", pct, 100 - pct),
                    tip: "Split this strip's height between its rows at these shares.", checked: pct == h[side]
                ) {
                    anchors.setTop(side, pct)
                    app.engine.save()
                } as NSMenuItem
            }
            out.append(folder("\(name) side", presets))
        }
        return out
    }
}
