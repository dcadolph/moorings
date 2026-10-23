import AppKit

// AppDelegate starts Moorings and owns its long-lived objects.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // spike runs the step 0 platform checks.
    private let spike = Spike()
    // item is the menu bar status item.
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    // applicationDidFinishLaunching builds the menu bar item and runs any commands given at launch.
    func applicationDidFinishLaunching(_ notification: Notification) {
        item.button?.image = NSImage(systemSymbolName: "sailboat", accessibilityDescription: "Moorings")
        let menu = NSMenu()
        for command in Spike.Command.allCases {
            let entry = NSMenuItem(title: command.title, action: #selector(runMenuCommand(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = command.rawValue
            menu.addItem(entry)
        }
        item.menu = menu
        if let flag = CommandLine.arguments.firstIndex(of: "--spike") {
            for name in CommandLine.arguments.dropFirst(flag + 1) {
                spike.run(name, query: [:])
            }
        }
    }

    // application runs a spike command for each moorings:// link, e.g. moorings://move?app=TextEdit.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "moorings" {
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let query = Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { _, last in last })
            spike.run(url.host() ?? "", query: query)
        }
    }

    // runMenuCommand runs the spike command a menu item names.
    @objc private func runMenuCommand(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        spike.run(name, query: [:])
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
