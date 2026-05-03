import AppKit
import ApplicationServices
import Combine
import Carbon

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    // MARK: - Constants

    private enum UI {
        static let autoStripPollingInterval: TimeInterval = 0.333
        static let autoStripDebounceInterval: TimeInterval = 0.15
        static let pasteDelay: TimeInterval = 0.20
    }

    private enum DefaultsKey {
        static let autoStripEnabled = "UnformatAutoStripEnabled"
    }

    // MARK: - Properties

    private var pasteboardMonitor: Timer?
    private lazy var aboutWindowController = AboutWindowController()
    private let clipboardStripper = ClipboardStripper()
    private let loginManager = LoginManager()
    private let clipboardMonitor = ClipboardMonitor(
        initialChangeCount: NSPasteboard.general.changeCount,
        debounceInterval: UI.autoStripDebounceInterval
    )
    private lazy var hotKeyManager = HotKeyManager { [weak self] in
        self?.stripAndPaste()
    }

    @Published var autoStripEnabled: Bool {
        didSet {
            UserDefaults.standard.set(autoStripEnabled, forKey: DefaultsKey.autoStripEnabled)
        }
    }

    @Published private(set) var isLaunchAtLoginEnabled: Bool

    override init() {
        autoStripEnabled = UserDefaults.standard.bool(forKey: DefaultsKey.autoStripEnabled)
        isLaunchAtLoginEnabled = loginManager.isLaunchAtLoginEnabled
        super.init()
    }

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        startPasteboardMonitoring()
        registerStripAndPasteHotKey()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Stop observing before the app exits so the delegate releases cleanly.
        pasteboardMonitor?.invalidate()
        clipboardMonitor.cancelPendingWork()
        hotKeyManager.unregister()
    }

    // MARK: - Permissions and Input Simulation

    /// Checks accessibility trust, optionally asking macOS to display the permission prompt.
    private func isProcessTrusted(promptIfNeeded: Bool) -> Bool {
        let options =
            [
                kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String:
                    promptIfNeeded
            ]
            as CFDictionary

        return AXIsProcessTrustedWithOptions(options)
    }

    /// Posts a synthetic Command-V event sequence to the current foreground app.
    private func pasteIntoFrontmostApp() {
        let source = CGEventSource(stateID: .privateState)
        source?.localEventsSuppressionInterval = 0

        let commandDown = CGEvent(
            keyboardEventSource: source,
            virtualKey: CGKeyCode(kVK_Command),
            keyDown: true
        )

        let vDown = CGEvent(
            keyboardEventSource: source,
            virtualKey: CGKeyCode(kVK_ANSI_V),
            keyDown: true
        )
        vDown?.flags = .maskCommand

        let vUp = CGEvent(
            keyboardEventSource: source,
            virtualKey: CGKeyCode(kVK_ANSI_V),
            keyDown: false
        )
        vUp?.flags = .maskCommand

        let commandUp = CGEvent(
            keyboardEventSource: source,
            virtualKey: CGKeyCode(kVK_Command),
            keyDown: false
        )

        commandDown?.post(tap: .cghidEventTap)
        vDown?.post(tap: .cghidEventTap)
        vUp?.post(tap: .cghidEventTap)
        commandUp?.post(tap: .cghidEventTap)
    }

    /// Converts the clipboard to plain text and pastes it into the active app.
    private func stripAndPaste() {
        guard isProcessTrusted(promptIfNeeded: true) else {
            return
        }

        stripNow()

        // Delay slightly so the updated plain-text pasteboard entry is visible to the target app.
        DispatchQueue.main.asyncAfter(deadline: .now() + UI.pasteDelay) {
            [weak self] in
            self?.pasteIntoFrontmostApp()
        }
    }

    // MARK: - Hot Key Registration

    /// Registers the global shortcut used to strip and paste in one step.
    private func registerStripAndPasteHotKey() {
        if let status = hotKeyManager.register() {
            handleHotKeyRegistrationFailure(status)
        }
    }

    /// Informs the user when the global shortcut cannot be registered.
    private func handleHotKeyRegistrationFailure(_ status: OSStatus) {
        let message: String
        if status == eventHotKeyExistsErr {
            message =
                "The paste shortcut Control-Option-Command-V is already used by another app. Unformat will keep running, but the global paste shortcut is disabled."
        } else {
            message =
                "Unformat could not register the paste shortcut Control-Option-Command-V. Error code: \(status). Unformat will keep running, but the global paste shortcut is disabled."
        }

        showHotKeyRegistrationAlert(message: message)
    }

    /// Presents a blocking alert because hot key registration failures need direct user attention.
    private func showHotKeyRegistrationAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = "Paste Shortcut Disabled"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // MARK: - Clipboard Monitoring

    /// Polls the general pasteboard and strips rich text after changes settle.
    private func startPasteboardMonitoring() {
        pasteboardMonitor = Timer.scheduledTimer(
            withTimeInterval: UI.autoStripPollingInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handlePasteboardChangeIfNeeded()
            }
        }
    }

    /// Debounces pasteboard writes so the source app can finish publishing all representations.
    private func handlePasteboardChangeIfNeeded() {
        let pasteboard = NSPasteboard.general
        clipboardMonitor.processChangeCount(
            pasteboard.changeCount,
            autoStripEnabled: autoStripEnabled
        ) { [weak self] in
            self?.stripNow()
        }
    }

    // MARK: - Menu Actions

    /// Persists the automatic stripping preference when the menu toggle changes.
    func setAutoStripEnabled(_ isEnabled: Bool) {
        autoStripEnabled = isEnabled
    }

    /// Updates login-item registration when the menu toggle changes.
    func setLaunchAtLoginEnabled(_ isEnabled: Bool) {
        do {
            try loginManager.setLaunchAtLogin(desiredState: isEnabled)
            isLaunchAtLoginEnabled = loginManager.isLaunchAtLoginEnabled
        } catch {
            isLaunchAtLoginEnabled = loginManager.isLaunchAtLoginEnabled
            showLaunchAtLoginAlert(for: isEnabled, error: error)
        }
    }

    /// Rewrites the general pasteboard with only its plain-text representation.
    func stripNowFromMenu() {
        stripNow()
    }

    /// Presents the app's custom About window.
    func showAboutWindowFromMenu() {
        aboutWindowController.present()
    }

    func quitFromMenu() {
        NSApplication.shared.terminate(nil)
    }

    /// Rewrites the general pasteboard with only its plain-text representation.
    private func stripNow() {
        let pasteboard = NSPasteboard.general

        if clipboardStripper.stripIfNeeded(pasteboard) {
            clipboardMonitor.updateObservedChangeCount(pasteboard.changeCount)
        }
    }

    /// Presents a warning when the app cannot update launch-at-login registration.
    private func showLaunchAtLoginAlert(for desiredState: Bool, error: Error) {
        let alert = NSAlert()
        alert.messageText = desiredState ? "Could Not Enable Launch at Login" : "Could Not Disable Launch at Login"
        alert.informativeText = "Unformat could not update its login item status. Error: \(error.localizedDescription)"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
