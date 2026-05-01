import AppKit
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var autoStripEnabled: Bool = false
    private var pasteboardChangeCount: Int = NSPasteboard.general.changeCount
    private var debounceWork: DispatchWorkItem?
    private var clipboardTypesItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.statusItem = statusItem

        if let button = statusItem.button {
            button.title = "U"
        }

        let menu = NSMenu()

        let clipboardTypesItem = NSMenuItem(
            title: currentClipboardTypesTitle(),
            action: #selector(refreshClipboardTypes(_:)),
            keyEquivalent: ""
        )
        clipboardTypesItem.target = self
        self.clipboardTypesItem = clipboardTypesItem
        menu.addItem(clipboardTypesItem)

        let debugItem = NSMenuItem(
            title: "Print Clipboard Debug Info",
            action: #selector(printClipboardDebugInfo),
            keyEquivalent: ""
        )
        debugItem.target = self
        menu.addItem(debugItem)

        menu.addItem(.separator())

        let autoItem = NSMenuItem(
            title: "Automatic Stripping",
            action: #selector(toggleAutomaticStripping(_:)),
            keyEquivalent: ""
        )
        autoItem.target = self
        autoItem.state = autoStripEnabled ? .on : .off
        menu.addItem(autoItem)

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
            keyEquivalent: "q"
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
                self.updateClipboardTypesMenuItem()
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
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Tear down resources if needed
    }
    
    @objc private func toggleAutomaticStripping(_ sender: NSMenuItem) {
        autoStripEnabled.toggle()
        sender.state = autoStripEnabled ? .on : .off
    }

    @objc private func refreshClipboardTypes(_ sender: NSMenuItem) {
        updateClipboardTypesMenuItem()
    }

    @objc private func printClipboardDebugInfo() {
        let pasteboard = NSPasteboard.general
        let types = pasteboard.types ?? []
        let hasString = pasteboard.canReadObject(forClasses: [NSString.self], options: nil)
        let hasImage = pasteboard.canReadObject(forClasses: [NSImage.self], options: nil)
        let plainText = pasteboard.string(forType: .string)

        print("----- Clipboard Debug -----")
        print("changeCount:", pasteboard.changeCount)
        print("has NSString:", hasString)
        print("has NSImage:", hasImage)
        print("has rich text:", containsRichTextRepresentation(types))
        print("has file-like type:", types.contains(where: isFileLike))
        print("plain text length:", plainText?.count ?? 0)
        print("should strip:", shouldStripClipboard(pasteboard))
        print("types:")

        for type in types {
            print("-", type.rawValue)
            print("  friendly:", friendlyName(for: type))
            print("  rich:", isRichTextLike(type))
            print("  file:", isFileLike(type))
            print("  image:", isImageLike(type))
            print("  binary:", isBinaryDocumentLike(type))

            if let uniformType = UTType(type.rawValue) {
                print("  utType:", uniformType.identifier)
                print("  conforms plainText:", uniformType.conforms(to: .plainText))
                print("  conforms text:", uniformType.conforms(to: .text))
                print("  conforms rtf:", uniformType.conforms(to: .rtf))
                print("  conforms rtfd:", uniformType.conforms(to: .rtfd))
                print("  conforms html:", uniformType.conforms(to: .html))
                print("  conforms image:", uniformType.conforms(to: .image))
                print("  conforms fileURL:", uniformType.conforms(to: .fileURL))
            } else {
                print("  utType: nil")
            }
        }

        print("---------------------------")
    }

    private func updateClipboardTypesMenuItem() {
        clipboardTypesItem?.title = currentClipboardTypesTitle()
    }

    private func currentClipboardTypesTitle() -> String {
        let pasteboard = NSPasteboard.general
        let types = pasteboard.types ?? []

        guard !types.isEmpty else {
            return "Clipboard Types: Empty"
        }

        let detectedTypes = types
            .map { friendlyName(for: $0) }
            .uniquedPreservingOrder()

        return "Clipboard Types: " + detectedTypes.joined(separator: ", ")
    }

    private func friendlyName(for type: NSPasteboard.PasteboardType) -> String {
        switch type {
        case .string:
            return "Plain Text"
        case .rtf:
            return "RTF"
        case .rtfd:
            return "RTFD"
        case .html:
            return "HTML"
        case .png:
            return "PNG"
        case .tiff:
            return "TIFF"
        case .fileURL:
            return "File URL"
        case NSPasteboard.PasteboardType("NeXT Rich Text Format"):
            return "NeXT RTF"
        case NSPasteboard.PasteboardType("com.microsoft.Object-Descriptor"):
            return "Microsoft Object Descriptor"
        default:
            return type.rawValue
        }
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
        pasteboard.setString(plainText, forType: .string)
        pasteboardChangeCount = pasteboard.changeCount
        updateClipboardTypesMenuItem()
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

    private func containsBlockedNonTextContent(_ types: [NSPasteboard.PasteboardType], pasteboard: NSPasteboard) -> Bool {
        // Kept for debug output/backward compatibility with earlier logic.
        // The strip decision now only blocks file-like clipboard payloads.
        return types.contains(where: isFileLike)
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

    private func isImageLike(_ type: NSPasteboard.PasteboardType) -> Bool {
        switch type {
        case .png, .tiff:
            return true
        default:
            break
        }

        guard let uniformType = UTType(type.rawValue) else {
            return false
        }

        return uniformType.conforms(to: .image)
    }

    private func isBinaryDocumentLike(_ type: NSPasteboard.PasteboardType) -> Bool {
        let rawValue = type.rawValue.lowercased()

        if rawValue.contains("pdf")
            || rawValue.contains("postscript")
            || rawValue.contains("movie")
            || rawValue.contains("audio")
            || rawValue.contains("video") {
            return true
        }

        guard let uniformType = UTType(type.rawValue) else {
            return false
        }

        return uniformType.conforms(to: .pdf)
            || uniformType.conforms(to: .movie)
            || uniformType.conforms(to: .audio)
            || uniformType.conforms(to: .video)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

private extension Array where Element: Hashable {
    func uniquedPreservingOrder() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
