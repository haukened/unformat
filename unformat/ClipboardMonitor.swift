import Foundation

/// Tracks pasteboard changes and debounces automatic strip actions.
final class ClipboardMonitor {
    typealias Scheduler = (_ delay: TimeInterval, _ work: DispatchWorkItem) -> Void

    private let debounceInterval: TimeInterval
    private let scheduler: Scheduler
    private var lastObservedChangeCount: Int
    private var pendingWork: DispatchWorkItem?

    init(
        initialChangeCount: Int,
        debounceInterval: TimeInterval,
        scheduler: @escaping Scheduler = { delay, work in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    ) {
        self.lastObservedChangeCount = initialChangeCount
        self.debounceInterval = debounceInterval
        self.scheduler = scheduler
    }

    /// Updates the monitor with the latest pasteboard change count and schedules work when needed.
    func processChangeCount(
        _ currentChangeCount: Int,
        autoStripEnabled: Bool,
        perform: @escaping () -> Void
    ) {
        guard currentChangeCount != lastObservedChangeCount else {
            return
        }

        lastObservedChangeCount = currentChangeCount

        guard autoStripEnabled else {
            return
        }

        pendingWork?.cancel()

        let work = DispatchWorkItem(block: perform)
        pendingWork = work
        scheduler(debounceInterval, work)
    }

    /// Stores the latest pasteboard change count after the app mutates the clipboard directly.
    func updateObservedChangeCount(_ changeCount: Int) {
        lastObservedChangeCount = changeCount
    }

    /// Cancels any pending debounced work.
    func cancelPendingWork() {
        pendingWork?.cancel()
        pendingWork = nil
    }
}
