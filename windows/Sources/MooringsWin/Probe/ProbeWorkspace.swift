import Foundation
import WinSDK

import MooringsCore
import MooringsEngine
import MooringsTesting

// probeWorkspace staggers every window of the app on a fresh choices file, saves them as a workspace
// under the name the tray would pick, moves them away and recalls the workspace, printing each
// window's saved frame beside where it landed and the Workspaces folder the tray builds. Under --tie
// it then ties the workspace to the fake monitor, moves the windows away, swaps the monitor for
// another size and back, and prints where they sat after each change, so a recall that comes back by
// itself only on its own displays shows. Under --launch it runs probeWorkspaceLaunch instead.
func probeWorkspace(_ opts: ProbeOptions) -> Int32 {
    let screens = Screens.current(minAspect: opts.minAspect)
    let store = Store()
    do {
        try store.save(Choices())
    } catch {
        print("workspace: \(error)")
        return 1
    }
    let app = App(store: store, minAspect: opts.minAspect)
    let pads = app.windows.scan(screens, full: true).windows.filter { $0.bundle.hasSuffix(opts.app) }
    guard let first = pads.first, let i = screens.index(first.frame) else {
        print("workspace: no window of \(opts.app)")
        return 1
    }
    let area = app.engine.organizer.area(screens, i)
    if opts.launch {
        return probeWorkspaceLaunch(app, first, area: area, screens: screens)
    }
    let settle = { app.run(until: App.now + 0.5) }
    let place = { (frame: (Double) -> Frame) in
        for (k, p) in pads.enumerated() {
            app.windows.move(p.id, to: frame(Double(k)), from: nil, behavior: Behaviors())
        }
        settle()
    }
    let away = { (d: Double) in Frame(x: area.x + 20 + 15 * d, y: area.y + 20, w: 300, h: 200) }
    place { Frame(x: area.x + 60 + 120 * $0, y: area.y + 60 + 30 * $0, w: 420, h: 300) }
    var saved: [WindowID: Frame] = [:]
    for p in pads {
        saved[p.id] = app.windows.frame(p.id)
    }
    let show = { (label: String) in
        for p in pads {
            let got = app.windows.frame(p.id).map(pixels) ?? "gone"
            print("\(label) \(hex(p.id)): want \(saved[p.id].map(pixels) ?? "none") got \(got)")
        }
    }
    let workspaces = app.engine.workspaces
    let name = Tray.freeWorkspaceName(app.engine.anchors.choices)
    workspaces.saveWorkspace(name)
    let kept = app.engine.anchors.choices.workspaces[name]?.windows ?? []
    print("pads: \(pads.count)")
    print("name: \(name)")
    print("saved: \(kept.count) pads \(kept.filter { $0.bundle.hasSuffix(opts.app) }.count)")
    place(away)
    print("recalled: \(workspaces.recall(name))")
    settle()
    show("pad")
    let folder = {
        printMenu([
            Tray.workspacesFolder(
                choices: app.engine.anchors.choices, displays: app.screens.displaySetKey(app.screens.current()))
        ])
    }
    folder()
    guard opts.tie else { return 0 }
    guard let fake = Monitor.fake else {
        print("workspace: --tie needs --screen")
        return 1
    }
    workspaces.tie(name)
    print("tied: \(workspaces.tied(name))")
    folder()
    place(away)
    let wait = { app.run(until: App.now + WorkspaceKeeper.settleSeconds + 1) }
    Monitor.fake = .sized(Size(w: Int(fake.full.w) - 880, h: Int(fake.full.h)), scale: fake.scale)
    print("other displays: \(app.screens.displaySetKey(app.screens.current()))")
    app.displaysChanged()
    wait()
    show("other")
    Monitor.fake = fake
    print("own displays: \(app.screens.displaySetKey(app.screens.current()))")
    app.displaysChanged()
    wait()
    show("back")
    return 0
}

// probeWorkspaceLaunch places first inside area, saves it in a workspace, turns on Open apps that are
// not running through the tray's command, moves the window off its saved frame so the app does not
// remember the saved one, closes every window of its app and recalls. It prints where the window the
// recall opened landed beside the saved frame.
func probeWorkspaceLaunch(_ app: App, _ first: WindowInfo, area: Frame, screens: Screens) -> Int32 {
    let bundle = first.bundle
    app.windows.move(
        first.id, to: Frame(x: area.x + 150, y: area.y + 120, w: 600, h: 400), from: nil, behavior: Behaviors())
    app.run(until: App.now + 0.5)
    guard let want = app.windows.frame(first.id) else {
        print("workspace: the window of \(bundle) is gone")
        return 1
    }
    let name = Tray.freeWorkspaceName(app.engine.anchors.choices)
    app.engine.workspaces.saveWorkspace(name)
    Tray(app: app).perform(.openMissing(name))
    let ws = app.engine.anchors.choices.workspaces[name]
    print("opens missing: \(ws.map(Tray.opensMissing) ?? false)")
    let closed = closeAll(app, bundle: bundle, screens: screens, moving: area)
    print("closed: \(closed)")
    print("recalled: \(app.engine.workspaces.recall(name))")
    let shown = waitWindow(app, bundle: bundle, screens: screens, seconds: 10)
    print("launched: \(shown.map(hex) ?? "none")")
    app.run(until: App.now + WorkspaceKeeper.recheckSeconds + 1)
    print("launch: want \(pixels(want)) got \(shown.flatMap(app.windows.frame).map(pixels) ?? "none")")
    return 0
}

// probeAppRule learns the app's bundle from its front window and, on a fresh choices file, sets a rule
// that puts the app's first window at a frame inside the organize area, or no rule under --no-rule.
// It moves every window of the app off that frame, so the app does not remember it, closes them,
// opens the app the way a recall does and prints where its new window landed.
func probeAppRule(_ opts: ProbeOptions) -> Int32 {
    let screens = Screens.current(minAspect: opts.minAspect)
    guard let first = WinWindows.scan(screens: screens).windows.first(where: { $0.bundle.hasSuffix(opts.app) }),
        let i = screens.index(first.frame)
    else {
        print("apprule: no window of \(opts.app)")
        return 1
    }
    let bundle = first.bundle
    let store = Store()
    do {
        try store.save(Choices())
    } catch {
        print("apprule: \(error)")
        return 1
    }
    let app = App(store: store, minAspect: opts.minAspect)
    let area = app.engine.organizer.area(screens, i)
    let target = Frame(x: area.x + 150, y: area.y + 120, w: 600, h: 400)
    if !opts.noRule {
        app.engine.anchors.choices.appRules = [AppRule(bundle: bundle, frame: target)]
        app.engine.save()
    }
    print("rule: \(!app.engine.anchors.choices.appRules.isEmpty)")
    print("closed: \(closeAll(app, bundle: bundle, screens: screens, moving: area))")
    print("opened: \(app.apps.open(bundle, background: true, target: nil))")
    let shown = waitWindow(app, bundle: bundle, screens: screens, seconds: 10)
    print("shown: \(shown.map(hex) ?? "none")")
    app.run(until: App.now + WorkspaceKeeper.recheckSeconds + 1)
    print("landed: want \(pixels(target)) got \(shown.flatMap(app.windows.frame).map(pixels) ?? "none")")
    return 0
}

// closeAll moves every window of bundle to the top-left of area, where no probe expects one, so the
// position the app keeps for its next start is that one, then closes them and runs the loop until
// they are gone. It reports whether none is left.
private func closeAll(_ app: App, bundle: String, screens: Screens, moving area: Frame) -> Bool {
    let mine = { app.windows.scan(screens, full: true).windows.filter { $0.bundle == bundle } }
    for w in mine() {
        let corner = Frame(x: area.x + 10, y: area.y + 10, w: 380, h: 260)
        app.windows.move(w.id, to: corner, from: nil, behavior: Behaviors())
    }
    app.run(until: App.now + 0.5)
    for w in mine() {
        if let hwnd = WinWindows.hwnd(w.id) {
            _ = PostMessageW(hwnd, UINT(WM_CLOSE), 0, 0)
        }
    }
    app.run(until: App.now + 1.5)
    return mine().isEmpty
}

// waitWindow runs the loop until a window of bundle shows or seconds pass, and returns its ID.
private func waitWindow(_ app: App, bundle: String, screens: Screens, seconds: Double) -> WindowID? {
    let until = App.now + seconds
    while App.now < until {
        app.run(until: App.now + 0.25)
        if let w = app.windows.scan(screens, full: true).windows.first(where: { $0.bundle == bundle }) {
            return w.id
        }
    }
    return nil
}
