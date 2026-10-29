import AppKit
import UniformTypeIdentifiers

final class LogWindowController: NSWindowController {
    private let textView = NSTextView()
    private let scrollView = NSScrollView()

    convenience init() {
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 820, height: 560),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable],
                              backing: .buffered,
                              defer: false)
        window.title = "Журнал RDP Mac"
        window.minSize = NSSize(width: 640, height: 400)
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("RDPMacLogWindow")
        self.init(window: window)
        buildUI()
        NotificationCenter.default.addObserver(self, selector: #selector(refresh),
                                               name: LogStore.didChange, object: nil)
        refresh()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.documentView = textView

        let export = UI.button("Экспорт…", target: self, action: #selector(exportLog(_:)))
        let clear = UI.button("Очистить журнал", target: self, action: #selector(clearLog(_:)))
        let close = UI.button("Закрыть", target: self, action: #selector(closeWindow(_:)))
        let buttons = UI.hStack([export, clear, NSView(), close], spacing: 8)
        buttons.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(scrollView)
        content.addSubview(buttons)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            scrollView.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            scrollView.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -10),
            buttons.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            buttons.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            buttons.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12)
        ])
    }

    @objc func refresh() {
        textView.string = LogStore.shared.text()
        textView.scrollToEndOfDocument(nil)
    }

    @objc private func exportLog(_ sender: Any?) {
        guard let window else { return }
        let panel = NSSavePanel()
        panel.title = "Экспорт журнала"
        panel.nameFieldStringValue = "rdp-mac-log.txt"
        panel.allowedContentTypes = [.plainText]
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try LogStore.shared.export(to: url)
                LogStore.shared.append("Журнал экспортирован: \(url.lastPathComponent)", level: 0)
            } catch {
                LogStore.shared.append("Не удалось экспортировать журнал: "
                                       + error.localizedDescription, level: 2)
            }
        }
    }

    @objc private func clearLog(_ sender: Any?) {
        LogStore.shared.clear()
    }

    @objc private func closeWindow(_ sender: Any?) {
        close()
    }
}
