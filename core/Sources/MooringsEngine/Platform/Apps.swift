// Apps names and opens apps.
public protocol Apps: AnyObject {
    // name returns the name to show for a bundle or executable id.
    func name(_ bundle: String) -> String
    // open launches an app, in the background when asked, with an optional target (a file or URL). It
    // returns false when the platform cannot start it.
    func open(_ bundle: String, background: Bool, target: String?) -> Bool
}
