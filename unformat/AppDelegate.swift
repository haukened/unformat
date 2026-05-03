import AppKit
import ApplicationServices
import Carbon

final class AppDelegate: NSObject, NSApplicationDelegate {
    // MARK: - Constants

    private enum UI {
        static let autoStripPollingInterval: TimeInterval = 0.333
        static let autoStripDebounceInterval: TimeInterval = 0.15
        static let pasteDelay: TimeInterval = 0.20
        static let statusItemWidth: CGFloat = 24
    }

    private enum DefaultsKey {
        static let autoStripEnabled = "UnformatAutoStripEnabled"
    }

    // MARK: - Properties

    private var statusItem: NSStatusItem?
    private var pasteboardMonitor: Timer?
    private lazy var aboutWindowController = AboutWindowController()
    private let clipboardStripper = ClipboardStripper()
    private let clipboardMonitor = ClipboardMonitor(
        initialChangeCount: NSPasteboard.general.changeCount,
        debounceInterval: UI.autoStripDebounceInterval
    )
    private lazy var hotKeyManager = HotKeyManager { [weak self] in
        self?.stripAndPaste()
    }

    private var autoStripEnabled: Bool {
        get {
            UserDefaults.standard.bool(forKey: DefaultsKey.autoStripEnabled)
        }
        set {
            UserDefaults.standard.set(
                newValue,
                forKey: DefaultsKey.autoStripEnabled
            )
        }
    }

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)

        configureStatusItem()
        startPasteboardMonitoring()
        registerStripAndPasteHotKey()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Stop observing before the app exits so the delegate releases cleanly.
        pasteboardMonitor?.invalidate()
        clipboardMonitor.cancelPendingWork()
        hotKeyManager.unregister()
    }

    // MARK: - Status Item

    /// Builds the menu bar item and its menu-based controls.
    private func configureStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength
        )
        self.statusItem = statusItem

        if let button = statusItem.button {
            button.attributedTitle = StatusMenuBuilder.makeStatusItemTitle()
            button.frame = NSRect(
                x: 0,
                y: 0,
                width: UI.statusItemWidth,
                height: NSStatusBar.system.thickness
            )
        }

        statusItem.menu = StatusMenuBuilder.makeMenu(
            target: self,
            autoStripEnabled: autoStripEnabled,
            toggleAction: #selector(toggleAutomaticStrippingFromSwitch(_:)),
            stripAction: #selector(stripNow),
            aboutAction: #selector(showAboutWindow),
            quitAction: #selector(quit)
        )
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
            self?.handlePasteboardChangeIfNeeded()
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

    // MARK: - Actions

    /// Persists the automatic stripping preference when the menu switch changes.
    @objc private func toggleAutomaticStrippingFromSwitch(_ sender: NSSwitch) {
        autoStripEnabled = sender.state == .on
    }

    /// Rewrites the general pasteboard with only its plain-text representation.
    @objc private func stripNow() {
        let pasteboard = NSPasteboard.general

        if clipboardStripper.stripIfNeeded(pasteboard) {
            clipboardMonitor.updateObservedChangeCount(pasteboard.changeCount)
        }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    /// Presents the app's custom About window.
    @objc private func showAboutWindow() {
        aboutWindowController.present()
    }
}
