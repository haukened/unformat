import AppKit
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.statusItem = statusItem

        if let button = statusItem.button {
            button.title = "U"
        }

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
        requestAccessibilityPermissionIfNeeded()
    }
    
    private func pasteIntoFrontmostApp() {
        let source = CGEventSource(stateID: .combinedSessionState)

        let keyDown = CGEvent(
            keyboardEventSource: source,
            virtualKey: CGKeyCode(kVK_ANSI_V),
            keyDown: true
        )
        keyDown?.flags = .maskCommand

        let keyUp = CGEvent(
            keyboardEventSource: source,
            virtualKey: CGKeyCode(kVK_ANSI_V),
            keyDown: false
        )
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
    
    private func ensureAccessibilityPermission() -> Bool {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true
        ] as CFDictionary

        return AXIsProcessTrustedWithOptions(options)
    }

    private func requestAccessibilityPermissionIfNeeded() {
        guard !AXIsProcessTrusted() else {
            return
        }

        _ = ensureAccessibilityPermission()
    }
    
    private func stripAndPaste() {
        guard ensureAccessibilityPermission() else {
            return
        }
        
        stripNow()
        pasteIntoFrontmostApp()
    }
    
    private func registerStripAndPasteHotKey() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
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

        let hotKeyID = EventHotKeyID(
            signature: OSType("UNFT".fourCharCode),
            id: 1
        )

        let modifiers = UInt32(cmdKey | optionKey | controlKey)

        RegisterEventHotKey(
            UInt32(kVK_ANSI_V),
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
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
