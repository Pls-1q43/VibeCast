import AppKit
import Sparkle

final class AboutWindowController: NSWindowController {
    private let updaterController: SPUStandardUpdaterController
    private let projectURL = URL(string: "https://github.com/Pls-1q43/VibeCast")!
    private let authorURL = URL(string: "https://x.com/JeffreyCalm")!

    init(updaterController: SPUStandardUpdaterController) {
        self.updaterController = updaterController

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 250),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = MacI18n.t("aboutWindowTitle")
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
        window.contentView = makeContentView()
    }

    required init?(coder: NSCoder) {
        nil
    }

    private func makeContentView() -> NSView {
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView(image: appIcon())
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.imageScaling = .scaleProportionallyUpOrDown

        let title = label("VibeCast", font: .systemFont(ofSize: 24, weight: .semibold), alignment: .center)
        let version = label(MacI18n.f("aboutVersion", AppVersion.display), font: .systemFont(ofSize: 13), alignment: .center)
        version.textColor = .secondaryLabelColor

        let checkUpdates = NSButton(title: MacI18n.t("checkForUpdates"), target: updaterController, action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)))
        checkUpdates.translatesAutoresizingMaskIntoConstraints = false

        let project = linkButton(MacI18n.t("projectHomepage"), action: #selector(openProjectHomepage))
        let author = linkButton(MacI18n.t("authorX"), action: #selector(openAuthorX))

        let links = NSStackView(views: [project, author])
        links.translatesAutoresizingMaskIntoConstraints = false
        links.orientation = .horizontal
        links.alignment = .centerY
        links.distribution = .fillEqually
        links.spacing = 12

        let stack = NSStackView(views: [icon, title, version, checkUpdates, links])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12

        root.addSubview(stack)

        NSLayoutConstraint.activate([
            root.widthAnchor.constraint(equalToConstant: 420),
            root.heightAnchor.constraint(equalToConstant: 250),
            icon.widthAnchor.constraint(equalToConstant: 64),
            icon.heightAnchor.constraint(equalToConstant: 64),
            stack.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: root.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -24)
        ])

        return root
    }

    private func label(_ string: String, font: NSFont, alignment: NSTextAlignment) -> NSTextField {
        let field = NSTextField(labelWithString: string)
        field.translatesAutoresizingMaskIntoConstraints = false
        field.font = font
        field.alignment = alignment
        field.lineBreakMode = .byTruncatingTail
        return field
    }

    private func linkButton(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isBordered = false
        button.font = .systemFont(ofSize: 13)
        button.contentTintColor = .linkColor
        return button
    }

    private func appIcon() -> NSImage {
        if let image = NSApp.applicationIconImage, image.isValid {
            return image
        }
        return NSImage(size: NSSize(width: 64, height: 64))
    }

    @objc private func openProjectHomepage() {
        NSWorkspace.shared.open(projectURL)
    }

    @objc private func openAuthorX() {
        NSWorkspace.shared.open(authorURL)
    }
}
