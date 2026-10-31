import AppKit
import Carbon.HIToolbox
import os

import MooringsCore

// Selftest drives real Probe windows through the layout on the ultrawide and logs PASS or FAIL per
// check, then puts the owner's slots and anchor back and quits the probe. It runs from the
// moorings://selftest link. With apps=, a comma-separated list of bundle ids, it instead moves,
// resizes, snaps and restores a window of each named app and logs PASS or FAIL per app and case,
// or MIN when the app keeps a minimum size above the one asked.
@MainActor
final class Selftest {
    // bundle is the probe, the app the run makes throwaway windows in. make probe in mac/ builds it.
    static let bundle = "com.dcadolph.moorings.probe"
    // newWindow is the distributed notification that asks the probe for another window.
    static let newWindow = Notification.Name("com.dcadolph.moorings.probe.new-window")
    // landSeconds is how long a window may take to land.
    static let landSeconds = 3.0
    // holdSeconds is how long a window must stay put to count as steady.
    static let holdSeconds = 1.5
    // graceSeconds is how long after placing a pin before a move counts as by hand.
    static let graceSeconds = 2.5
    // openSeconds is how long the probe may take to show a window.
    static let openSeconds = 10.0
    // stepSeconds is how often a wait checks again.
    static let stepSeconds = 0.1
    // hang is the distributed notification that sleeps the probe's main thread.
    static let hang = Notification.Name("com.dcadolph.moorings.probe.hang")
    // hangSeconds is how long the probe hangs for the hung app check.
    static let hangSeconds = 6.0
    // hungSeconds is the most one call may take while an app is hung: two Accessibility timeouts.
    static let hungSeconds = 0.6
    // stallSeconds is how long the stall check blocks the main thread. The system turns a tap off when
    // its callback has not answered an event for about a second.
    static let stallSeconds = 2.0

    // Check is one result.
    struct Check {
        // name is what was checked.
        let name: String
        // ok reports whether it passed, nil when it was skipped.
        let ok: Bool?
        // detail says what was seen when it failed or why it was skipped.
        let detail: String
        // minimum reports whether it passed with the app keeping a minimum size above the one asked.
        var minimum = false
    }

    // Stop ends a run early with a reason.
    struct Stop: Error {
        // reason says why the run stopped.
        let reason: String
    }

    // app is the running app delegate.
    private unowned let app: AppDelegate
    // logger writes each result.
    private let logger = Logger(subsystem: "com.dcadolph.moorings", category: "selftest")
    // running reports whether a run is going.
    private var running = false
    // checks holds the results of the run.
    private var checks: [Check] = []
    // made lists the windows the run opened.
    private var made: [WindowID] = []
    // slot is the slot the probe borrows.
    private var slot: SlotKey = .leftTop
    // emptySide reports whether the probe's side has no other app.
    private var emptySide = false

    // init builds a selftest for app.
    init(app: AppDelegate) {
        self.app = app
    }

    // anchors is the layout under test.
    private var anchors: Anchors { app.engine.anchors }

    // start runs the selftest unless one is going, or the compatibility cases when apps names any.
    func start(apps: [String] = []) {
        guard !running else { return }
        running = true
        Task { @MainActor in
            if apps.isEmpty {
                await self.run()
            } else {
                await self.compatibility(apps)
            }
            self.running = false
        }
    }

    // compatibility runs the move, resize, snap and restore cases against a window of each app in
    // bundles and reports.
    private func compatibility(_ bundles: [String]) async {
        checks = []
        let why =
            !app.windows.trusted ? "Accessibility is not granted" : anchors.choices.paused ? "moorings is paused" : nil
        if let why {
            logger.notice("selftest not run: \(why, privacy: .public)")
            app.notify("Selftest not run", why + ".")
            return
        }
        for bundle in bundles {
            await compatible(bundle)
        }
        let failed = checks.filter { $0.ok == false }.count
        let skipped = checks.filter { $0.ok == nil }.count
        let kept = checks.filter(\.minimum).count
        let summary =
            "\(checks.count) checks on \(bundles.count) apps, \(failed) failed, \(skipped) skipped, "
            + "\(kept) kept an app minimum"
        logger.notice("selftest: \(summary, privacy: .public)")
        app.notify(failed == 0 ? "Selftest passed" : "Selftest failed", summary + ". The log has each check.")
    }

    // compatible runs the cases against the front free window of the app with bundle, opening the
    // app in the background when it is not running and quitting it after, and puts the window back
    // where it was.
    private func compatible(_ bundle: String) async {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else {
            skip(bundle, "not installed")
            return
        }
        let version = Bundle(url: url)?.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let tag = "\(bundle) \(version)"
        let launched = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).isEmpty
        if launched {
            app.open(bundle, background: true)
        }
        defer {
            if launched {
                NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first?.terminate()
            }
        }
        var found: WindowInfo?
        _ = await settled(
            {
                found = self.free(bundle); return (found != nil, "")
            }, Self.openSeconds)
        guard let w = found else {
            skip(tag, "no free window. Open one that is not anchored, fullscreen, stashed or a panel")
            return
        }
        let original = w.frame
        let area = app.engine.actions.area(for: w, screens: Screens.current())
        let moved = Frame(
            x: area.x + 60, y: area.y + 60, w: min(w.frame.w, area.w - 120), h: min(w.frame.h, area.h - 120))
        app.windows.move(w.id, to: moved)
        check("\(tag): move", await settled { self.at(w.id, moved) })

        let resized = Frame(x: area.x + 40, y: area.y + 40, w: min(900, area.w - 80), h: min(600, area.h - 80))
        let start = app.windows.frame(w.id) ?? moved
        app.windows.move(w.id, to: resized)
        let landed = await settled { self.at(w.id, resized) }
        if !landed.0, let got = app.windows.frame(w.id), Actions.keptMinimum(start: start, asked: resized, got: got) {
            app.windows.move(w.id, to: resized)
            try? await Task.sleep(for: .seconds(Self.stepSeconds * 5))
            if let again = app.windows.frame(w.id), Actions.near(again, got) {
                minimum("\(tag): resize", "kept \(Int(got.w))x\(Int(got.h)) for \(Int(resized.w))x\(Int(resized.h))")
            } else {
                check("\(tag): resize", (false, "stopped at \(got), then moved on a second set"))
            }
        } else {
            check("\(tag): resize", landed)
        }

        _ = anchors.restore(w.id)
        let before = app.windows.frame(w.id) ?? resized
        if let cur = info(w.id),
            let want = app.engine.actions.frame("left-half", for: cur, screens: Screens.current()).0
        {
            app.engine.actions.run("left-half", window: w.id)
            check("\(tag): snap left half", await settled { self.at(w.id, want) })
        } else {
            check("\(tag): snap left half", (false, "left half gave no frame"))
        }

        app.engine.actions.run("restore", window: w.id)
        check("\(tag): restore", await settled { self.at(w.id, before) })
        app.windows.move(w.id, to: original)
    }

    // free returns the front window of the app with bundle that moorings may move: not anchored,
    // fullscreen, stashed or a file panel.
    private func free(_ bundle: String) -> WindowInfo? {
        app.windows.scan(Screens.current()).windows.first {
            $0.bundle == bundle && !$0.isFilePanel && !$0.isFullScreen && !anchors.pinned($0)
                && !anchors.stashed.contains($0.id)
        }
    }

    // minimum records a check that passed with the app keeping a minimum size and logs what it kept.
    private func minimum(_ name: String, _ detail: String) {
        checks.append(Check(name: name, ok: true, detail: detail, minimum: true))
        logger.notice("MIN \(name, privacy: .public): \(detail, privacy: .public)")
    }

    // skip records a check that could not run and logs why.
    private func skip(_ name: String, _ why: String) {
        checks.append(Check(name: name, ok: nil, detail: why))
        logger.notice("SKIP \(name, privacy: .public): \(why, privacy: .public)")
    }

    // run prepares, runs the scenarios, cleans up and reports.
    private func run() async {
        checks = []
        made = []
        if let why = prepare() {
            logger.notice("selftest not run: \(why, privacy: .public)")
            app.notify("Selftest not run", why + ".")
            return
        }
        let saved = anchors.choices
        var stopped: String?
        do {
            try await scenarios()
        } catch let s as Stop {
            stopped = s.reason
        } catch {
            stopped = error.localizedDescription
        }
        for id in made {
            app.windows.close(id)
        }
        anchors.choices.slots = saved.slots
        anchors.choices.paused = saved.paused
        anchors.choices.appRules = saved.appRules
        anchors.choices.slotStacks = saved.slotStacks
        app.engine.save()
        await quitProbe()
        let failed = checks.filter { $0.ok == false }.count
        let summary = "\(checks.count) checks, \(failed) failed" + (stopped.map { ", stopped: \($0)" } ?? "")
        logger.notice("selftest: \(summary, privacy: .public)")
        app.notify(
            failed == 0 && stopped == nil ? "Selftest passed" : "Selftest failed", summary + ". The log has each check."
        )
    }

    // prepare picks the slot the probe borrows, preferring one on a side with no other app, and
    // returns why the run cannot start, nil when it can.
    private func prepare() -> String? {
        guard app.windows.trusted else { return "Accessibility is not granted" }
        guard Screens.current().wide != nil else { return "no ultrawide screen is attached" }
        if let why = Self.held(CGEventSource.flagsState(.combinedSessionState)) {
            return why
        }
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundle) != nil else {
            return "the probe is not installed. Run make probe in mac/ first"
        }
        let picks = anchors.assignments()
        if picks.values.contains(Self.bundle) {
            return "the probe is anchored. Take it out of Anchored apps first"
        }
        for wantEmpty in [true, false] {
            for key in SlotKey.allCases {
                let other = SlotKey.allCases.first { $0.side == key.side && $0 != key }!
                if picks[key] == "" && (picks[other] == "" || !wantEmpty) {
                    slot = key
                    emptySide = wantEmpty
                    return nil
                }
            }
        }
        return "every slot is taken. Empty one in Anchored apps first"
    }

    // held returns why a run cannot start while flags holds Shift, Control, Option or Command, nil
    // when it holds none. macOS reads a drag with a key the system thinks is down as that key's drag,
    // so a stuck Option would tile the dragged window.
    nonisolated static func held(_ flags: CGEventFlags) -> String? {
        let keys: [(CGEventFlags, String)] = [
            (.maskShift, "Shift"), (.maskControl, "Control"), (.maskAlternate, "Option"), (.maskCommand, "Command"),
        ]
        let names = keys.filter { flags.contains($0.0) }.map(\.1)
        guard !names.isEmpty else { return nil }
        return "The system reads \(names.joined(separator: " and ")) as held. Press and release "
            + (names.count == 1 ? "it" : "them") + ", then run again"
    }

    // scenarios runs the checks in the order selftest.lua does.
    private func scenarios() async throws {
        anchors.choices.paused = false
        anchors.assign(slot, Self.bundle)
        app.engine.save()
        let a = try await launch()
        check("anchored window lands in its slot", await settled { self.landed(a) })

        let stacks = anchors.choices.slotStacks
        anchors.choices.slotStacks = true
        let b = try await newDocument()
        check(
            "second window is held in the slot when the slot holds all windows",
            await settled { self.landed(b) })
        anchors.choices.slotStacks = false
        app.engine.wake()
        check(
            "second window goes to the channel when the slot holds one window",
            await settled { self.inChannel(b) })
        anchors.choices.slotStacks = stacks
        app.engine.wake()

        try await close(a)
        check("next window takes the slot when the anchored one closes", await settled { self.landed(b) })

        try await close(b)
        let freed = "an anchored app with no window frees its side"
        if emptySide, let wide = Screens.current().wide {
            check(
                freed,
                await settled {
                    let use = self.anchors.inUse(wide)
                    let pct = self.slot.side == .left ? use.left : use.right
                    return (pct == 0, String(format: "the side is still %.0f%% wide", pct))
                })
        } else {
            checks.append(Check(name: freed, ok: nil, detail: "another app shares the side"))
        }

        let picker = "open picker is not held"
        if let p = probe() {
            p.activate()
            key(kVK_ANSI_O, [.maskCommand], p.processIdentifier)
            var panel: WindowInfo?
            if await settled(
                {
                    panel = self.windows(panels: true).first; return (panel != nil, "")
                }, Self.openSeconds
            ).0,
                let panel
            {
                check(picker, await steady { (!self.anchors.pinned(self.info(panel.id) ?? panel), "anchored") })
                try await dismissPanels()
            } else {
                check(picker, (false, "the open picker did not show"))
            }
        }

        let c = try await newDocument()
        check("a new document takes the slot back", await settled { self.landed(c) })

        try await Task.sleep(for: .seconds(Self.graceSeconds))
        guard let wide = Screens.current().wide, let f = app.windows.frame(c) else {
            throw Stop(reason: "lost the window")
        }
        let ch = anchors.channel(wide)
        app.windows.move(c, to: Frame(x: ch.x + 40, y: ch.y + 40, w: min(f.w, ch.w - 80), h: f.h))
        let moved = app.windows.frame(c) ?? f
        check(
            "moving the anchored window releases it",
            await settled {
                (self.anchors.isReleased(c), "not released")
            })
        check("a released window stays where it was put", await steady { self.at(c, moved) })

        app.windows.raise(c)
        let green = "green button puts a released window back"
        if let w = info(c), let r = w.zoomRect {
            click(CGPoint(x: r.x + r.w / 2, y: r.y + r.h / 2))
            check(green, await settled { self.landed(c) })
        } else {
            check(green, (false, "the window reported no green button"))
        }

        try await Task.sleep(for: .seconds(Self.graceSeconds))
        guard let pinned = app.windows.frame(c) else { throw Stop(reason: "lost the window") }
        let grab = CGPoint(x: pinned.x + pinned.w / 2, y: pinned.y + 12)
        let drop = CGPoint(x: ch.x + ch.w / 2, y: ch.y + ch.h / 3)
        await drag(from: grab, to: drop)
        let dropped = app.windows.frame(c) ?? pinned
        check(
            "dragging the anchored window by its title bar releases it",
            await settled {
                (self.anchors.isReleased(c), "not released, at \(self.app.windows.frame(c) ?? pinned)")
            })
        check("a dragged window stays where it was dropped", await steady { self.at(c, dropped) })
        app.windows.raise(c)
        let greenDrag = "green button puts a dragged window back"
        if let w = info(c), let r = w.zoomRect {
            click(CGPoint(x: r.x + r.w / 2, y: r.y + r.h / 2))
            check(greenDrag, await settled { self.landed(c) })
        } else {
            check(greenDrag, (false, "the window reported no green button"))
        }

        anchors.choices.paused = true
        app.engine.save()
        app.windows.move(c, to: moved)
        let held = app.windows.frame(c) ?? moved
        check("pause leaves windows where they are", await steady { self.at(c, held) })
        anchors.choices.paused = false
        app.engine.save()
        check("resume puts the window back", await settled { self.landed(c) })

        let d = try await newDocument()
        let focusName = "focus next window brings the app's other window forward"
        let ids = windows(panels: false).map(\.id)
        if let want = Tile.neighbor(ids, of: d, forward: true) {
            app.engine.actions.run("focus-next-window")
            check(
                focusName,
                await settled {
                    let got = self.app.windows.scan(Screens.current()).focused?.id
                    return (got == want, "focused \(got.map(String.init) ?? "nothing"), want \(want)")
                })
        } else {
            check(focusName, (false, "the probe shows one window"))
        }

        let ruleName = "an app rule places the app's first window"
        anchors.choices.slots[slot] = nil
        app.engine.save()
        for id in made {
            try await close(id)
        }
        made = []
        let empty = await settled(
            { (self.windows(panels: false).isEmpty, "the probe still shows a window") },
            Self.openSeconds)
        guard empty.0 else {
            check(ruleName, empty)
            return
        }
        try await Task.sleep(for: .seconds(Pace.settleSeconds + 0.5))
        let target = Frame(x: ch.x + 100, y: ch.y + 100, w: 700, h: 500)
        anchors.choices.appRules = [AppRule(bundle: Self.bundle, frame: target)]
        app.engine.save()
        let e = try await newDocument()
        check(ruleName, await settled { self.at(e, target) })
        anchors.choices.appRules = []
        app.engine.save()

        try await hungApp(e)
        try await stalledTap(e)
    }

    // hungApp hangs the probe while it is in front and times a pass, a focused read, a left half on a
    // second probe's window and a hit on the hung window. Each must finish within hungSeconds, the
    // probe must be marked stalled, the tap must stay on, and the probe must be read again once the
    // hang ends.
    private func hungApp(_ id: WindowID) async throws {
        let name = "a hung app does not stall moorings"
        guard let p = probe(), let f = app.windows.frame(id) else { throw Stop(reason: "lost the window") }
        let other = try await secondProbe()
        p.activate()
        try await Task.sleep(for: .seconds(0.5))
        let disabled = app.tap.disabled
        let pid = p.processIdentifier
        DistributedNotificationCenter.default().postNotificationName(
            Self.hang, object: nil, userInfo: ["pid": String(pid), "seconds": String(Self.hangSeconds)],
            deliverImmediately: true)
        try await Task.sleep(for: .seconds(0.5))
        let screens = Screens.current()
        let center = Point(x: f.x + f.w / 2, y: f.y + f.h / 2)
        let times: [(String, Double)] = [
            ("moor", timed { self.app.engine.moor() }),
            ("focused", timed { _ = self.app.windows.focused(screens) }),
            ("left half", timed { self.app.engine.actions.run("left-half", window: other.window) }),
            ("hit", timed { _ = self.app.windows.hit(center) }),
        ]
        let stalled = app.windows.stalled(pid)
        let detail = times.map { String(format: "%@ %.3f s", $0.0, $0.1) }.joined(separator: ", ")
        logger.notice("hung app: \(detail, privacy: .public), stalled=\(stalled)")
        var result = (true, detail)
        if let slow = times.first(where: { $0.1 >= Self.hungSeconds }) {
            result = (false, "\(slow.0) took \(String(format: "%.3f", slow.1)) s: \(detail)")
        } else if !stalled {
            result = (false, "the probe was not marked stalled: \(detail)")
        } else if app.tap.disabled != disabled || !app.tap.running {
            result = (false, "the tap was turned off during the hang")
        } else {
            let back = await settled(
                {
                    let read = self.app.windows.stalls[pid] == nil && self.app.windows.scanned.contains(pid)
                    return (read, "the probe was not read again after the hang")
                }, Self.hangSeconds + Self.landSeconds)
            result = back.0 ? result : back
        }
        check(name, result)
        other.app.terminate()
        if !(await settled({ (other.app.isTerminated, "") }).0) {
            other.app.forceTerminate()
        }
    }

    // block sleeps the calling thread for seconds, which on the main thread stalls the tap's callback.
    private static func block(_ seconds: Double) {
        Thread.sleep(forTimeInterval: seconds)
    }

    // timed runs f and returns how long it took in seconds.
    private func timed(_ f: () -> Void) -> Double {
        let start = ProcessInfo.processInfo.systemUptime
        f()
        return ProcessInfo.processInfo.systemUptime - start
    }

    // secondProbe opens another probe process and returns it with the window it opens at launch.
    private func secondProbe() async throws -> (app: NSRunningApplication, window: WindowID) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundle) else {
            throw Stop(reason: "the probe is not installed")
        }
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        config.activates = false
        let other = try await NSWorkspace.shared.openApplication(at: url, configuration: config)
        var found: WindowID?
        _ = await settled(
            {
                found = self.windows(panels: false).first { self.app.windows.pid($0.id) == other.processIdentifier }?.id
                return (found != nil, "")
            }, Self.openSeconds)
        guard let found else {
            other.terminate()
            throw Stop(reason: "the second probe's window did not show")
        }
        return (other, found)
    }

    // stalledTap anchors the probe's window, blocks the main thread for stallSeconds while a
    // background thread posts events the tap listens for, and expects the system to turn the tap off
    // once, moorings to turn it back on, and a title bar drag to release the window after.
    private func stalledTap(_ id: WindowID) async throws {
        let name = "clicks work after a stalled main thread"
        anchors.assign(slot, Self.bundle)
        app.engine.save()
        guard await settled({ self.landed(id) }).0 else {
            check(name, (false, "the window did not take the slot"))
            return
        }
        try await Task.sleep(for: .seconds(Self.graceSeconds))
        let disabled = app.tap.disabled
        let events = Int((Self.stallSeconds + 0.5) * 20)
        let poster = Thread {
            for _ in 0..<events {
                let e = CGEvent(source: nil)
                e?.type = .flagsChanged
                e?.flags = []
                e?.post(tap: .cghidEventTap)
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
        poster.start()
        Self.block(Self.stallSeconds)
        try await Task.sleep(for: .seconds(1))
        let turnedOff = app.tap.disabled - disabled
        guard turnedOff == 1, app.tap.running else {
            check(name, (false, "the tap was turned off \(turnedOff) times, running=\(app.tap.running)"))
            return
        }
        guard let wide = Screens.current().wide, let pinned = app.windows.frame(id) else {
            throw Stop(reason: "lost the window")
        }
        let ch = anchors.channel(wide)
        await drag(
            from: CGPoint(x: pinned.x + pinned.w / 2, y: pinned.y + 12),
            to: CGPoint(x: ch.x + ch.w / 2, y: ch.y + ch.h / 3))
        check(
            name,
            await settled {
                (
                    self.anchors.isReleased(id),
                    "not released after the tap came back, at \(self.app.windows.frame(id) ?? pinned)"
                )
            })
    }

    // check records one result and logs it.
    private func check(_ name: String, _ result: (Bool, String)) {
        checks.append(Check(name: name, ok: result.0, detail: result.1))
        if result.0 {
            logger.notice("PASS \(name, privacy: .public)")
        } else {
            logger.notice("FAIL \(name, privacy: .public): \(result.1, privacy: .public)")
        }
    }

    // settled waits up to seconds for test to pass, and returns the last result.
    private func settled(_ test: @escaping () -> (Bool, String), _ seconds: Double = landSeconds) async -> (
        Bool, String
    ) {
        let end = Date().addingTimeInterval(seconds)
        var last = (false, "")
        while Date() < end {
            app.engine.moor()
            last = test()
            if last.0 {
                return last
            }
            try? await Task.sleep(for: .seconds(Self.stepSeconds))
        }
        return last
    }

    // steady reports whether test keeps passing for holdSeconds.
    private func steady(_ test: @escaping () -> (Bool, String)) async -> (Bool, String) {
        let end = Date().addingTimeInterval(Self.holdSeconds)
        while Date() < end {
            app.engine.moor()
            let r = test()
            if !r.0 {
                return r
            }
            try? await Task.sleep(for: .seconds(Self.stepSeconds))
        }
        return (true, "")
    }

    // info returns the window with id as the last scan saw it.
    private func info(_ id: WindowID) -> WindowInfo? {
        app.windows.scan(Screens.current()).windows.first { $0.id == id }
    }

    // windows returns the probe's windows, or its open panels when panels is true.
    private func windows(panels: Bool) -> [WindowInfo] {
        app.windows.scan(Screens.current()).windows.filter { $0.bundle == Self.bundle && $0.isFilePanel == panels }
    }

    // landed reports whether window id is anchored at the frame moorings gave it, against the edge.
    private func landed(_ id: WindowID) -> (Bool, String) {
        guard let w = info(id) else { return (false, "the window is gone") }
        guard anchors.pinned(w) else { return (false, "not anchored, at \(w.frame)") }
        guard let target = anchors.target(id) else { return (false, "anchored but never placed") }
        guard let s = Screens.current().wide else { return (false, "no ultrawide") }
        let edge =
            slot.side == .left
            ? abs(w.frame.x - s.x) <= Anchors.tolerance
            : abs(w.frame.x + w.frame.w - s.x - s.w) <= Anchors.tolerance
        if Actions.near(w.frame, target) && edge {
            return (true, "")
        }
        return (false, "at \(w.frame), want \(target) against the edge")
    }

    // inChannel reports whether window id is free and inside the channel.
    private func inChannel(_ id: WindowID) -> (Bool, String) {
        guard let w = info(id) else { return (false, "the window is gone") }
        guard !anchors.pinned(w) else { return (false, "anchored, at \(w.frame)") }
        guard let s = Screens.current().wide else { return (false, "no ultrawide") }
        let ch = anchors.channel(s)
        let inside =
            w.frame.x >= ch.x - Anchors.tolerance
            && w.frame.x + w.frame.w <= ch.x + ch.w + Anchors.tolerance
        return (inside, "at \(w.frame), channel \(ch)")
    }

    // at reports whether window id still sits at f.
    private func at(_ id: WindowID, _ f: Frame) -> (Bool, String) {
        guard let got = app.windows.frame(id) else { return (false, "the window is gone") }
        return (Actions.near(got, f), "moved to \(got) from \(f)")
    }

    // probe returns the running probe, nil when it is not open.
    private func probe() -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundle).first
    }

    // launch quits a probe left open, opens a fresh one and returns the window it opens at launch.
    private func launch() async throws -> WindowID {
        await quitProbe()
        app.open(Self.bundle, background: false)
        var found: WindowID?
        _ = await settled(
            {
                found = self.windows(panels: false).first?.id
                return (found != nil, "")
            }, Self.openSeconds)
        guard let found else { throw Stop(reason: "the probe's launch window did not show") }
        made.append(found)
        return found
    }

    // newDocument asks the probe for another window and returns it once it shows.
    private func newDocument() async throws -> WindowID {
        let before = Set(windows(panels: false).map(\.id))
        if let p = probe() {
            p.activate()
            askWindow()
        } else {
            app.open(Self.bundle, background: false)
        }
        var found: WindowID?
        var asked = probe() != nil
        let started = Date()
        _ = await settled(
            {
                found = self.windows(panels: false).first { !before.contains($0.id) }?.id
                if found == nil, !asked, Date().timeIntervalSince(started) > 2, self.probe() != nil {
                    asked = true
                    self.askWindow()
                }
                return (found != nil, "")
            }, Self.openSeconds)
        guard let found else { throw Stop(reason: "the new probe window did not show") }
        made.append(found)
        return found
    }

    // askWindow posts the probe's new-window request.
    private func askWindow() {
        DistributedNotificationCenter.default().postNotificationName(
            Self.newWindow, object: nil, userInfo: nil, deliverImmediately: true)
    }

    // close closes window id and waits for it to go.
    private func close(_ id: WindowID) async throws {
        app.windows.close(id)
        guard await settled({ (self.info(id) == nil, "") }).0 else {
            throw Stop(reason: "a probe window would not close")
        }
        made.removeAll { $0 == id }
    }

    // dismissPanels presses Cancel in each open panel the probe shows, or Escape when a panel has no
    // Cancel button.
    private func dismissPanels() async throws {
        for p in windows(panels: true) where !app.windows.cancel(p.id) {
            app.windows.raise(p.id)
            try await Task.sleep(for: .seconds(0.3))
            if let running = probe() {
                key(kVK_Escape, [], running.processIdentifier)
            }
        }
        guard await settled({ (self.windows(panels: true).isEmpty, "") }).0 else {
            throw Stop(reason: "the probe's open panel would not close")
        }
    }

    // quitProbe quits the probe, forcing it when it ignores the request. The probe holds no work, so
    // quitting it loses nothing.
    private func quitProbe() async {
        guard let p = probe() else { return }
        p.terminate()
        if await settled({ (self.probe() == nil, "") }).0 {
            return
        }
        p.forceTerminate()
    }

    // key presses the key with code and flags in the process pid.
    private func key(_ code: Int, _ flags: CGEventFlags, _ pid: pid_t) {
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(code), keyDown: down)
            e?.flags = flags
            e?.postToPid(pid)
        }
    }

    // drag presses the primary button at from, moves to to in steps, and lets go, through the mouse
    // tap like a real drag with no modifier held.
    private func drag(from: CGPoint, to: CGPoint) async {
        Self.post(.leftMouseDown, at: from)
        try? await Task.sleep(for: .seconds(0.1))
        let steps = 20
        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            Self.post(.leftMouseDragged, at: CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t))
            try? await Task.sleep(for: .seconds(0.02))
        }
        try? await Task.sleep(for: .seconds(0.1))
        Self.post(.leftMouseUp, at: to)
    }

    // click clicks the primary button at p, through the mouse tap like a real click with no modifier
    // held.
    private func click(_ p: CGPoint) {
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            Self.post(type, at: p)
        }
    }

    // post posts a primary button event of type at p with no modifier flags. An event made without
    // a source takes the session's modifier state, so a modifier the system reads as stuck would
    // turn the drag into, say, an Option-drag that macOS tiles.
    private static func post(_ type: CGEventType, at p: CGPoint) {
        let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .left)
        e?.flags = []
        e?.post(tap: .cghidEventTap)
    }
}
