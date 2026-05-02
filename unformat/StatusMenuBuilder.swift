import AppKit

/// Creates the status item title and menu used by the menu bar app.
enum StatusMenuBuilder {
    private enum UI {
        static let statusItemFontSize: CGFloat = 18
        static let statusItemBaselineOffset: CGFloat = -3
        static let toggleContainerSize = NSSize(width: 280, height: 40)
        static let horizontalInset: CGFloat = 14
        static let labelSpacing: CGFloat = 12
    }

    /// Creates the attributed title shown in the menu bar.
    static func makeStatusItemTitle() -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: UI.statusItemFontSize, weight: .bold),
            .paragraphStyle: paragraph,
            .baselineOffset: UI.statusItemBaselineOffset
        ]

        return NSAttributedString(string: "U", attributes: attributes)
    }

    /// Builds the menu used by the app's status item.
    static func makeMenu(
        target: AnyObject,
        autoStripEnabled: Bool,
        toggleAction: Selector,
        stripAction: Selector,
        aboutAction: Selector,
        quitAction: Selector
    ) -> NSMenu {
        let menu = NSMenu()

        let autoItem = NSMenuItem()
        autoItem.view = makeAutoStripToggleView(
            target: target,
            autoStripEnabled: autoStripEnabled,
            action: toggleAction
        )
        menu.addItem(autoItem)
        menu.addItem(.separator())

        let stripItem = NSMenuItem(
            title: "Strip Clipboard Now",
            action: stripAction,
            keyEquivalent: ""
        )
        stripItem.target = target
        stripItem.image = NSImage(
            systemSymbolName: "eraser",
            accessibilityDescription: "Strip Clipboard Now"
        )
        menu.addItem(stripItem)

        let aboutItem = NSMenuItem(
            title: "About Unformat",
            action: aboutAction,
            keyEquivalent: ""
        )
        aboutItem.target = target
        menu.addItem(aboutItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit Unformat",
            action: quitAction,
            keyEquivalent: ""
        )
        quitItem.target = target
        menu.addItem(quitItem)

        return menu
    }

    /// Creates the custom menu row that pairs the automatic mode label with its switch.
    private static func makeAutoStripToggleView(
        target: AnyObject,
        autoStripEnabled: Bool,
        action: Selector
    ) -> NSView {
        let container = NSView(frame: NSRect(origin: .zero, size: UI.toggleContainerSize))

        let label = NSTextField(labelWithString: "Automatic Stripping")
        label.font = .menuFont(ofSize: 0)
        label.translatesAutoresizingMaskIntoConstraints = false

        let toggle = NSSwitch()
        toggle.state = autoStripEnabled ? .on : .off
        toggle.target = target
        toggle.action = action
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
}
