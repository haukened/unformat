import AppKit

@main
struct UnformatApp {
    /// Boots the AppKit application manually so the menu bar delegate remains the entry point.
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
