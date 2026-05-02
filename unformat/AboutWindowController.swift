import AppKit

/// Handles window-local keyboard shortcuts for the About panel.
private final class AboutWindow: NSWindow {
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            performClose(nil)
            return
        }

        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers?.lowercased() == "w" {
            performClose(nil)
            return
        }

        super.keyDown(with: event)
    }
}

/// Draws a rounded branded button with an inset image instead of relying on AppKit's default bezel layout.
private final class BrandImageButton: NSButton {
    private let insetImageView = NSImageView()

    init(
        image: NSImage,
        backgroundColor: NSColor,
        cornerRadius: CGFloat,
        contentInsets: NSEdgeInsets,
        target: AnyObject?,
        action: Selector?,
        accessibilityLabel: String
    ) {
        super.init(frame: .zero)

        self.target = target
        self.action = action
        self.isBordered = false
        self.title = ""
        self.imagePosition = .noImage
        self.translatesAutoresizingMaskIntoConstraints = false
        self.setButtonType(.momentaryChange)
        self.wantsLayer = true
        self.layer?.backgroundColor = backgroundColor.cgColor
        self.layer?.cornerRadius = cornerRadius
        self.layer?.masksToBounds = true
        self.setAccessibilityLabel(accessibilityLabel)

        insetImageView.image = image
        insetImageView.imageScaling = .scaleProportionallyDown
        insetImageView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(insetImageView)

        NSLayoutConstraint.activate([
            insetImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: contentInsets.left),
            insetImageView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -contentInsets.right),
            insetImageView.topAnchor.constraint(equalTo: topAnchor, constant: contentInsets.top),
            insetImageView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -contentInsets.bottom)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateLayer() {
        super.updateLayer()
        layer?.opacity = isHighlighted ? 0.85 : 1
    }
}

/// Presents a lightweight About window for the menu bar app.
final class AboutWindowController: NSWindowController {
    private enum UI {
        static let windowSize = NSSize(width: 420, height: 320)
        static let iconSize = NSSize(width: 96, height: 96)
        static let githubButtonSize = NSSize(width: 184, height: 44)
        static let beerButtonSize = NSSize(width: 184, height: 44)
        static let horizontalInset: CGFloat = 24
        static let verticalInset: CGFloat = 24
        static let contentSpacing: CGFloat = 14
        static let buttonSpacing: CGFloat = 10
        static let githubButtonCornerRadius: CGFloat = 8
        static let githubButtonInsets = NSEdgeInsets(top: 10, left: 18, bottom: 10, right: 18)
        static let beerButtonCornerRadius: CGFloat = 8
        static let buttonBackgroundColor = NSColor(
            calibratedRed: 48 / 255,
            green: 55 / 255,
            blue: 65 / 255,
            alpha: 1
        )
    }

    private enum Asset {
        static let githubLockupBlack = "GitHub_Lockup_Black"
        static let githubLockupWhite = "GitHub_Lockup_White"
    }

    private enum Link {
        static let website = URL(string: "https://unformat.hauken.us")!
        static let github = URL(string: "https://github.com/haukened/unformat")!
        static let beer = URL(string: "https://beer.hauken.us")!
        static let gplv3 = URL(string: "https://www.gnu.org/licenses/gpl-3.0.en.html")!
    }

    init() {
        let window = AboutWindow(
            contentRect: NSRect(origin: .zero, size: UI.windowSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        window.title = "About Unformat"
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
        window.contentView = makeContentView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Brings the about window forward even though the app runs without a Dock icon.
    func present() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Builds the window contents using simple AppKit stack views.
    private func makeContentView() -> NSView {
        let container = NSView(frame: NSRect(origin: .zero, size: UI.windowSize))

        let contentStack = NSStackView(views: [
            makeIconView(),
            makeAppNameLabel(),
            makeVersionLabel(),
            makeWebsiteButton(),
            makeCopyrightLabel(),
            makeLicenseButton(),
            makeButtonRow()
        ])

        contentStack.orientation = .vertical
        contentStack.alignment = .centerX
        contentStack.spacing = UI.contentSpacing
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(contentStack)

        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: UI.horizontalInset),
            contentStack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -UI.horizontalInset),
            contentStack.topAnchor.constraint(equalTo: container.topAnchor, constant: UI.verticalInset),
            contentStack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -UI.verticalInset),
            contentStack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            contentStack.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        return container
    }

    /// Uses the application icon already bundled with the app.
    private func makeIconView() -> NSImageView {
        let imageView = NSImageView()
        imageView.image = NSApp.applicationIconImage
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: UI.iconSize.width),
            imageView.heightAnchor.constraint(equalToConstant: UI.iconSize.height)
        ])

        return imageView
    }

    /// Displays the localized bundle name when available.
    private func makeAppNameLabel() -> NSTextField {
        let label = NSTextField(labelWithString: bundleDisplayName)
        label.font = .systemFont(ofSize: 24, weight: .semibold)
        label.alignment = .center
        return label
    }

    /// Reads the version metadata from the app bundle's info dictionary.
    private func makeVersionLabel() -> NSTextField {
        let label = NSTextField(labelWithString: versionDescription)
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        return label
    }

    /// Provides a clickable website link in the body of the About window.
    private func makeWebsiteButton() -> NSButton {
        let button = NSButton(title: Link.website.absoluteString, target: self, action: #selector(openWebsite))
        button.isBordered = false
        button.bezelStyle = .inline
        button.contentTintColor = .systemBlue

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor.systemBlue,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        button.attributedTitle = NSAttributedString(string: Link.website.absoluteString, attributes: attributes)

        return button
    }

    /// Displays the copyright owner and the built app's year.
    private func makeCopyrightLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "Copyright \(copyrightSymbol) \(buildYear) David Haukeness")
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        return label
    }

    /// Provides a direct hyperlink to the GPL v3 license text.
    private func makeLicenseButton() -> NSButton {
        let button = NSButton(title: "Distributed under the GNU GPL v3", target: self, action: #selector(openGPLv3))
        button.isBordered = false
        button.bezelStyle = .inline
        button.contentTintColor = .systemBlue

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.systemBlue,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        button.attributedTitle = NSAttributedString(
            string: "Distributed under the GNU GPL v3",
            attributes: attributes
        )

        return button
    }

    /// Groups the primary outbound actions at the bottom of the window.
    private func makeButtonRow() -> NSStackView {
        let githubButton = makeGitHubButton()
        let beerButton = makeBeerButton()

        let stack = NSStackView(views: [githubButton, beerButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = UI.buttonSpacing
        return stack
    }

    /// Creates a GitHub button that uses the bundled GitHub lockup asset and brand styling.
    private func makeGitHubButton() -> NSButton {
        let button = BrandImageButton(
            image: githubButtonImage,
            backgroundColor: githubBrandColor,
            cornerRadius: UI.githubButtonCornerRadius,
            contentInsets: UI.githubButtonInsets,
            target: self,
            action: #selector(openGitHub),
            accessibilityLabel: "View on GitHub"
        )

        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: UI.githubButtonSize.width),
            button.heightAnchor.constraint(equalToConstant: UI.githubButtonSize.height)
        ])

        return button
    }

    /// Creates a monospace support button that matches the GitHub button's overall size.
    private func makeBeerButton() -> NSButton {
        let button = NSButton(title: "", target: self, action: #selector(openBeerLink))
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.wantsLayer = true
        button.layer?.backgroundColor = UI.buttonBackgroundColor.cgColor
        button.layer?.cornerRadius = UI.beerButtonCornerRadius

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        button.attributedTitle = NSAttributedString(string: "🍺 Buy me a Beer", attributes: attributes)

        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: UI.beerButtonSize.width),
            button.heightAnchor.constraint(equalToConstant: UI.beerButtonSize.height)
        ])

        return button
    }

    private var bundleDisplayName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Unformat"
    }

    private var buildYear: Int {
        let buildDate = bundleBuildDate ?? Date()
        return Calendar.current.component(.year, from: buildDate)
    }

    /// Uses the bundle's file metadata as a proxy for when this app build was produced.
    private var bundleBuildDate: Date? {
        guard let resourceValues = try? Bundle.main.bundleURL.resourceValues(forKeys: [.contentModificationDateKey]) else {
            return nil
        }

        return resourceValues.contentModificationDate
    }

    private let copyrightSymbol: String = "\u{00A9}"

    /// Uses the white GitHub lockup on the standard dark GitHub background.
    private var githubButtonImage: NSImage {
        NSImage(named: Asset.githubLockupWhite) ?? NSImage()
    }

    private var githubBrandColor: NSColor {
        UI.buttonBackgroundColor
    }

    private var versionDescription: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let buildVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        switch (shortVersion, buildVersion) {
        case let (shortVersion?, buildVersion?) where shortVersion != buildVersion:
            return "Version \(shortVersion) (\(buildVersion))"
        case let (shortVersion?, _):
            return "Version \(shortVersion)"
        case let (_, buildVersion?):
            return "Version \(buildVersion)"
        default:
            return "Version unavailable"
        }
    }

    /// Opens the project website in the user's default browser.
    @objc private func openWebsite() {
        NSWorkspace.shared.open(Link.website)
    }

    /// Opens the public source repository in the user's default browser.
    @objc private func openGitHub() {
        NSWorkspace.shared.open(Link.github)
    }

    /// Opens the support link in the user's default browser.
    @objc private func openBeerLink() {
        NSWorkspace.shared.open(Link.beer)
    }

    /// Opens the GNU GPL v3 license in the user's default browser.
    @objc private func openGPLv3() {
        NSWorkspace.shared.open(Link.gplv3)
    }
}
