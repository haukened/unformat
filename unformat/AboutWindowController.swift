import AppKit

/// Presents a lightweight About window for the menu bar app.
final class AboutWindowController: NSWindowController {
    private enum UI {
        static let windowSize = NSSize(width: 420, height: 320)
        static let iconSize = NSSize(width: 96, height: 96)
        static let horizontalInset: CGFloat = 24
        static let verticalInset: CGFloat = 24
        static let contentSpacing: CGFloat = 14
        static let buttonSpacing: CGFloat = 10
    }

    private enum Link {
        static let website = URL(string: "https://unformat.hauken.us")!
        static let github = URL(string: "https://github.com/haukened/unformat")!
        static let beer = URL(string: "https://beer.hauken.us")!
    }

    init() {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: UI.windowSize),
            styleMask: [.titled, .closable, .miniaturizable],
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
        button.setButtonType(.momentaryPushIn)
        button.bezelStyle = .inline
        return button
    }

    /// Groups the primary outbound actions at the bottom of the window.
    private func makeButtonRow() -> NSStackView {
        let githubButton = NSButton(title: "View on GitHub", target: self, action: #selector(openGitHub))
        githubButton.bezelStyle = .rounded

        let beerButton = NSButton(title: "Buy Me A Beer", target: self, action: #selector(openBeerLink))
        beerButton.bezelStyle = .rounded

        let stack = NSStackView(views: [githubButton, beerButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = UI.buttonSpacing
        return stack
    }

    private var bundleDisplayName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Unformat"
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
}
