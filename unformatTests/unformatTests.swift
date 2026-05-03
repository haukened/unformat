import AppKit
import Testing
@testable import unformat

struct ClipboardStripperTests {
    @Test
    func stripsRichTextToPlainText() {
        let pasteboard = makePasteboard()
        let stripper = ClipboardStripper()

        pasteboard.declareTypes([.string, .rtf], owner: nil)
        pasteboard.setString("Hello, world!", forType: .string)
        pasteboard.setData(Data("{\\rtf1\\ansi Hello, world!}".utf8), forType: .rtf)

        let didStrip = stripper.stripIfNeeded(pasteboard)

        #expect(didStrip)
        #expect(pasteboard.string(forType: .string) == "Hello, world!")
        #expect(pasteboard.types?.contains(.string) == true)
        #expect(pasteboard.types?.contains(.rtf) == false)
    }

    @Test
    func doesNotStripPlainTextOnlyClipboard() {
        let pasteboard = makePasteboard()
        let stripper = ClipboardStripper()

        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString("Already plain text", forType: .string)

        let didStrip = stripper.stripIfNeeded(pasteboard)

        #expect(!didStrip)
        #expect(pasteboard.string(forType: .string) == "Already plain text")
        #expect(pasteboard.types?.contains(.string) == true)
        #expect(pasteboard.types?.contains(.rtf) == false)
    }

    @Test
    func doesNotStripWhenReadableTextIsMissing() {
        let pasteboard = makePasteboard()
        let stripper = ClipboardStripper()
        let unreadableRichTextType = NSPasteboard.PasteboardType("com.example.rtf-fragment")

        pasteboard.declareTypes([unreadableRichTextType], owner: nil)
        pasteboard.setData(Data([0x00, 0xFF, 0x10, 0x80]), forType: unreadableRichTextType)

        let didStrip = stripper.stripIfNeeded(pasteboard)

        #expect(!didStrip)
        #expect(pasteboard.string(forType: .string) == nil)
        #expect(pasteboard.types?.contains(unreadableRichTextType) == true)
    }

    @Test
    func doesNotStripWhenPlainTextIsEmpty() {
        let pasteboard = makePasteboard()
        let stripper = ClipboardStripper()

        pasteboard.declareTypes([.string, .html], owner: nil)
        pasteboard.setString("", forType: .string)
        pasteboard.setString("<b></b>", forType: .html)

        let didStrip = stripper.stripIfNeeded(pasteboard)

        #expect(!didStrip)
        #expect(pasteboard.string(forType: .string) == "")
        #expect(pasteboard.types?.contains(.html) == true)
    }

    @Test
    func doesNotStripWhenFileURLPayloadIsPresent() {
        let pasteboard = makePasteboard()
        let stripper = ClipboardStripper()

        pasteboard.declareTypes([.string, .rtf, .fileURL], owner: nil)
        pasteboard.setString("File label", forType: .string)
        pasteboard.setData(Data("{\\rtf1\\ansi File label}".utf8), forType: .rtf)
        pasteboard.setString("file:///tmp/example.txt", forType: .fileURL)

        let didStrip = stripper.stripIfNeeded(pasteboard)

        #expect(!didStrip)
        #expect(pasteboard.types?.contains(.fileURL) == true)
        #expect(pasteboard.types?.contains(.rtf) == true)
    }

    @Test
    func stripsLegacyNamedRichTextType() {
        let pasteboard = makePasteboard()
        let stripper = ClipboardStripper()
        let legacyRichTextType = NSPasteboard.PasteboardType("NeXT Rich Text Format")

        pasteboard.declareTypes([.string, legacyRichTextType], owner: nil)
        pasteboard.setString("Legacy text", forType: .string)
        pasteboard.setData(Data("legacy".utf8), forType: legacyRichTextType)

        let didStrip = stripper.stripIfNeeded(pasteboard)

        #expect(didStrip)
        #expect(pasteboard.string(forType: .string) == "Legacy text")
        #expect(pasteboard.types?.contains(.string) == true)
        #expect(pasteboard.types?.contains(legacyRichTextType) == false)
    }

    @Test
    func stripsUniformTypeRichTextRepresentation() {
        let pasteboard = makePasteboard()
        let stripper = ClipboardStripper()
        let publicRTF = NSPasteboard.PasteboardType("public.rtf")

        pasteboard.declareTypes([.string, publicRTF], owner: nil)
        pasteboard.setString("UTType text", forType: .string)
        pasteboard.setData(Data("{\\rtf1\\ansi UTType text}".utf8), forType: publicRTF)

        let didStrip = stripper.stripIfNeeded(pasteboard)

        #expect(didStrip)
        #expect(pasteboard.string(forType: .string) == "UTType text")
        #expect(pasteboard.types?.contains(.string) == true)
        #expect(pasteboard.types?.contains(publicRTF) == false)
    }

    @Test
    func doesNotStripLegacyFileNamePayload() {
        let pasteboard = makePasteboard()
        let stripper = ClipboardStripper()
        let legacyFileNameType = NSPasteboard.PasteboardType("NSFilenamesPboardType")

        pasteboard.declareTypes([.string, .html, legacyFileNameType], owner: nil)
        pasteboard.setString("File selection", forType: .string)
        pasteboard.setString("<p>File selection</p>", forType: .html)
        pasteboard.setPropertyList(["/tmp/example.txt"], forType: legacyFileNameType)

        let didStrip = stripper.stripIfNeeded(pasteboard)

        #expect(!didStrip)
        #expect(pasteboard.types?.contains(legacyFileNameType) == true)
        #expect(pasteboard.types?.contains(.html) == true)
    }

    private func makePasteboard() -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        pasteboard.clearContents()
        return pasteboard
    }
}
