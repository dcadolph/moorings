import Foundation

// ActionLink reads the moorings:// links that run an action, the same on every platform.
public enum ActionLink {
    // isLink reports whether text is a moorings link of any kind.
    public static func isLink(_ text: String) -> Bool {
        text.lowercased().hasPrefix("moorings://")
    }

    // name returns the action a moorings://action?name= link asks for, nil for anything else.
    public static func name(in link: String) -> String? {
        guard isLink(link), let parts = URLComponents(string: link), parts.host?.lowercased() == "action" else {
            return nil
        }
        return parts.queryItems?.first { $0.name == "name" }?.value.flatMap { $0.isEmpty ? nil : $0 }
    }
}
