import AppKit
import ApplicationServices
import Carbon
import UniformTypeIdentifiers

/// Converts a short ASCII string into the four-character code used by Carbon APIs.
private extension String {
    var fourCharCode: FourCharCode {
        var result: FourCharCode = 0

        for char in utf8.prefix(4) {
            result = (result << 8) + FourCharCode(char)
        }

        return result
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    // MARK: - Constants

    private enum UI {
        static let autoStripPollingInterval: TimeInterval = 0.333
        static let autoStripDebounceInterval: TimeInterval = 0.15
        static let pasteDelay: TimeInterval = 0.20
        static let statusItemWidth: CGFloat = 24
        static let statusItemFontSize: CGFloat = 18
        static let statusItemBaselineOffset: CGFloat = -3
        static let toggleContainerSize = NSSize(width: 280, height: 40)
        static let horizontalInset: CGFloat = 14
        static let labelSpacing: CGFloat = 12
    }

    private enum DefaultsKey {
        static let autoStripEnabled = "UnformatAutoStripEnabled"
    }

    // MARK: - Properties

    private var statusItem: NSStatusItem?
    private var pasteboardChangeCount: Int = NSPasteboard.general.changeCount
    private var debounceWork: DispatchWorkItem?
    private var pasteboardMonitor: Timer?
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?
    private var retryHotKeyItem: NSMenuItem?

    private var autoStripEnabled: Bool {
        get {
            UserDefaults.standard.bool(forKey: DefaultsKey.autoStripEnabled)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: DefaultsKey.autoStripEnabled)
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
        debounceWork?.cancel()

        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }

        if let hotKeyHandler {
            RemoveEventHandler(hotKeyHandler)
        }
    }

    // MARK: - Status Item

    /// Builds the menu bar item and its menu-based controls.
    private func configureStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.statusItem = statusItem

        if let button = statusItem.button {
            button.attributedTitle = makeStatusItemTitle()
            button.frame = NSRect(
                x: 0,
                y: 0,
                width: UI.statusItemWidth,
                height: NSStatusBar.system.thickness
            )
        }

        statusItem.menu = makeStatusMenu()
    }

    /// Creates the attributed title used in the menu bar.
    private func makeStatusItemTitle() -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: UI.statusItemFontSize, weight: .bold),
            .paragraphStyle: paragraph,
            .baselineOffset: UI.statusItemBaselineOffset
        ]

        return NSAttributedString(string: "U", attributes: attributes)
    }

    /// Assembles the menu shown when the user clicks the status item.
    private func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()

        let autoItem = NSMenuItem()
        autoItem.view = makeAutoStripToggleView()
        menu.addItem(autoItem)
        menu.addItem(.separator())

        let stripItem = NSMenuItem(
            title: "Strip Clipboard Now",
            action: #selector(stripNow),
            keyEquivalent: ""
        )
        stripItem.target = self
        menu.addItem(stripItem)

        let retryItem = NSMenuItem(
            title: "Retry Paste Shortcut",
            action: #selector(retryHotKeyRegistration),
            keyEquivalent: ""
        )
        retryItem.target = self
        retryItem.isHidden = true
        retryHotKeyItem = retryItem
        menu.addItem(retryItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit Unformat",
            action: #selector(quit),
            keyEquivalent: ""
        )
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    // MARK: - Permissions and Input Simulation

    /// Checks accessibility trust, optionally asking macOS to display the permission prompt.
    private func isProcessTrusted(promptIfNeeded: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: promptIfNeeded]
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
        DispatchQueue.main.asyncAfter(deadline: .now() + UI.pasteDelay) { [weak self] in
            self?.pasteIntoFrontmostApp()
        }
    }

    // MARK: - Hot Key Registration

    /// Registers the global shortcut used to strip and paste in one step.
    private func registerStripAndPasteHotKey() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let userData else {
                    return noErr
                }

                let appDelegate = Unmanaged<AppDelegate>
                    .fromOpaque(userData)
                    .takeUnretainedValue()

                appDelegate.stripAndPaste()

                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &hotKeyHandler
        )

        guard handlerStatus == noErr else {
            handleHotKeyRegistrationFailure(handlerStatus)
            return
        }

        let hotKeyID = EventHotKeyID(
            signature: OSType("UNFT".fourCharCode),
            id: 1
        )

        let modifiers = UInt32(cmdKey | optionKey | controlKey)

        let hotKeyStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_V),
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard hotKeyStatus == noErr else {
            if let hotKeyHandler {
                RemoveEventHandler(hotKeyHandler)
                self.hotKeyHandler = nil
            }

            handleHotKeyRegistrationFailure(hotKeyStatus)
            return
        }

        retryHotKeyItem?.isHidden = true
    }

    /// Updates menu state and informs the user when the global shortcut cannot be registered.
    private func handleHotKeyRegistrationFailure(_ status: OSStatus) {
        retryHotKeyItem?.isHidden = false

        let message: String
        if status == eventHotKeyExistsErr {
            message = "The paste shortcut Control-Option-Command-V is already used by another app. Unformat will keep running, but the global paste shortcut is disabled."
        } else {
            message = "Unformat could not register the paste shortcut Control-Option-Command-V. Error code: \(status). Unformat will keep running, but the global paste shortcut is disabled."
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

    /// Removes any stale registration before trying again.
    @objc private func retryHotKeyRegistration() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if let hotKeyHandler {
            RemoveEventHandler(hotKeyHandler)
            self.hotKeyHandler = nil
        }

        registerStripAndPasteHotKey()
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
        let currentChangeCount = pasteboard.changeCount

        guard currentChangeCount != pasteboardChangeCount else {
            return
        }

        pasteboardChangeCount = currentChangeCount

        guard autoStripEnabled else {
            return
        }

        debounceWork?.cancel()

        let work = DispatchWorkItem { [weak self] in
            self?.stripNow()
        }

        debounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + UI.autoStripDebounceInterval, execute: work)
    }

    // MARK: - Menu Views

    /// Creates the custom menu row that pairs the automatic mode label with its switch.
    private func makeAutoStripToggleView() -> NSView {
        let container = NSView(frame: NSRect(origin: .zero, size: UI.toggleContainerSize))

        let label = NSTextField(labelWithString: "Automatic Stripping")
        label.font = .menuFont(ofSize: 0)
        label.translatesAutoresizingMaskIntoConstraints = false

        let toggle = NSSwitch()
        toggle.state = autoStripEnabled ? .on : .off
        toggle.target = self
        toggle.action = #selector(toggleAutomaticStrippingFromSwitch(_:))
        toggle.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(label)
        container.addSubview(toggle)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: UI.horizontalInset),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            toggle.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -UI.horizontalInset),
            toggle.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            label.trailingAnchor.constraint(lessThanOrEqualTo: toggle.leadingAnchor, constant: -UI.labelSpacing)
        ])

        return container
    }

    /// Persists the automatic stripping preference when the menu switch changes.
    @objc private func toggleAutomaticStrippingFromSwitch(_ sender: NSSwitch) {
        autoStripEnabled = sender.state == .on
    }

    // MARK: - Clipboard Stripping

    /// Rewrites the general pasteboard with only its plain-text representation.
    @objc private func stripNow() {
        let pasteboard = NSPasteboard.general

        guard shouldStripClipboard(pasteboard) else {
            return
        }

        guard let plainText = pasteboard.string(forType: .string), !plainText.isEmpty else {
            return
        }

        pasteboard.clearContents()
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString(plainText, forType: .string)
        pasteboardChangeCount = pasteboard.changeCount
    }

    /// Determines whether the clipboard currently contains rich text that is safe to flatten.
    private func shouldStripClipboard(_ pasteboard: NSPasteboard) -> Bool {
        let types = pasteboard.types ?? []

        guard pasteboard.canReadObject(forClasses: [NSString.self], options: nil) else {
            return false
        }

        guard containsRichTextRepresentation(types) else {
            return false
        }

        // Do not rewrite file selections into path-like text.
        // Rich text sources may also expose image/PDF flavors for embedded or printable content,
        // so image/PDF presence alone must not block stripping.
        guard !types.contains(where: isFileLike) else {
            return false
        }

        return true
    }

    /// Returns true when any available pasteboard type looks like rich text or HTML.
    private func containsRichTextRepresentation(_ types: [NSPasteboard.PasteboardType]) -> Bool {
        types.contains { type in
            isRichTextLike(type)
        }
    }

    /// Handles both standard and loosely named rich-text pasteboard types.
    private func isRichTextLike(_ type: NSPasteboard.PasteboardType) -> Bool {
        switch type {
        case .rtf, .rtfd, .html:
            return true
        default:
            break
        }

        let rawValue = type.rawValue.lowercased()

        if rawValue == "next rich text format" {
            return true
        }

        if rawValue.contains("rtf") || rawValue.contains("rich text") || rawValue.contains("html") {
            return true
        }

        guard let uniformType = UTType(type.rawValue) else {
            return false
        }

        return uniformType.conforms(to: .rtf)
            || uniformType.conforms(to: .rtfd)
            || uniformType.conforms(to: .html)
    }

    /// Detects file-selection pasteboard payloads, which should not be rewritten as text.
    private func isFileLike(_ type: NSPasteboard.PasteboardType) -> Bool {
        switch type {
        case .fileURL:
            return true
        default:
            break
        }

        let rawValue = type.rawValue.lowercased()

        if rawValue == "nsfilenamespboardtype"
            || rawValue.contains("file-url")
            || rawValue.contains("fileurl")
            || rawValue.contains("filename") {
            return true
        }

        guard let uniformType = UTType(type.rawValue) else {
            return false
        }

        return uniformType.conforms(to: .fileURL)
    }

    // MARK: - Actions

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
