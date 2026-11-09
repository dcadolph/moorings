import Foundation
import WinSDK

import MooringsCore
import MooringsEngine

// LinkRequest is what the command line asks of Moorings, read before any option. A link is the whole
// request, because the shell expands "%1" into the command line and a link holding a quote could
// otherwise add flags of its own. --action is the terminal form.
enum LinkRequest: Equatable {
    case link(String)
    case action(String?)

    // init reads the request from the arguments after the program name, nil when they hold none.
    init?(_ arguments: [String]) {
        guard let first = arguments.first else { return nil }
        if ActionLink.isLink(first) {
            self = .link(first)
        } else if first == "--action" {
            self = .action(arguments.dropFirst().first)
        } else {
            return nil
        }
    }
}

// Links carries an action to the running Moorings as WM_COPYDATA to its tray window, and registers
// the moorings: scheme with the current user. The reply is the message's return value.
enum Links {
    // tag marks a WM_COPYDATA message as a link's action name.
    static let tag = ULONG_PTR(0x4D4F_4F52)
    // limit is the longest action name in bytes the tray reads.
    static let limit = 256
    // wait is how long a sender waits on the tray, in milliseconds.
    static let wait = UINT(5000)
    // ran, unknown and refused are the tray's answers. Zero means the message was not understood.
    static let ran = LRESULT(1)
    static let unknown = LRESULT(2)
    static let refused = LRESULT(3)
    // schemeKey is the registry key that names Moorings as the handler of moorings: links.
    static let schemeKey = "Software\\Classes\\moorings"

    // running returns the tray window of the Moorings already running, nil when there is none.
    static func running() -> HWND? {
        FindWindowW(wide(Tray.className), nil)
    }

    // deliver answers a request that a running Moorings or the command line can answer, and exits.
    // It returns only for a link's action when Moorings is not running, for the new tray to run.
    static func deliver(_ request: LinkRequest) -> String {
        switch request {
        case .action(nil):
            print("--action needs an action name")
            exit(2)
        case .action(let name?):
            guard let window = running() else {
                print("not running")
                exit(1)
            }
            exit(say(send(name, to: window), name))
        case .link(let link):
            guard let name = ActionLink.name(in: link) else {
                print("unknown link: \(link)")
                exit(1)
            }
            guard let window = running() else { return name }
            exit(say(send(name, to: window), name))
        }
    }

    // send asks the tray window to run name and returns its answer, nil when it gave none.
    static func send(_ name: String, to window: HWND) -> LRESULT? {
        var bytes = Array(name.utf8)
        guard bytes.count <= limit else { return unknown }
        var answer = DWORD_PTR(0)
        let sent = bytes.withUnsafeMutableBytes { raw in
            var data = COPYDATASTRUCT(dwData: tag, cbData: DWORD(raw.count), lpData: raw.baseAddress)
            return withUnsafeMutablePointer(to: &data) { pointer in
                SendMessageTimeoutW(
                    window, UINT(WM_COPYDATA), 0, LPARAM(Int(bitPattern: pointer)), UINT(SMTO_ABORTIFHUNG), wait,
                    &answer)
            }
        }
        return sent == 0 || answer == 0 ? nil : LRESULT(bitPattern: answer)
    }

    // answer returns the reply that says verdict.
    static func answer(_ verdict: LinkVerdict) -> LRESULT {
        switch verdict {
        case .run: ran
        case .unknown: unknown
        case .refused: refused
        }
    }

    // say prints what the tray answered about name and returns the exit code.
    static func say(_ answer: LRESULT?, _ name: String) -> Int32 {
        switch answer {
        case ran:
            print("ran: \(name)")
            return 0
        case unknown:
            print("unknown action: \(name)")
        case refused:
            print("refused: \(name): closing actions run only from shortcuts and the menu")
        default:
            print("no answer from Moorings")
        }
        return 1
    }

    // register names this exe as the handler of moorings: links, refreshed at each start since the
    // folder can move. A value the registry refuses is logged, since links are all that it costs. An
    // empty value name is the key's default value.
    static func register(_ log: WinLog) {
        let values = [
            (schemeKey, "", "URL:Moorings"),
            (schemeKey, "URL Protocol", ""),
            ("\(schemeKey)\\shell\\open\\command", "", "\"\(LoginItem.executable)\" \"%1\""),
        ]
        for (key, name, value) in values {
            let text = wide(value)
            let status = RegSetKeyValueW(
                LoginItem.currentUser, wide(key), wide(name), DWORD(REG_SZ), text,
                DWORD(text.count * MemoryLayout<WCHAR>.size))
            if status != ERROR_SUCCESS {
                log.note(.actions, "links: \(key) not registered: error \(status)")
            }
        }
    }
}
