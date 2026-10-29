import AppKit
import UniformTypeIdentifiers

final class MainWindowController: NSWindowController, NSWindowDelegate,
                                  RDPMacClientDelegate, NSMenuItemValidation {
    private let profileStore = ProfileStore()
    private let formView = ConnectFormView()
    private let sessionView = SessionView()
    private var client: RDPMacClient?
    private var lastRequest: ConnectionRequest?
    private var diagnosticsController: DiagnosticsWindowController?
    private var logController: LogWindowController?
    private var clipboardDiagnostics = RDPMacClipboardDiagnostics()
    private var resizeTimer: Timer?
    private var sessionActive = false
    private var connected = false
    private var pendingShowSettings = false
    private var currentHost = ""
    private var currentPort = 3389
    private var lastRemoteSize = (width: 0, height: 0)

    convenience init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1020, height: 700),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered,
                              defer: false)
        window.title = "RDP Mac"
        window.minSize = NSSize(width: 780, height: 600)
        window.center()
        window.setFrameAutosaveName("RDPMacMainWindow")
        self.init(window: window)
        window.delegate = self
        buildConnections()
        showForm(message: nil, isError: false)
        window.makeKeyAndOrderFront(nil)
    }

    private func buildConnections() {
        formView.onConnect = { [weak self] request in self?.connect(request) }
        formView.onSaveProfile = { [weak self] profile in self?.promptSaveProfile(profile) }
        formView.onDeleteProfile = { [weak self] id in self?.deleteProfile(id) }
        formView.onForgetPassword = { [weak self] in self?.forgetPassword() }
        formView.onProfileSelected = { [weak self] id in self?.profileSelected(id) }
        formView.onShowDiagnostics = { [weak self] in self?.showDiagnostics(nil) }
        formView.onShowLog = { [weak self] in self?.showLog(nil) }

        sessionView.onDisconnect = { [weak self] in self?.disconnect(nil) }
        sessionView.onCtrlAltDelete = { [weak self] in self?.sendCtrlAltDelete(nil) }
        sessionView.onToggleFullScreen = { [weak self] in self?.toggleFullScreenAction(nil) }
        sessionView.onDiagnostics = { [weak self] in self?.showDiagnostics(nil) }
        sessionView.onRetry = { [weak self] in self?.retryConnection() }
        sessionView.onSettings = { [weak self] in self?.showSettings(nil) }

        LogStore.shared.append("RDP Mac запущен. Профилей: \(profileStore.profiles.count)", level: 0)
    }

    private func showForm(message: String?, isError: Bool) {
        guard let window else { return }
        sessionView.removeFromSuperview()
        formView.removeFromSuperview()
        formView.translatesAutoresizingMaskIntoConstraints = true
        formView.autoresizingMask = [.width, .height]
        formView.frame = window.contentView?.bounds ?? window.frame
        window.contentView = formView
        window.title = "RDP Mac"
        formView.setProfiles(profileStore.profiles, selectedID: formView.selectedProfile)
        formView.setBusy(false)
        if let message {
            formView.showMessage(message, isError: isError)
        } else {
            formView.showMessage("Готово к подключению. Пароль вводится здесь и не пишется в журнал.",
                                 isError: false)
        }
        formView.focusHost()
    }

    private func showSessionView() {
        guard let window else { return }
        formView.removeFromSuperview()
        sessionView.removeFromSuperview()
        sessionView.translatesAutoresizingMaskIntoConstraints = true
        sessionView.autoresizingMask = [.width, .height]
        sessionView.frame = window.contentView?.bounds ?? window.frame
        window.contentView = sessionView
        sessionView.configure(host: currentHost, port: currentPort)
        window.makeFirstResponder(sessionView.rdpView)
    }

    private func connect(_ request: ConnectionRequest) {
        guard let window else { return }
        currentHost = request.host
        currentPort = request.port
        lastRequest = request

        let account = KeychainStore.account(host: request.host,
                                            port: request.port,
                                            domain: request.domain,
                                            username: request.username)
        if request.savePassword {
            if KeychainStore.save(password: request.password, account: account) {
                LogStore.shared.append("Пароль сохранён в Keychain для \(request.host):\(request.port)",
                                       level: 0)
            } else {
                LogStore.shared.append("Не удалось сохранить пароль в Keychain", level: 1)
            }
        } else {
            KeychainStore.delete(account: account)
        }

        // The session view uses a 44 pt toolbar; match its desktop area exactly
        // to avoid an unnecessary DisplayControl resize right after connecting.
        let content = NSSize(width: max(800, window.contentView?.bounds.width ?? 1000),
                             height: max(600, (window.contentView?.bounds.height ?? 700) - 44))
        let scale = window.backingScaleFactor
        let size = request.resolution.size(for: content, backingScale: scale)

        let newClient = RDPMacClient()
        newClient.delegate = self
        client = newClient
        sessionView.rdpView.client = newClient

        do {
            try newClient.start(withHost: request.host,
                                port: request.port,
                                username: request.username,
                                domain: request.domain,
                                password: request.password,
                                width: UInt(size.width),
                                height: UInt(size.height),
                                securityMode: request.security.bridgeValue,
                                clipboardEnabled: request.clipboardEnabled,
                                commandAsControl: request.commandAsControl,
                                certificatePromptTimeout: 180)
        } catch {
            let message = (error as NSError).localizedDescription
            LogStore.shared.append(message, level: 2)
            showForm(message: message, isError: true)
            client = nil
            return
        }

        sessionActive = true
        connected = false
        clipboardDiagnostics = newClient.clipboardDiagnostics()
        showSessionView()
        sessionView.showConnecting("Сервер \(request.host):\(request.port), пользователь "
                                   + "\(request.username)")
        sessionView.updateClipboard(clipboardDiagnostics)
        diagnosticsController?.update(diagnostics: clipboardDiagnostics,
                                      session: sessionDescription())
        LogStore.shared.append("Запуск подключения к \(request.host):\(request.port)", level: 0)
    }

    private func retryConnection() {
        guard let request = lastRequest else {
            showForm(message: "Нет параметров для повторного подключения.", isError: true)
            return
        }
        connect(request)
    }

    // MARK: - Profiles and passwords

    private func profileSelected(_ id: UUID?) {
        guard let id, let profile = profileStore.profiles.first(where: { $0.id == id }) else {
            formView.clearProfileSelection()
            formView.clearPassword()
            formView.showMessage("Новый профиль. Заполните параметры подключения.", isError: false)
            return
        }
        let password = profileStore.password(for: profile)
        formView.applyProfile(profile, password: password)
        if profile.savePassword && password == nil {
            formView.showMessage("В Keychain не найден пароль для этого профиля. Введите пароль.",
                                 isError: false)
        } else {
            formView.showMessage("Профиль: \(profile.displayName)", isError: false)
        }
    }

    private func promptSaveProfile(_ profile: Profile) {
        let alert = NSAlert()
        alert.messageText = "Сохранить профиль"
        alert.informativeText = "Пароль в JSON-профиль не записывается. Для пароля используйте "
            + "галочку «Сохранить пароль в Keychain»."
        alert.addButton(withTitle: "Сохранить")
        alert.addButton(withTitle: "Отмена")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = "Имя профиля"
        field.stringValue = profile.name.isEmpty
            ? (profile.host.isEmpty ? "Профиль" : profile.displayName)
            : profile.name
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        var saved = profile
        saved.name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if saved.name.isEmpty {
            saved.name = saved.displayName
        }
        profileStore.upsert(saved)
        formView.setProfiles(profileStore.profiles, selectedID: saved.id)
        formView.applyProfile(saved, password: formView.currentPassword)
        formView.showMessage("Профиль сохранён: \(saved.name)", isError: false)
        LogStore.shared.append("Профиль сохранён: \(saved.name) (\(saved.host):\(saved.port))",
                               level: 0)
    }

    private func deleteProfile(_ id: UUID) {
        guard let profile = profileStore.profiles.first(where: { $0.id == id }) else { return }
        let alert = NSAlert()
        alert.messageText = "Удалить профиль «\(profile.displayName)»?"
        alert.informativeText = "Пароль этого профиля будет удалён из Keychain."
        alert.addButton(withTitle: "Удалить")
        alert.addButton(withTitle: "Отмена")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        profileStore.forgetPassword(for: profile)
        profileStore.delete(id: id)
        formView.clearProfileSelection()
        formView.clearPassword()
        formView.setProfiles(profileStore.profiles, selectedID: nil)
        formView.showMessage("Профиль удалён.", isError: false)
        LogStore.shared.append("Профиль удалён: \(profile.displayName)", level: 0)
    }

    private func forgetPassword() {
        KeychainStore.delete(account: formView.currentAccount)
        formView.clearPassword()
        formView.showMessage("Пароль удалён из Keychain и из поля ввода.", isError: false)
        LogStore.shared.append("Пароль удалён из Keychain для текущего сервера/пользователя", level: 0)
    }

    // MARK: - RDPMacClientDelegate

    func rdpClient(_ client: RDPMacClient, didChange state: RDPMacConnectionState,
                   message: String) {
        switch state {
        case .connecting:
            sessionView.showConnecting(message)
        case .disconnecting:
            sessionView.showConnecting("Отключение…")
        case .disconnected, .failed:
            sessionActive = false
            connected = false
            window?.title = "RDP Mac"
            diagnosticsController?.setSessionActive(false)
            if pendingShowSettings {
                pendingShowSettings = false
                showForm(message: message, isError: state == .failed)
            } else {
                let isError = state == .failed
                sessionView.showDisconnected(message: message, isError: isError)
            }
        case .connected, .idle:
            break
        @unknown default:
            break
        }
    }

    func rdpClientDidConnect(_ client: RDPMacClient) {
        connected = true
        sessionActive = true
        lastRemoteSize = (width: Int(client.frameWidth), height: Int(client.frameHeight))
        sessionView.showConnected(width: lastRemoteSize.width, height: lastRemoteSize.height)
        sessionView.updateClipboard(client.clipboardDiagnostics())
        sessionView.rdpView.needsDisplay = true
        window?.title = "\(currentHost):\(currentPort) — RDP Mac"
        LogStore.shared.append("Сеанс установлен: \(lastRemoteSize.width)×\(lastRemoteSize.height)",
                               level: 0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.scheduleRemoteResize()
        }
    }

    func rdpClient(_ client: RDPMacClient, didResizeToWidth width: UInt, height: UInt) {
        lastRemoteSize = (width: Int(width), height: Int(height))
        sessionView.updateResolution(width: Int(width), height: Int(height))
        sessionView.rdpView.needsDisplay = true
        LogStore.shared.append("Разрешение сеанса изменено: \(width)×\(height)", level: 0)
    }

    func rdpClient(_ client: RDPMacClient, didUpdateFrameIn rect: CGRect) {
        if rect.width <= 0 || rect.height <= 0 {
            sessionView.rdpView.needsDisplay = true
        } else {
            sessionView.rdpView.invalidate(remoteRect: rect)
        }
    }

    func rdpClient(_ client: RDPMacClient,
                   didUpdate diagnostics: RDPMacClipboardDiagnostics) {
        clipboardDiagnostics = diagnostics
        sessionView.updateClipboard(diagnostics)
        diagnosticsController?.update(diagnostics: diagnostics, session: sessionDescription())
    }

    func rdpClient(_ client: RDPMacClient, didLogMessage message: String, level: Int) {
        LogStore.shared.append(message, level: level)
    }

    func rdpClient(_ client: RDPMacClient, didDisconnectWithError error: String?) {
        connected = false
        sessionActive = false
        let message = error ?? "Сеанс завершён."
        window?.title = "RDP Mac"
        diagnosticsController?.setSessionActive(false)
        diagnosticsController?.update(diagnostics: clipboardDiagnostics,
                                      session: sessionDescription())
        LogStore.shared.append(error == nil ? "Сеанс завершён" : "Сеанс завершён с ошибкой: \(message)",
                               level: error == nil ? 0 : 2)
        if pendingShowSettings {
            pendingShowSettings = false
            showForm(message: message, isError: error != nil)
        } else {
            sessionView.showDisconnected(message: message, isError: error != nil)
        }
    }

    func rdpClient(_ client: RDPMacClient,
                   didRequestCertificateApproval info: RDPMacCertificateInfo,
                   completion: @escaping (RDPMacCertificateDecision) -> Void) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = info.changed
            ? "Сертификат сервера изменился"
            : "Сервер предъявил неизвестный сертификат"
        alert.informativeText = """
        \(info.details)

        Сертификат не подтверждён системным хранилищем доверия. Подключайтесь, только если
        отпечаток SHA-256 совпадает с ожидаемым. «Запомнить» сохраняет сертификат в known_hosts
        FreeRDP для этого сервера.
        """
        alert.addButton(withTitle: "Отклонить")
        alert.addButton(withTitle: "Принять один раз")
        alert.addButton(withTitle: "Принять и запомнить")

        let response = alert.runModal()
        let decision: RDPMacCertificateDecision
        switch response {
        case .alertSecondButtonReturn:
            decision = .acceptOnce
        case .alertThirdButtonReturn:
            decision = .acceptAndRemember
        default:
            decision = .reject
        }
        completion(decision)
    }

    private func sessionDescription() -> String {
        guard let client else { return "нет клиента" }
        switch client.state {
        case .connected:
            return "подключено, \(lastRemoteSize.width)×\(lastRemoteSize.height), "
                + "\(currentHost):\(currentPort)"
        case .connecting:
            return "подключение к \(currentHost):\(currentPort)"
        case .disconnecting:
            return "отключение"
        default:
            return "нет активного сеанса"
        }
    }

    // MARK: - Menu / toolbar actions

    @objc func disconnect(_ sender: Any?) {
        if sessionActive || client?.state == .connecting {
            client?.disconnect()
        } else {
            showForm(message: "Сеанс не активен.", isError: false)
        }
    }

    @objc func sendCtrlAltDelete(_ sender: Any?) {
        guard connected else {
            LogStore.shared.append("Ctrl+Alt+Delete не отправлен: нет активного сеанса", level: 1)
            return
        }
        client?.sendCtrlAltDelete()
    }

    @objc func toggleFullScreenAction(_ sender: Any?) {
        window?.toggleFullScreen(nil)
    }

    @objc func clipboardSendLocal(_ sender: Any?) {
        guard connected else {
            LogStore.shared.append("Буфер: нет активного сеанса", level: 1)
            return
        }
        client?.clipboardSendLocal()
    }

    @objc func clipboardRequestRemote(_ sender: Any?) {
        guard connected else {
            LogStore.shared.append("Буфер: нет активного сеанса", level: 1)
            return
        }
        client?.clipboardRequestRemote()
    }

    @objc func clipboardResync(_ sender: Any?) {
        guard connected else {
            LogStore.shared.append("Буфер: нет активного сеанса", level: 1)
            return
        }
        client?.clipboardResync()
    }

    @objc func showDiagnostics(_ sender: Any?) {
        if diagnosticsController == nil {
            let controller = DiagnosticsWindowController()
            controller.onSendLocal = { [weak self] in self?.clipboardSendLocal(nil) }
            controller.onRequestRemote = { [weak self] in self?.clipboardRequestRemote(nil) }
            controller.onResync = { [weak self] in self?.clipboardResync(nil) }
            controller.onExportLog = { [weak self] in self?.exportLog(nil) }
            diagnosticsController = controller
        }
        diagnosticsController?.update(diagnostics: client?.clipboardDiagnostics()
                                          ?? clipboardDiagnostics,
                                      session: sessionDescription())
        diagnosticsController?.setSessionActive(connected)
        diagnosticsController?.showWindow(nil)
        diagnosticsController?.window?.makeKeyAndOrderFront(nil)
    }

    @objc func showLog(_ sender: Any?) {
        if logController == nil {
            logController = LogWindowController()
        }
        logController?.refresh()
        logController?.showWindow(nil)
        logController?.window?.makeKeyAndOrderFront(nil)
    }

    @objc func exportLog(_ sender: Any?) {
        guard let window else { return }
        let panel = NSSavePanel()
        panel.title = "Экспорт журнала RDP Mac"
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

    @objc func showSettings(_ sender: Any?) {
        if sessionActive || client?.state == .connecting {
            pendingShowSettings = true
            client?.disconnect()
        } else {
            showForm(message: nil, isError: false)
        }
    }

    @objc func showAbout(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc func showHelp(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "RDP Mac: что уже работает"
        alert.informativeText = """
        Работает:
        • текстовый буфер обмена в обе стороны (CF_UNICODETEXT; CF_TEXT — best effort);
        • русский и английский ввод, Unicode, многострочный текст;
        • мышь, колесо, боковые кнопки, Ctrl+Alt+Delete (Ctrl+Alt+End);
        • полноэкранный режим, масштаб Retina, изменение разрешения через DisplayControl;
        • NLA и TLS с обязательным подтверждением неизвестного сертификата;
        • профили без паролей, пароль — только в Keychain по согласию;
        • журнал подключения без содержимого буфера и экспорт журнала.

        Пока не поддерживается:
        • изображения, файлы, перенаправление папок и принтеров;
        • звук, камера, смарт-карты, IME (китайский/японский ввод);
        • автоматическое переподключение при обрыве сети (есть кнопка «Переподключиться»).

        Ограничения, заданные сервером (запрет буфера обмена групповой политикой,
        отключённый CLIPRDR), клиент обойти не может.
        """
        alert.addButton(withTitle: "Понятно")
        alert.runModal()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(disconnect(_:)), #selector(sendCtrlAltDelete(_:)),
             #selector(toggleFullScreenAction(_:)):
            return sessionActive
        case #selector(clipboardSendLocal(_:)), #selector(clipboardRequestRemote(_:)),
             #selector(clipboardResync(_:)):
            return connected
        default:
            return true
        }
    }

    // MARK: - Window size / fullscreen

    private func scheduleRemoteResize() {
        resizeTimer?.invalidate()
        resizeTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) {
            [weak self] _ in
            self?.applyRemoteResize()
        }
        if let resizeTimer {
            RunLoop.main.add(resizeTimer, forMode: .common)
        }
    }

    private func applyRemoteResize() {
        guard let client, connected, let window, let request = lastRequest,
              request.autoResize, request.resolution == .window else { return }
        let size = sessionView.rdpView.bounds.size
        guard size.width > 100, size.height > 100 else { return }
        let scale = window.backingScaleFactor
        var width = Int(size.width * scale) & ~1
        var height = Int(size.height * scale) & ~1
        width = max(800, min(width, 2560))
        height = max(600, min(height, 1600))
        if abs(width - lastRemoteSize.width) < 8 && abs(height - lastRemoteSize.height) < 8 {
            return
        }
        if !client.requestDesktopSize(UInt(width), height: UInt(height)) {
            LogStore.shared.append("DisplayControl: не удалось запросить размер \(width)×\(height)",
                                   level: 1)
        }
    }

    func windowDidResize(_ notification: Notification) {
        guard connected else { return }
        scheduleRemoteResize()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard connected else { return }
        scheduleRemoteResize()
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        sessionView.setFullScreen(true)
        scheduleRemoteResize()
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        sessionView.setFullScreen(false)
        scheduleRemoteResize()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        if connected {
            window?.makeFirstResponder(sessionView.rdpView)
        }
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        frameSize
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sessionActive || client?.state == .connecting || client?.state == .disconnecting {
            let alert = NSAlert()
            alert.messageText = "Завершить приложение и отключиться от сервера?"
            alert.informativeText = "Активный RDP-сеанс будет закрыт, ресурсы освобождены."
            alert.addButton(withTitle: "Отключиться и закрыть")
            alert.addButton(withTitle: "Отмена")
            if alert.runModal() == .alertFirstButtonReturn {
                NSApp.terminate(nil)
            }
            return false
        }
        return true
    }

    func prepareForTermination(_ completion: @escaping () -> Void) {
        resizeTimer?.invalidate()
        guard let client else {
            completion()
            return
        }
        let state = client.state
        guard state == .connecting || state == .connected || state == .disconnecting else {
            completion()
            return
        }
        client.disconnect()
        let deadline = Date().addingTimeInterval(3.0)
        var poll: (() -> Void)!
        poll = {
            if client.state == .disconnected || client.state == .failed || client.state == .idle
                || Date() > deadline {
                completion()
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: poll)
        }
        poll()
    }
}
