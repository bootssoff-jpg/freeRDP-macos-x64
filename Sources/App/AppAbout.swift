import AppKit

/// Explicit credits are independent of the system's cached bundle metadata.
enum AppAbout {
    static let repositoryURL = URL(string: "https://github.com/bootssoff-jpg/freeRDP-macos-x64")!

    static var options: [NSApplication.AboutPanelOptionKey: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let credits = NSMutableAttributedString(
            string: L("Автор: %@", "NFreeZr") + "\n\n",
            attributes: [.font: NSFont.systemFont(ofSize: 13),
                         .foregroundColor: NSColor.labelColor,
                         .paragraphStyle: paragraph])
        credits.append(NSAttributedString(
            string: L("Репозиторий приложения на GitHub"),
            attributes: [.link: repositoryURL, .foregroundColor: NSColor.linkColor,
                         .font: NSFont.systemFont(ofSize: 13), .paragraphStyle: paragraph]))
        return [.applicationName: "RDP Mac", .credits: credits,
                NSApplication.AboutPanelOptionKey(rawValue: "Copyright"):
                    L("© 2026 NFreeZr. Независимый клиент на базе FreeRDP.")]
    }

    static func show() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: options)
    }
}
