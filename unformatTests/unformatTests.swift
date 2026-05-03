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

struct ClipboardMonitorTests {
    @Test
    func ignoresUnchangedPasteboardCount() {
        var scheduledWorkItems: [DispatchWorkItem] = []
        let monitor = ClipboardMonitor(
            initialChangeCount: 5,
            debounceInterval: 0.15
        ) { _, work in
            scheduledWorkItems.append(work)
        }
        var invocationCount = 0

        monitor.processChangeCount(5, autoStripEnabled: true) {
            invocationCount += 1
        }

        #expect(scheduledWorkItems.isEmpty)
        #expect(invocationCount == 0)
    }

    @Test
    func updatesObservedCountWithoutSchedulingWhenAutoStripIsDisabled() {
        var scheduledWorkItems: [DispatchWorkItem] = []
        let monitor = ClipboardMonitor(
            initialChangeCount: 1,
            debounceInterval: 0.15
        ) { _, work in
            scheduledWorkItems.append(work)
        }
        var invocationCount = 0

        monitor.processChangeCount(2, autoStripEnabled: false) {
            invocationCount += 1
        }

        monitor.processChangeCount(2, autoStripEnabled: true) {
            invocationCount += 1
        }

        #expect(scheduledWorkItems.isEmpty)
        #expect(invocationCount == 0)
    }

    @Test
    func schedulesDebouncedWorkForChangedPasteboardCount() {
        var scheduledDelay: TimeInterval?
        var scheduledWork: DispatchWorkItem?
        let monitor = ClipboardMonitor(
            initialChangeCount: 1,
            debounceInterval: 0.15
        ) { delay, work in
            scheduledDelay = delay
            scheduledWork = work
        }
        var invocationCount = 0

        monitor.processChangeCount(2, autoStripEnabled: true) {
            invocationCount += 1
        }

        #expect(scheduledDelay == 0.15)
        #expect(scheduledWork != nil)
        #expect(invocationCount == 0)

        scheduledWork?.perform()

        #expect(invocationCount == 1)
    }

    @Test
    func cancelsPreviousWorkWhenAnotherChangeArrives() {
        var scheduledWorkItems: [DispatchWorkItem] = []
        let monitor = ClipboardMonitor(
            initialChangeCount: 1,
            debounceInterval: 0.15
        ) { _, work in
            scheduledWorkItems.append(work)
        }
        var invocationCount = 0

        monitor.processChangeCount(2, autoStripEnabled: true) {
            invocationCount += 1
        }
        monitor.processChangeCount(3, autoStripEnabled: true) {
            invocationCount += 1
        }

        #expect(scheduledWorkItems.count == 2)
        #expect(scheduledWorkItems[0].isCancelled)
        #expect(!scheduledWorkItems[1].isCancelled)

        scheduledWorkItems[0].perform()
        scheduledWorkItems[1].perform()

        #expect(invocationCount == 1)
    }

    @Test
    func canUpdateObservedCountAfterDirectClipboardMutation() {
        var scheduledWorkItems: [DispatchWorkItem] = []
        let monitor = ClipboardMonitor(
            initialChangeCount: 1,
            debounceInterval: 0.15
        ) { _, work in
            scheduledWorkItems.append(work)
        }

        monitor.updateObservedChangeCount(10)
        monitor.processChangeCount(10, autoStripEnabled: true) {}

        #expect(scheduledWorkItems.isEmpty)
    }

    @Test
    func cancelPendingWorkCancelsLatestScheduledItem() {
        var scheduledWorkItems: [DispatchWorkItem] = []
        let monitor = ClipboardMonitor(
            initialChangeCount: 1,
            debounceInterval: 0.15
        ) { _, work in
            scheduledWorkItems.append(work)
        }

        monitor.processChangeCount(2, autoStripEnabled: true) {}
        monitor.cancelPendingWork()

        #expect(scheduledWorkItems.count == 1)
        #expect(scheduledWorkItems[0].isCancelled)
    }
}
