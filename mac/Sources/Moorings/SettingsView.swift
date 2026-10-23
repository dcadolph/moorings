import SwiftUI

import MooringsCore

// SettingsView is the settings window's content: shortcuts, sizes, workspaces, layout, appearance
// and general choices.
struct SettingsView: View {
    // model holds the choices and saves each change.
    @ObservedObject var model: SettingsModel

    // body lays the sections out as tabs.
    var body: some View {
        TabView {
            shortcuts.tabItem { Text("Shortcuts") }
            sizes.tabItem { Text("Sizes") }
            workspaces.tabItem { Text("Workspaces") }
            layout.tabItem { Text("Layout") }
            appearance.tabItem { Text("Appearance") }
            general.tabItem { Text("General") }
        }
        .padding()
        .frame(minWidth: 600, minHeight: 480)
    }

    // actionNames lists every action that can take a shortcut, in menu order.
    private var actionNames: [String] {
        ActionRunner.families.flatMap { $0.names + $0.groups.flatMap(\.names) } + Tile.names
    }

    // shortcuts lists every action with its shortcut, a recorder, and a way back to the keymap's.
    private var shortcuts: some View {
        let map = model.bindings.map
        return List(actionNames, id: \.self) { name in
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
        return VStack(alignment: .leading) {
            if names.isEmpty {
                Text("No workspaces yet. Save one from the Workspaces folder in the menu.").font(.callout)
            }
            List(names, id: \.self) { name in
                WorkspaceRow(name: name, tied: model.app.organizer.tied(name),
                             rename: { new in
                                 model.change {
                                     guard let ws = $0.workspaces.removeValue(forKey: name) else { return }
                                     var renamed = ws
                                     renamed.name = new
                                     $0.workspaces[new] = renamed
                                 }
                             },
                             tie: { model.app.organizer.tie(name); model.reload() },
                             delete: { model.change { $0.workspaces[name] = nil } })
            }
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
            Toggle("Fullscreen fills the channel", isOn: Binding(get: { model.choices.fullscreenFills },
                                                                  set: { v in model.change { $0.fullscreenFills = v } }))
            Toggle("Fullscreen keeps anchored apps in their slots",
                   isOn: Binding(get: { model.choices.pinFullscreenFills },
                                 set: { v in model.change { $0.pinFullscreenFills = v } }))
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

    // general holds launch at login, the update check, and export and import.
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

    // draft is the name being typed.
    @State private var draft = ""

    // body shows the name field, the tie switch and Delete.
    var body: some View {
        HStack {
            TextField("Name", text: $draft)
                .onAppear { draft = name }
                .onSubmit {
                    let new = draft.trimmingCharacters(in: .whitespaces)
                    if !new.isEmpty && new != name {
                        rename(new)
                    }
                }
            Toggle("With these displays", isOn: Binding(get: { tied }, set: { _ in tie() }))
            Button("Delete", action: delete)
        }
    }
}
