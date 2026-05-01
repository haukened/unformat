import AppKit
import ApplicationServices
import Carbon
import UniformTypeIdentifiers

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
    private var statusItem: NSStatusItem?
    private var autoStripEnabled: Bool = false
    private var pasteboardChangeCount: Int = NSPasteboard.general.changeCount
    private var debounceWork: DispatchWorkItem?
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?
    private var hotKeyRegistrationFailed: Bool = false
    private var retryHotKeyItem: NSMenuItem?
    private var enablePermissionItem: NSMenuItem?
    private var menu: NSMenu?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.statusItem = statusItem

        if let button = statusItem.button {
            button.title = "U"
        }

        let menu = NSMenu()
        self.menu = menu

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

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit Unformat",
            action: #selector(quit),
            keyEquivalent: ""
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu

        // Start a timer to observe pasteboard changes and auto-strip when enabled.
        Timer.scheduledTimer(withTimeInterval: 0.333, repeats: true) { [weak self] _ in
            guard let self else { return }
            let pb = NSPasteboard.general
            let currentCount = pb.changeCount
            if currentCount != self.pasteboardChangeCount {
                self.pasteboardChangeCount = currentCount
                guard self.autoStripEnabled else { return }

                // Debounce: wait briefly to let the writer finish updating all representations.
                self.debounceWork?.cancel()
                let work = DispatchWorkItem { [weak self] in
                    self?.stripNow()
                }
                self.debounceWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
            }
        }
        
        registerStripAndPasteHotKey()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            let trust = self?.isProcessTrusted()
            print("Has Accessibility Permission: ", trust?.description ?? "unknown")
        }
    }
    
    private func isProcessTrusted() -> Bool {
        let options: NSDictionary = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSString: true
        ]
        
        return AXIsProcessTrustedWithOptions(options)
    }
    
    private func pasteIntoFrontmostApp() {
        print("Posting synthetic Command-V")

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
    
    private func stripAndPaste() {
        guard isProcessTrusted() else {
            print("App does not have accessibility permissions to simulate paste command. Skipping.")
            return
        }
        stripNow()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) { [weak self] in
            self?.pasteIntoFrontmostApp()
        }
    }
    
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
            print("InstallEventHandler failed:", handlerStatus)
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
            print("RegisterEventHotKey failed:", hotKeyStatus)
            if let hotKeyHandler {
                RemoveEventHandler(hotKeyHandler)
                self.hotKeyHandler = nil
            }

            handleHotKeyRegistrationFailure(hotKeyStatus)
            return
        }

        hotKeyRegistrationFailed = false
        retryHotKeyItem?.isHidden = true
        print("Registered global hotkey: Control-Option-Command-V")
    }

    private func handleHotKeyRegistrationFailure(_ status: OSStatus) {
        hotKeyRegistrationFailed = true
        retryHotKeyItem?.isHidden = false

        let message: String
        if status == eventHotKeyExistsErr {
            message = "The paste shortcut Control-Option-Command-V is already used by another app. Unformat will keep running, but the global paste shortcut is disabled."
        } else {
            message = "Unformat could not register the paste shortcut Control-Option-Command-V. Error code: \(status). Unformat will keep running, but the global paste shortcut is disabled."
        }

        showHotKeyRegistrationAlert(message: message)
    }

    private func showHotKeyRegistrationAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = "Paste Shortcut Disabled"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

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

    func applicationWillTerminate(_ notification: Notification) {
        // Tear down resources if needed
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        
        if let hotKeyHandler {
            RemoveEventHandler(hotKeyHandler)
        }
    }
    
    private func makeAutoStripToggleView() -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 40))

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
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            toggle.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            toggle.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            label.trailingAnchor.constraint(lessThanOrEqualTo: toggle.leadingAnchor, constant: -12)
        ])

        return container
    }

    @objc private func toggleAutomaticStrippingFromSwitch(_ sender: NSSwitch) {
        autoStripEnabled = sender.state == .on
    }

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
    
    private func containsRichTextRepresentation(_ types: [NSPasteboard.PasteboardType]) -> Bool {
        types.contains { type in
            isRichTextLike(type)
        }
    }

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

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
