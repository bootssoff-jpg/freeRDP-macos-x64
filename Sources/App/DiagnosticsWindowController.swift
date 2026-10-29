import AppKit

final class DiagnosticsWindowController: NSWindowController {
    var onSendLocal: (() -> Void)?
    var onRequestRemote: (() -> Void)?
    var onResync: (() -> Void)?
    var onReconnect: (() -> Void)?
    var onExportLog: (() -> Void)?

    private let textView = NSTextView()
    private let sendButton = UI.button(L("Отправить Mac → Windows"), target: nil, action: nil)
    private let requestButton = UI.button(L("Запросить Windows → Mac"), target: nil, action: nil)
    private let resyncButton = UI.button(L("Полная ресинхронизация"), target: nil, action: nil)
    private let copyButton = UI.button(L("Копировать отчёт"), target: nil, action: nil)
    private let exportButton = UI.button(L("Экспорт журнала…"), target: nil, action: nil)
    private let reconnectButton = UI.button(L("Переподключиться"), target: nil, action: nil)
    private var lastReport = ""
    private var recoveryAvailable = false

    convenience init() {
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 760, height: 620),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable],
                              backing: .buffered,
                              defer: false)
        window.title = L("Диагностика буфера обмена")
        window.minSize = NSSize(width: 640, height: 480)
        window.isReleasedWhenClosed = false
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

        reconnectButton.target = self
        reconnectButton.action = #selector(reconnect(_:))
        reconnectButton.isHidden = true
        let firstRow = UI.hStack([sendButton, requestButton, resyncButton], spacing: 8)
        let secondRow = UI.hStack([copyButton, exportButton, reconnectButton], spacing: 8)
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
        lines.append(L("Сеанс: %@", String(describing: session)))
        lines.append("")
        lines.append(L("CLIPRDR включён: %@", String(describing: diagnostics.enabled ? L("да") : L("нет"))))
        lines.append(L("Канал подключён: %@", String(describing: diagnostics.channelConnected ? L("да") : L("нет"))))
        lines.append("Monitor Ready: \(diagnostics.monitorReady ? L("да") : L("нет"))")
        lines.append(L("Состояние: %@", String(describing: diagnostics.stateDescription)))
        lines.append(L("Локальные форматы: %@", String(describing: diagnostics.localFormats.joined(separator: ", "))))
        lines.append(L("Форматы Windows: %@", String(describing: formats)))
        lines.append("")
        lines.append(L("Объявлений Mac → Windows: %@", String(describing: diagnostics.localAdvertiseCount)))
        lines.append(L("Объявлений Windows → Mac: %@", String(describing: diagnostics.remoteAdvertiseCount)))
        lines.append(L("Отправлено пакетов: %@", String(describing: diagnostics.sendCount)))
        lines.append(L("Получено пакетов: %@", String(describing: diagnostics.receiveCount)))
        lines.append(L("Ошибок: %@", String(describing: diagnostics.failureCount)))
        lines.append("")
        lines.append(L("Последнее объявление Mac: %@", String(describing: diagnostics.lastLocalAdvertise ?? "—")))
        lines.append(L("Последнее объявление Windows: %@", String(describing: diagnostics.lastRemoteAdvertise ?? "—")))
        lines.append(L("Последняя отправка: %@", String(describing: diagnostics.lastLocalSend ?? "—")))
        lines.append(L("Последнее получение: %@", String(describing: diagnostics.lastRemoteReceive ?? "—")))
        lines.append(L("Ожидание ответа: %@", String(describing: diagnostics.pendingRequest ?? "—")))
        lines.append(L("Последняя ошибка: %@", String(describing: diagnostics.lastError ?? "—")))
        lines.append("")
        lines.append(L("Поддерживается: текст CF_UNICODETEXT (UTF-16LE) и CF_TEXT (best effort)."))
        lines.append(L("Изображения, файлы и перенаправление папок не поддерживаются."))
        lines.append(L("Содержимое буфера обмена в диагностику и журнал не записывается."))
        lastReport = lines.joined(separator: "\n")
        textView.string = lastReport

        sendButton.isEnabled = enabled && diagnostics.monitorReady
        requestButton.isEnabled = enabled && diagnostics.monitorReady
        resyncButton.isEnabled = enabled && diagnostics.monitorReady && !diagnostics.requiresReconnect
        requestButton.isEnabled = enabled && diagnostics.monitorReady && !diagnostics.requiresReconnect
        recoveryAvailable = diagnostics.requiresReconnect
        reconnectButton.isHidden = !recoveryAvailable
        reconnectButton.isEnabled = recoveryAvailable
    }

    func setSessionActive(_ active: Bool) {
        reconnectButton.isEnabled = active && recoveryAvailable
        if !active {
            sendButton.isEnabled = false
            requestButton.isEnabled = false
            resyncButton.isEnabled = false
        }
    }

    @objc private func reconnect(_ sender: Any?) { onReconnect?() }
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
