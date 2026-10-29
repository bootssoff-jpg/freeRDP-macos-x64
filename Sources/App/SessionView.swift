import AppKit

final class SessionView: NSView {
    let rdpView = RDPView()

    var onDisconnect: (() -> Void)?
    var onCtrlAltDelete: (() -> Void)?
    var onToggleFullScreen: (() -> Void)?
    var onDiagnostics: (() -> Void)?
    var onRetry: (() -> Void)?
    var onSettings: (() -> Void)?

    private let toolbar = NSView()
    private let statusDot = UI.statusDot()
    private let connectionLabel = UI.label("", size: 13, weight: .medium)
    private let detailsLabel = UI.label("", size: 11, color: .secondaryLabelColor)
    private let resolutionLabel = UI.label("", size: 11, color: .secondaryLabelColor)
    private let clipboardLabel = UI.label("Буфер: —", size: 11, color: .secondaryLabelColor)
    private let overlay = NSView()
    private let spinner = NSProgressIndicator()
    private let overlayTitle = UI.label("", size: 18, weight: .semibold)
    private let overlayDetail = UI.label("", size: 12, color: .secondaryLabelColor, lines: 6)
    private let retryButton = UI.button("Переподключиться", target: nil, action: nil)
    private let settingsButton = UI.button("Изменить параметры", target: nil, action: nil)
    private var toolbarHeight: NSLayoutConstraint!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    private func buildUI() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        toolbar.wantsLayer = true
        toolbar.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        toolbar.layer?.masksToBounds = true
        toolbar.translatesAutoresizingMaskIntoConstraints = false

        let disconnect = UI.button("Отключить", target: self, action: #selector(disconnectAction(_:)))
        let ctrlAltDel = UI.button("Ctrl+Alt+Del", target: self, action: #selector(ctrlAltDelAction(_:)))
        let fullscreen = UI.button("Во весь экран", target: self, action: #selector(fullscreenAction(_:)))
        let diagnostics = UI.button("Буфер обмена…", target: self,
                                    action: #selector(diagnosticsAction(_:)))
        let left = UI.hStack([statusDot, connectionLabel, detailsLabel], spacing: 8)
        let right = UI.hStack([clipboardLabel, resolutionLabel, diagnostics, ctrlAltDel, fullscreen,
                               disconnect], spacing: 8)
        let bar = UI.hStack([left, NSView(), right], spacing: 12)
        bar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.addSubview(bar)
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 14),
            bar.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -14),
            bar.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor)
        ])

        rdpView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(toolbar)
        addSubview(rdpView)

        toolbarHeight = toolbar.heightAnchor.constraint(equalToConstant: 44)
        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: trailingAnchor),
            toolbar.topAnchor.constraint(equalTo: topAnchor),
            toolbarHeight,
            rdpView.leadingAnchor.constraint(equalTo: leadingAnchor),
            rdpView.trailingAnchor.constraint(equalTo: trailingAnchor),
            rdpView.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            rdpView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        overlay.wantsLayer = true
        overlay.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.86).cgColor
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.isHidden = true
        addSubview(overlay)

        spinner.style = .spinning
        spinner.controlSize = .regular
        spinner.isDisplayedWhenStopped = false
        retryButton.target = self
        retryButton.action = #selector(retryAction(_:))
        settingsButton.target = self
        settingsButton.action = #selector(settingsAction(_:))
        let buttons = UI.hStack([retryButton, settingsButton], spacing: 10)
        let overlayStack = UI.vStack([spinner, overlayTitle, overlayDetail, buttons], spacing: 14)
        overlayStack.translatesAutoresizingMaskIntoConstraints = false
        overlay.addSubview(overlayStack)
        NSLayoutConstraint.activate([
            overlay.leadingAnchor.constraint(equalTo: leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: trailingAnchor),
            // Keep the toolbar (disconnect, Ctrl+Alt+Del, diagnostics) usable
            // while connecting or after an error.
            overlay.topAnchor.constraint(equalTo: rdpView.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: bottomAnchor),
            overlayStack.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            overlayStack.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
            overlayDetail.widthAnchor.constraint(lessThanOrEqualToConstant: 560)
        ])
    }

    // MARK: - State

    func configure(host: String, port: Int) {
        connectionLabel.stringValue = "\(host):\(port)"
        detailsLabel.stringValue = "подключение"
        resolutionLabel.stringValue = ""
        clipboardLabel.stringValue = "Буфер: ожидание"
        clipboardLabel.textColor = .secondaryLabelColor
        statusDot.layer?.backgroundColor = NSColor.systemOrange.cgColor
    }

    func showConnecting(_ message: String) {
        overlay.isHidden = false
        spinner.startAnimation(nil)
        overlayTitle.stringValue = "Подключение…"
        overlayDetail.stringValue = message
        retryButton.isHidden = true
        settingsButton.isHidden = true
        statusDot.layer?.backgroundColor = NSColor.systemOrange.cgColor
        detailsLabel.stringValue = "подключение"
    }

    func showConnected(width: Int, height: Int) {
        overlay.isHidden = true
        spinner.stopAnimation(nil)
        retryButton.isHidden = true
        settingsButton.isHidden = true
        statusDot.layer?.backgroundColor = NSColor.systemGreen.cgColor
        detailsLabel.stringValue = "подключено"
        resolutionLabel.stringValue = "\(width) × \(height)"
        window?.makeFirstResponder(rdpView)
    }

    func showDisconnected(message: String, isError: Bool) {
        overlay.isHidden = false
        spinner.stopAnimation(nil)
        overlayTitle.stringValue = isError ? "Не удалось подключиться" : "Сеанс завершён"
        overlayDetail.stringValue = message
        retryButton.isHidden = false
        settingsButton.isHidden = false
        statusDot.layer?.backgroundColor =
            (isError ? NSColor.systemRed : NSColor.systemGray).cgColor
        detailsLabel.stringValue = isError ? "ошибка" : "отключено"
        resolutionLabel.stringValue = ""
        window?.makeFirstResponder(settingsButton)
    }

    func updateResolution(width: Int, height: Int) {
        resolutionLabel.stringValue = "\(width) × \(height)"
    }

    func updateClipboard(_ diagnostics: RDPMacClipboardDiagnostics) {
        let text: String
        let color: NSColor
        if !diagnostics.enabled {
            text = "Буфер: выключен"
            color = .secondaryLabelColor
        } else if !diagnostics.channelConnected {
            text = "Буфер: канал не подключён"
            color = .systemOrange
        } else if !diagnostics.monitorReady {
            text = "Буфер: согласование"
            color = .systemOrange
        } else if diagnostics.stateDescription.contains("приостановлен") {
            text = "Буфер: сессия не активна"
            color = .secondaryLabelColor
        } else if diagnostics.failureCount > 0 && diagnostics.lastError != nil {
            text = "Буфер: готов, были ошибки"
            color = .systemOrange
        } else {
            text = "Буфер: готов (CF_UNICODETEXT)"
            color = .systemGreen
        }
        clipboardLabel.stringValue = text
        clipboardLabel.textColor = color
    }

    func setFullScreen(_ fullScreen: Bool) {
        toolbarHeight.constant = fullScreen ? 0 : 44
        toolbar.isHidden = fullScreen
    }

    // MARK: - Actions

    @objc private func disconnectAction(_ sender: Any?) { onDisconnect?() }
    @objc private func ctrlAltDelAction(_ sender: Any?) { onCtrlAltDelete?() }
    @objc private func fullscreenAction(_ sender: Any?) { onToggleFullScreen?() }
    @objc private func diagnosticsAction(_ sender: Any?) { onDiagnostics?() }
    @objc private func retryAction(_ sender: Any?) { onRetry?() }
    @objc private func settingsAction(_ sender: Any?) { onSettings?() }
}
