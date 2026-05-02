import AppKit
import UniformTypeIdentifiers

/// Rewrites rich-text clipboard content to plain text when it is safe to do so.
final class ClipboardStripper {
    /// Replaces the given pasteboard contents with plain text when rich text is present.
    @discardableResult
    func stripIfNeeded(_ pasteboard: NSPasteboard) -> Bool {
        guard shouldStripClipboard(pasteboard) else {
            return false
        }

        guard let plainText = pasteboard.string(forType: .string), !plainText.isEmpty else {
            return false
        }

        pasteboard.clearContents()
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString(plainText, forType: .string)
        return true
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
}
