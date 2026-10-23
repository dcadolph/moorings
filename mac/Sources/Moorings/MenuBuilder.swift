import AppKit

import MooringsCore

// ActionItem is a menu item that runs a closure when chosen.
@MainActor
final class ActionItem: NSMenuItem {
    // run is what choosing the item does.
    private let run: @MainActor () -> Void

    // init builds an item with a title, a hover hint and an action.
    init(_ title: String, tip: String, checked: Bool = false, enabled: Bool = true, run: @escaping @MainActor () -> Void) {
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
    static let castTip = "Let this window cover the strips, even a pinned app. It stays free until you close it "
        + "or click again, then it returns to the channel."

    // app is the running app delegate.
    let app: AppDelegate

    // anchors is the layout the menu shows and changes.
    private var anchors: Anchors { app.anchors }

    // items returns the top-level entries.
    func items() -> [NSMenuItem] {
        var out: [NSMenuItem] = []
        if !app.windows.trusted {
            out.append(ActionItem("Grant Accessibility access",
                                  tip: "Moorings needs Accessibility access before it can move windows.") {
                let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
                _ = AXIsProcessTrustedWithOptions(options)
            })
            out.append(.separator())
        }
        let paused = anchors.choices.paused
        out.append(ActionItem(paused ? "⚓ Drop anchor (hold the layout)" : "⚓ Weigh anchor (let windows drift)",
                              tip: paused ? "Hold anchored apps in their slots and free windows in the channel again."
                                  : "Stop holding windows so you can arrange them freely.") {
            anchors.choices.paused.toggle()
            app.save()
        })
        out.append(ActionItem("Re-moor now", tip: "Put every anchored window back in its slot and every free window "
                + "in the channel, including windows left alone for fighting their place.", enabled: !paused) {
            anchors.remoorNow()
            app.wake()
            app.moor()
        })
        let screens = Screens.current()
        let scan = app.windows.scan(screens)
        let focused = scan.focused
        if let front = frontItem() {
            out.append(front)
        }
        out.append(castItem(focused, wide: screens.wide))
        out.append(.separator())
        out.append(folder("Anchored apps", anchoredItems(shows: Set(scan.windows.map(\.bundle)))))
        out.append(folder("Window", windowItems()))
        out.append(folder("Widths", widthItems(screens.wide)))
        out.append(folder("Heights", heightItems()))
        out.append(.separator())
        out.append(ActionItem("Launch at login", tip: "Open Moorings when you log in.", checked: app.launchAtLogin) {
            app.setLaunchAtLogin(!app.launchAtLogin)
        })
        out.append(ActionItem("Quit Moorings", tip: "Stop Moorings until you open it again from Applications or "
                + "next log in. Your slots, widths and heights are kept.") {
            NSApp.terminate(nil)
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
           let name = running.localizedName {
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
                app.save()
            }
        }
        let targets = SlotKey.allCases.map { key in
            let current = picks[key] ?? ""
            let tip = current.isEmpty ? "Anchor \(name) to this empty slot."
                : "Anchor \(name) here in place of \(appName(current))."
            return ActionItem(key.title, tip: tip) {
                anchors.assign(key, bundle)
                app.save()
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
            app.wake()
            app.moor()
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
    // apps and a file browser, then Unanchor all apps. shows holds the apps with a document window.
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
                    app.save()
                },
            ]
            if !current.isEmpty && !running.contains(current) {
                choices.append(ActionItem(appName(current), tip: "Anchored here but not running. Its first window "
                        + "will take the slot.", checked: true, enabled: false) {})
            }
            for entry in apps {
                choices.append(ActionItem(entry.name, tip: "Anchor this app to the slot and bring its window there.",
                                          checked: entry.bundle == current) {
                    lock(key, entry.bundle)
                })
            }
            choices.append(.separator())
            choices.append(ActionItem("Choose app…", tip: "Pick any app in Applications, running or not, and open it "
                    + "in this slot.") {
                chooseApp(key)
            })
            out.append(folder("\(key.title): \(appName(current))", choices))
        }
        out.append(ActionItem("Unanchor all apps", tip: "Empty every slot so no app is held. Weigh anchor pauses "
                + "instead.", enabled: picks.values.contains { !$0.isEmpty }) {
            anchors.clearSlots()
            app.save()
        })
        return out
    }

    // lock puts bundle in the slot key and opens it like a Dock click.
    private func lock(_ key: SlotKey, _ bundle: String) {
        anchors.lock(key, bundle, now: AppDelegate.now)
        app.save()
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

    // gapPresets lists the gaps in points the Gap folder offers.
    static let gapPresets: [Double] = [0, 4, 8, 12, 16]

    // windowItems builds the Window folder: a folder per action family, the custom sizes, the keymap,
    // the gap, and the switch that turns the shortcuts off in the front app. Each entry shows its
    // shortcut, so the menu doubles as the cheat sheet.
    private func windowItems() -> [NSMenuItem] {
        let bindings = Bindings(anchors.choices)
        let paused = anchors.choices.paused
        let entries = { (names: [String], hint: String?) -> [NSMenuItem] in
            names.map { name in
                var title = Keymaps.label(name)
                if let sc = bindings.map[name] {
                    title += "  " + sc.text
                }
                return ActionItem(title, tip: hint ?? ActionRunner.hints[name] ?? "", enabled: !paused) {
                    app.actions.run(name)
                } as NSMenuItem
            }
        }
        var out: [NSMenuItem] = []
        for fam in ActionRunner.families {
            if fam.groups.isEmpty {
                out.append(folder(fam.title, entries(fam.names, fam.hint)))
            } else {
                out.append(folder(fam.title, fam.groups.map { folder($0.title, entries($0.names, fam.hint)) }))
            }
        }
        var custom = entries(bindings.sizes.map(\.name), "Resize the front window to this size.")
        if custom.isEmpty {
            custom = [label("No custom sizes", tip: "Add sizes in Settings to list them here.")]
        }
        out.append(folder("Custom sizes", custom))
        out.append(.separator())
        out.append(folder("Keymap", Keymap.allCases.map { km in
            ActionItem(km.rawValue.capitalized, tip: "Use \(km.rawValue.capitalized)'s shortcuts for the window actions.",
                       checked: anchors.choices.keymap == km.rawValue) {
                anchors.choices.keymap = km.rawValue
                anchors.choices.shortcuts = [:]
                app.save()
            } as NSMenuItem
        }))
        out.append(folder("Gap", Self.gapPresets.map { px in
            ActionItem(px == 0 ? "No gap" : String(format: "%.0f pt", px),
                       tip: "Leave this many points around a window a window action places.",
                       checked: anchors.choices.gapPx == px) {
                anchors.choices.gapPx = px
                app.save()
            } as NSMenuItem
        }))
        if let front = NSWorkspace.shared.frontmostApplication, let bundle = front.bundleIdentifier,
           bundle != Bundle.main.bundleIdentifier {
            let name = front.localizedName ?? bundle
            let on = anchors.choices.ignores.contains(bundle)
            out.append(ActionItem("Ignore shortcuts in \(name)", tip: "Turn the window shortcuts off while \(name) is in "
                    + "front, so its own shortcuts work.", checked: on) {
                if on {
                    anchors.choices.ignores.removeAll { $0 == bundle }
                } else {
                    anchors.choices.ignores.append(bundle)
                }
                app.save()
            })
        }
        return out
    }

    // widthItems builds the Widths folder: the channel label, a label per empty side, the steppers
    // and the presets.
    private func widthItems(_ wide: Frame?) -> [NSMenuItem] {
        let w = anchors.widths
        let use = wide != nil ? anchors.inUse(wide) : w
        var out = [label(String(format: "Channel %.0f%%", 100 - use.left - use.right),
                         tip: "The share of the display left between the strips for free windows.")]
        for side in anchors.emptySides() {
            out.append(label("\(side == .left ? "Left" : "Right") side empty: part of the channel",
                             tip: "Nothing is anchored on this side, so free windows use it until an app is."))
        }
        for (title, side, delta) in [("Left wider", Side.left, 1.0), ("Left narrower", .left, -1),
                                     ("Right wider", .right, 1), ("Right narrower", .right, -1)] {
            let (next, ok) = Layout.stepped(w, side, delta * Layout.widthStep)
            out.append(ActionItem(title, tip: "Move the strip's inner edge by one percent of the display.", enabled: ok) {
                anchors.setWidths(next)
                app.save()
            })
        }
        for preset in Layout.presets {
            out.append(ActionItem(String(format: "Left %.0f%%, right %.0f%%", preset.left, preset.right),
                                  tip: "Set both strips to these shares of the display.", checked: preset == w) {
                anchors.setWidths(preset)
                app.save()
            })
        }
        return out
    }

    // heightItems builds the Heights folder: a label per side, the taller and shorter steppers, and
    // a folder of presets per side.
    private func heightItems() -> [NSMenuItem] {
        let h = anchors.heights
        var out: [NSMenuItem] = []
        for (name, side) in [("Left", Side.left), ("Right", .right)] {
            out.append(label(String(format: "%@ top %g%%, bottom %g%%", name, h[side], 100 - h[side]),
                             tip: "How this strip's height splits between its two rows."))
        }
        for (title, side, delta) in [("Left top taller", Side.left, Layout.heightStep),
                                     ("Left top shorter", .left, -Layout.heightStep),
                                     ("Right top taller", .right, Layout.heightStep),
                                     ("Right top shorter", .right, -Layout.heightStep)] {
            let (pct, ok) = Layout.topStepped(h, side, delta)
            out.append(ActionItem(title, tip: String(format: "Move the line between the top and bottom rows by %g "
                    + "percent.", Layout.heightStep), enabled: ok) {
                anchors.setTop(side, pct)
                app.save()
            })
        }
        for (name, side) in [("Left", Side.left), ("Right", .right)] {
            let presets = Layout.heightPresets.map { pct in
                ActionItem(String(format: "Top %.0f%%, bottom %.0f%%", pct, 100 - pct),
                           tip: "Split this strip's height between its rows at these shares.", checked: pct == h[side]) {
                    anchors.setTop(side, pct)
                    app.save()
                } as NSMenuItem
            }
            out.append(folder("\(name) side", presets))
        }
        return out
    }
}
