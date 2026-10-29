import AppKit

final class DiagnosticsWindowController: NSWindowController {
    var onSendLocal: (() -> Void)?
    var onRequestRemote: (() -> Void)?
    var onResync: (() -> Void)?
    var onExportLog: (() -> Void)?

    private let textView = NSTextView()
    private let sendButton = UI.button("Отправить Mac → Windows", target: nil, action: nil)
    private let requestButton = UI.button("Запросить Windows → Mac", target: nil, action: nil)
    private let resyncButton = UI.button("Полная ресинхронизация", target: nil, action: nil)
    private let copyButton = UI.button("Копировать отчёт", target: nil, action: nil)
    private let exportButton = UI.button("Экспорт журнала…", target: nil, action: nil)
    private var lastReport = ""

    convenience init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 620),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable],
                              backing: .buffered,
                              defer: false)
        window.title = "Диагностика буфера обмена"
        window.minSize = NSSize(width: 640, height: 480)
        window.center()
        window.setFrameAutosaveName("RDPMacDiagnosticsWindow")
        self.init(window: window)
        buildUI()
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.autoresizingMask = [.width, .height]

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.documentView = textView

        sendButton.target = self
        sendButton.action = #selector(sendLocal(_:))
        requestButton.target = self
        requestButton.action = #selector(requestRemote(_:))
        resyncButton.target = self
        resyncButton.action = #selector(resync(_:))
        copyButton.target = self
        copyButton.action = #selector(copyReport(_:))
        exportButton.target = self
        exportButton.action = #selector(exportLog(_:))

        let firstRow = UI.hStack([sendButton, requestButton, resyncButton], spacing: 8)
        let secondRow = UI.hStack([copyButton, exportButton], spacing: 8)
        let buttons = UI.vStack([firstRow, secondRow], spacing: 8)
        buttons.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(scroll)
        content.addSubview(buttons)

        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            scroll.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
            scroll.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -10),
            buttons.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            buttons.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor,
                                              constant: -14),
            buttons.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14)
        ])
    }

    func update(diagnostics: RDPMacClipboardDiagnostics, session: String) {
        let enabled = diagnostics.enabled
        let formats = diagnostics.remoteFormats.isEmpty
            ? "—"
            : diagnostics.remoteFormats.joined(separator: ", ")
        var lines: [String] = []
        lines.append("Сеанс: \(session)")
        lines.append("")
        lines.append("CLIPRDR включён: \(diagnostics.enabled ? "да" : "нет")")
        lines.append("Канал подключён: \(diagnostics.channelConnected ? "да" : "нет")")
        lines.append("Monitor Ready: \(diagnostics.monitorReady ? "да" : "нет")")
        lines.append("Состояние: \(diagnostics.stateDescription)")
        lines.append("Локальные форматы: \(diagnostics.localFormats.joined(separator: ", "))")
        lines.append("Форматы Windows: \(formats)")
        lines.append("")
        lines.append("Объявлений Mac → Windows: \(diagnostics.localAdvertiseCount)")
        lines.append("Объявлений Windows → Mac: \(diagnostics.remoteAdvertiseCount)")
        lines.append("Отправлено пакетов: \(diagnostics.sendCount)")
        lines.append("Получено пакетов: \(diagnostics.receiveCount)")
        lines.append("Ошибок: \(diagnostics.failureCount)")
        lines.append("")
        lines.append("Последнее объявление Mac: \(diagnostics.lastLocalAdvertise ?? "—")")
        lines.append("Последнее объявление Windows: \(diagnostics.lastRemoteAdvertise ?? "—")")
        lines.append("Последняя отправка: \(diagnostics.lastLocalSend ?? "—")")
        lines.append("Последнее получение: \(diagnostics.lastRemoteReceive ?? "—")")
        lines.append("Ожидание ответа: \(diagnostics.pendingRequest ?? "—")")
        lines.append("Последняя ошибка: \(diagnostics.lastError ?? "—")")
        lines.append("")
        lines.append("Поддерживается: текст CF_UNICODETEXT (UTF-16LE) и CF_TEXT (best effort).")
        lines.append("Изображения, файлы и перенаправление папок не поддерживаются.")
        lines.append("Содержимое буфера обмена в диагностику и журнал не записывается.")
        lastReport = lines.joined(separator: "\n")
        textView.string = lastReport

        sendButton.isEnabled = enabled && diagnostics.monitorReady
        requestButton.isEnabled = enabled && diagnostics.monitorReady
        resyncButton.isEnabled = enabled && diagnostics.monitorReady
    }

    func setSessionActive(_ active: Bool) {
        if !active {
            sendButton.isEnabled = false
            requestButton.isEnabled = false
            resyncButton.isEnabled = false
        }
    }

    @objc private func sendLocal(_ sender: Any?) { onSendLocal?() }
    @objc private func requestRemote(_ sender: Any?) { onRequestRemote?() }
    @objc private func resync(_ sender: Any?) { onResync?() }

    @objc private func copyReport(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(lastReport, forType: .string)
    }

    @objc private func exportLog(_ sender: Any?) {
        onExportLog?()
    }
}
