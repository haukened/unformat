import Carbon

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

/// Encapsulates global Carbon hot key registration and teardown.
final class HotKeyManager {
    private let onHotKeyPressed: () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?

    init(onHotKeyPressed: @escaping () -> Void) {
        self.onHotKeyPressed = onHotKeyPressed
    }

    deinit {
        unregister()
    }

    /// Registers Control-Option-Command-V as a global shortcut.
    func register() -> OSStatus? {
        unregister()

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else {
                    return noErr
                }

                let hotKeyManager = Unmanaged<HotKeyManager>
                    .fromOpaque(userData)
                    .takeUnretainedValue()

                hotKeyManager.onHotKeyPressed()
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &hotKeyHandler
        )

        guard handlerStatus == noErr else {
            return handlerStatus
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
            unregister()
            return hotKeyStatus
        }

        return nil
    }

    /// Removes any active global hot key and event handler registration.
    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if let hotKeyHandler {
            RemoveEventHandler(hotKeyHandler)
            self.hotKeyHandler = nil
        }
    }
}
