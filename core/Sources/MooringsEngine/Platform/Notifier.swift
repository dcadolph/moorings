// Notifier shows a short message without taking focus.
public protocol Notifier: AnyObject {
    // notify shows title and body.
    func notify(_ title: String, _ body: String)
}
