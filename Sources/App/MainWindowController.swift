import AppKit
import UniformTypeIdentifiers

final class MainWindowController: NSWindowController, NSWindowDelegate,
                                  RDPMacClientDelegate, NSMenuItemValidation {
    private let profileStore = ProfileStore.shared
    private let formView = ConnectFormView()
    private let sessionView = SessionView()
    private var client: RDPMacClient?
    private var lastRequest: ConnectionRequest?
    private var diagnosticsController: DiagnosticsWindowController?
    private var logController: LogWindowController?
    private var credentialsController: CredentialsWindowController?
    private var clipboardDiagnostics = RDPMacClipboardDiagnostics()
    private var resizeTimer: Timer?
    private var sessionActive = false
    private var connected = false
    private var pendingShowSettings = false
    private var pendingReconnect = false
    private var legacyPromptShown = false
    private var didInitialProfileSelection = false
    private var currentHost = ""
    private var currentPort = 3389
    private var lastRemoteSize = (width: 0, height: 0)

    static let sessionDidChange = Notification.Name("RDPMacSessionDidChange")
    var runningProfileID: UUID? { sessionActive ? lastRequest?.profileID : nil }
    var isConnected: Bool { connected }
    var onClose: ((MainWindowController) -> Void)?
    var onActivate: ((MainWindowController) -> Void)?
    private var closingSession = false
    private var clipboardActive = false
    private let sessionID = String(UUID().uuidString.prefix(8))

    convenience init(showWindow: Bool = true) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1020, height: 700),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered,
                              defer: false)
        window.tabbingMode = .disallowed
        window.title = "RDP Mac"
        window.minSize = NSSize(width: 780, height: 600)
        window.center()
        self.init(window: window)
        window.setFrameAutosaveName("RDPMacMainWindow-\(sessionID)")
        window.delegate = self
        buildConnections()
        showForm(message: nil, isError: false)
        if showWindow { window.makeKeyAndOrderFront(nil) }
    }

    private func buildConnections() {
        formView.onConnect = { [weak self] request in self?.connect(request) }
        formView.onSaveProfile = { [weak self] profile in self?.promptSaveProfile(profile) }
        formView.onDeleteProfile = { [weak self] id in self?.deleteProfile(id) }
        formView.onForgetPassword = { [weak self] in self?.forgetPassword() }
        formView.onProfileSelected = { [weak self] id in self?.profileSelected(id) }
        formView.onShowDiagnostics = { [weak self] in self?.showDiagnostics(nil) }
        formView.onShowLog = { [weak self] in self?.showLog(nil) }
        formView.onManageCredentials = { [weak self] in self?.showCredentials(nil) }

        sessionView.onDisconnect = { [weak self] in self?.disconnect(nil) }
        sessionView.onCtrlAltDelete = { [weak self] in self?.sendCtrlAltDelete(nil) }
        sessionView.onToggleFullScreen = { [weak self] in self?.toggleFullScreenAction(nil) }
        sessionView.onDiagnostics = { [weak self] in self?.showDiagnostics(nil) }
        sessionView.onRetry = { [weak self] in self?.retryConnection() }
        sessionView.onSettings = { [weak self] in self?.showSettings(nil) }

        LogStore.shared.append(L("Сессия создана. Профилей: %@", String(describing: profileStore.profiles.count)), level: 0)
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
        formView.setCredentials(CredentialStore.shared.credentials,
                                selectedID: formView.currentCredential)
        if !didInitialProfileSelection {
            didInitialProfileSelection = true
            DispatchQueue.main.async { [weak self] in
                guard let self, self.formView.selectedProfile == nil,
                      let first = self.profileStore.profiles.first else { return }
                self.profileSelected(first.id)
            }
        }
        formView.setBusy(false)
        if let message {
            formView.showMessage(message, isError: isError)
        } else {
            formView.showMessage(L("Готово к подключению. Пароль вводится здесь и не пишется в журнал."),
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
        legacyPromptShown = false
        window.title = "\(request.host):\(request.port) — RDP Mac"

        // A directory record owns the secret: saving writes to its shared item,
        // and connecting never deletes it (other profiles may use it). Manual
        // accounts keep the original host-keyed behaviour.
        if let credentialID = request.credentialID,
           let credential = CredentialStore.shared.credential(id: credentialID) {
            if request.savePassword, !request.password.isEmpty {
                if CredentialStore.shared.savePassword(request.password, for: credential) {
                    LogStore.shared.append(L("Пароль сохранён в Keychain для учётной записи «%@»",
                                             credential.displayName), level: 0)
                } else {
                    LogStore.shared.append(L("Не удалось сохранить пароль в Keychain"), level: 1)
                }
            }
        } else {
            let account = KeychainStore.account(host: request.host,
                                                port: request.port,
                                                domain: request.domain,
                                                username: request.username)
            if request.savePassword, !request.password.isEmpty {
                if KeychainStore.save(password: request.password, account: account) {
                    LogStore.shared.append(L("Пароль сохранён в Keychain для %@:%@", String(describing: request.host), String(describing: request.port)),
                                           level: 0)
                } else {
                    LogStore.shared.append(L("Не удалось сохранить пароль в Keychain"), level: 1)
                }
            } else {
                // An empty password must not create an auto-connect entry, and
                // clearing the checkbox removes any previously saved password.
                KeychainStore.delete(account: account)
            }
        }

        // The session view uses a 44 pt toolbar; match its desktop area exactly
        // to avoid an unnecessary DisplayControl resize right after connecting.
        let content = NSSize(width: max(800, window.contentView?.bounds.width ?? 1000),
                             height: max(600, (window.contentView?.bounds.height ?? 700) - 44))
        let scale = window.backingScaleFactor
        let size = request.resolution.size(for: content, backingScale: scale)

        client?.delegate = nil
        let newClient = RDPMacClient()
        newClient.delegate = self
        // Do not let a background window touch the shared pasteboard even for
        // the short interval before AppDelegate activates the new window.
        newClient.setClipboardActive(clipboardActive)
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
                                allowLegacyTLS: request.legacyTLS,
                                certificatePromptTimeout: 180)
        } catch {
            let message = (error as NSError).localizedDescription
            LogStore.shared.append(message, level: 2)
            newClient.delegate = nil
            newClient.disconnect()
            sessionView.rdpView.client = nil
            client = nil
            sessionActive = false
            connected = false
            showForm(message: message, isError: true)
            return
        }

        sessionActive = true
        connected = false
        NotificationCenter.default.post(name: Self.sessionDidChange, object: self)
        clipboardDiagnostics = newClient.clipboardDiagnostics()
        showSessionView()
        sessionView.showConnecting(L("Сервер %@:%@, пользователь ", String(describing: request.host), String(describing: request.port))
                                   + "\(request.username)")
        sessionView.updateClipboard(clipboardDiagnostics)
        diagnosticsController?.update(diagnostics: clipboardDiagnostics,
                                      session: sessionDescription())
        LogStore.shared.append(L("Запуск подключения к %@:%@", String(describing: request.host), String(describing: request.port)), level: 0)
    }

    private func reconnectFromDiagnostics() {
        guard let client, connected else { return }
        let alert = NSAlert()
        alert.messageText = L("Переподключиться для восстановления буфера?")
        alert.informativeText = L("Текущая сессия будет отключена и подключена снова. Остальные сессии продолжат работу.")
        alert.addButton(withTitle: L("Переподключиться"))
        alert.addButton(withTitle: L("Отмена"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        pendingReconnect = true
        client.disconnect()
    }

    private func retryConnection() {
        guard let request = lastRequest else {
            showForm(message: L("Нет параметров для повторного подключения."), isError: true)
            return
        }
        legacyPromptShown = false
        connect(request)
    }

    /// Some old Windows servers use SHA-1/RSA-1024 certificates that OpenSSL 3
    /// rejects at the default security level. Offer an explicit, warned retry
    /// with SECLEVEL=0; certificate approval is still mandatory.
    private func offerLegacyTLSIfNeeded(client: RDPMacClient, error: String?) -> Bool {
        guard let request = lastRequest,
              !request.legacyTLS,
              client.lastErrorWasTLS,
              !legacyPromptShown,
              !pendingShowSettings else {
            return false
        }
        legacyPromptShown = true
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L("Сервер использует устаревший TLS")
        alert.informativeText = L("%@\n\nОбычно это старый сертификат Windows (SHA-1 или ключ RSA-1024), который OpenSSL 3\nотклоняет по умолчанию. Можно повторить подключение в режиме совместимости\n(SECLEVEL=0): трафик останется зашифрованным, но стойкость TLS будет ниже.\nСертификат всё равно будет показан, и его нужно подтвердить вручную.\n\nИспользуйте это только для доверенного сервера в локальной сети.", String(describing: error ?? L("Обычный TLS не смог установить соединение.")))
        alert.addButton(withTitle: L("Подключиться в режиме совместимости"))
        alert.addButton(withTitle: L("Отмена"))
        guard alert.runModal() == .alertFirstButtonReturn else { return false }

        let updated = request.withLegacyTLS()
        lastRequest = updated
        formView.setLegacyTLS(true)
        // Do not persist an insecure compatibility mode automatically. The
        // warning applies to this retry; the user must explicitly opt in again
        // if they want the profile to use it after a restart.
        LogStore.shared.append(L("Повтор подключения с совместимым TLS (SECLEVEL=0)"), level: 1)
        connect(updated)
        return true
    }

    // MARK: - Profiles and passwords

    func openProfile(_ profile: Profile) {
        selectProfile(profile)
        if profile.savePassword && !formView.currentPassword.isEmpty {
            formView.submitConnection()
        }
    }

    func selectProfile(_ profile: Profile) {
        didInitialProfileSelection = true
        formView.setProfiles(profileStore.profiles, selectedID: profile.id)
        profileSelected(profile.id)
    }

    func setClipboardActive(_ active: Bool) {
        clipboardActive = active
        client?.setClipboardActive(active)
        if !active { client?.sendModifierFlags(0) }
    }

    private func profileSelected(_ id: UUID?) {
        guard let id, var profile = profileStore.profile(id: id) else {
            formView.clearProfileSelection()
            formView.clearPassword()
            formView.showMessage(L("Новый профиль. Заполните параметры подключения."), isError: false)
            return
        }
        // Lazy migration: the first time a profile with a legacy host-keyed
        // password is opened, its record is created from the secret that was
        // just read for the form. No extra Keychain prompt, nothing deleted.
        if profile.credentialID == nil, profile.savePassword,
           let legacySecret = profileStore.password(for: profile),
           let credential = CredentialStore.shared.attachLegacyPassword(for: profile,
                                                                        secret: legacySecret) {
            profile.credentialID = credential.id
            profileStore.upsert(profile)
        }
        let credential = CredentialStore.shared.credential(id: profile.credentialID)
        let password = credential.map { CredentialStore.shared.password(for: $0) }
            ?? profileStore.password(for: profile)
        formView.setCredentials(CredentialStore.shared.credentials, selectedID: profile.credentialID)
        formView.applyProfile(profile, password: password)
        if let credential {
            if password == nil {
                formView.showMessage(L("Для учётной записи «%@» нет пароля в Keychain. Введите пароль.",
                                       credential.displayName), isError: false)
            } else {
                formView.showMessage(L("Профиль: %@ · учётная запись «%@»",
                                       profile.displayName, credential.displayName), isError: false)
            }
        } else if profile.savePassword && password == nil {
            formView.showMessage(L("В Keychain не найден пароль для этого профиля. Введите пароль."),
                                 isError: false)
        } else {
            formView.showMessage(L("Профиль: %@", String(describing: profile.displayName)), isError: false)
        }
    }

    private func promptSaveProfile(_ profile: Profile) {
        let draft = formView.isDraftProfile
        let alert = NSAlert()
        alert.messageText = draft ? L("Сохранить копию подключения") : L("Сохранить профиль")
        alert.informativeText = L("Пароль в JSON-профиль не записывается. Для пароля используйте ")
            + L("галочку «Сохранить пароль в Keychain».")
        alert.addButton(withTitle: draft ? L("Сохранить копию") : L("Сохранить"))
        alert.addButton(withTitle: L("Отмена"))
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = L("Имя профиля")
        field.stringValue = profile.name.isEmpty
            ? (profile.host.isEmpty ? L("Профиль") : profile.displayName)
            : profile.name
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        var saved = profile
        saved.name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if saved.name.isEmpty {
            saved.name = saved.displayName
        }

        // A typed password goes into the selected account record. A profile (or
        // a copy of one) that still keeps its secret under the legacy
        // host-keyed item gets a new record, so the password survives an
        // address change; nothing is ever written into the profile itself.
        let typedPassword = formView.currentPassword
        if saved.savePassword {
            if let credentialID = saved.credentialID,
               let credential = CredentialStore.shared.credential(id: credentialID) {
                if !typedPassword.isEmpty,
                   CredentialStore.shared.savePassword(typedPassword, for: credential) {
                    LogStore.shared.append(L("Пароль сохранён в Keychain для учётной записи «%@»",
                                             credential.displayName), level: 0)
                }
            } else if !saved.username.isEmpty {
                let secret: String? = typedPassword.isEmpty ? nil : typedPassword
                if let credential = CredentialStore.shared.attachLegacyPassword(for: saved,
                                                                               secret: secret) {
                    saved.credentialID = credential.id
                    LogStore.shared.append(L("Создана учётная запись «%@» из профиля",
                                             credential.displayName), level: 0)
                }
            }
        }

        profileStore.upsert(saved)
        formView.setProfiles(profileStore.profiles, selectedID: saved.id)
        formView.setCredentials(CredentialStore.shared.credentials, selectedID: saved.credentialID)
        let effectivePassword = saved.credentialID
            .flatMap { CredentialStore.shared.credential(id: $0) }
            .flatMap { CredentialStore.shared.password(for: $0) } ?? typedPassword
        formView.applyProfile(saved, password: effectivePassword)
        formView.showMessage(draft ? L("Копия сохранена: %@", String(describing: saved.name))
                                   : L("Профиль сохранён: %@", String(describing: saved.name)),
                             isError: false)
        LogStore.shared.append(L("Профиль сохранён: %@ (%@:%@)", String(describing: saved.name), String(describing: saved.host), String(describing: saved.port)),
                               level: 0)
    }

    private func deleteProfile(_ id: UUID) {
        guard let profile = profileStore.profile(id: id) else { return }
        let shared = profile.credentialID != nil
        let alert = NSAlert()
        alert.messageText = L("Удалить профиль «%@»?", String(describing: profile.displayName))
        alert.informativeText = shared
            ? L("Учётная запись и её пароль останутся в справочнике и будут доступны другим подключениям.")
            : L("Пароль этого профиля будет удалён из Keychain.")
        alert.addButton(withTitle: L("Удалить"))
        alert.addButton(withTitle: L("Отмена"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        profileStore.forgetPassword(for: profile)
        profileStore.delete(id: id)
        formView.clearProfileSelection()
        formView.clearPassword()
        formView.setProfiles(profileStore.profiles, selectedID: nil)
        formView.showMessage(L("Профиль удалён."), isError: false)
        LogStore.shared.append(L("Профиль удалён: %@", String(describing: profile.displayName)), level: 0)
    }

    private func forgetPassword() {
        guard let credential = formView.selectedCredentialRecord else {
            KeychainStore.delete(account: formView.currentAccount)
            formView.clearPassword()
            formView.showMessage(L("Пароль удалён из Keychain и из поля ввода."), isError: false)
            LogStore.shared.append(L("Пароль удалён из Keychain для текущего сервера/пользователя"), level: 0)
            return
        }
        let usage = CredentialStore.shared.profilesUsing(credential.id, in: profileStore).count
        if usage > 1 {
            let alert = NSAlert()
            alert.messageText = L("Удалить общий пароль учётной записи «%@»?", credential.displayName)
            alert.informativeText = L("Запись используется в %@ подключениях: пароль перестанет быть доступен всем им.",
                                      String(describing: usage))
            alert.addButton(withTitle: L("Удалить"))
            alert.addButton(withTitle: L("Отмена"))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        CredentialStore.shared.forgetPassword(for: credential)
        formView.clearPassword()
        formView.showMessage(L("Пароль учётной записи удалён из Keychain."), isError: false)
        LogStore.shared.append(L("Пароль удалён из Keychain для учётной записи «%@»",
                                 credential.displayName), level: 0)
    }

    // MARK: - RDPMacClientDelegate

    func rdpClient(_ client: RDPMacClient, didChange state: RDPMacConnectionState,
                   message: String) {
        defer { NotificationCenter.default.post(name: Self.sessionDidChange, object: self) }
        switch state {
        case .connecting:
            sessionView.showConnecting(message)
        case .disconnecting:
            sessionView.showConnecting(L("Отключение…"))
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
        NotificationCenter.default.post(name: Self.sessionDidChange, object: self)
        lastRemoteSize = (width: Int(client.frameWidth), height: Int(client.frameHeight))
        sessionView.showConnected(width: lastRemoteSize.width, height: lastRemoteSize.height)
        sessionView.updateClipboard(client.clipboardDiagnostics())
        sessionView.rdpView.needsDisplay = true
        window?.title = "\(currentHost):\(currentPort) · \(lastRequest?.username ?? "") — RDP Mac"
        LogStore.shared.append(L("Сеанс установлен: %@×%@", String(describing: lastRemoteSize.width), String(describing: lastRemoteSize.height)),
                               level: 0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.scheduleRemoteResize()
        }
    }

    func rdpClient(_ client: RDPMacClient, didResizeToWidth width: UInt, height: UInt) {
        lastRemoteSize = (width: Int(width), height: Int(height))
        sessionView.updateResolution(width: Int(width), height: Int(height))
        sessionView.rdpView.needsDisplay = true
        LogStore.shared.append(L("Разрешение сеанса изменено: %@×%@", String(describing: width), String(describing: height)), level: 0)
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
        LogStore.shared.append("[\(sessionID) \(currentHost):\(currentPort)] \(message)", level: level)
    }

    func rdpClient(_ client: RDPMacClient, didDisconnectWithError error: String?) {
        if pendingReconnect {
            pendingReconnect = false
            retryConnection()
            return
        }
        connected = false
        sessionActive = false
        let message = error ?? L("Сеанс завершён.")
        window?.title = "RDP Mac"
        diagnosticsController?.setSessionActive(false)
        diagnosticsController?.update(diagnostics: clipboardDiagnostics,
                                      session: sessionDescription())
        LogStore.shared.append(error == nil ? L("Сеанс завершён") : L("Сеанс завершён с ошибкой: %@", String(describing: message)),
                               level: error == nil ? 0 : 2)
        if offerLegacyTLSIfNeeded(client: client, error: error) {
            return
        }
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
            ? L("Сертификат сервера изменился")
            : L("Сервер предъявил неизвестный сертификат")
        alert.informativeText = L("%@\n\nСертификат не подтверждён системным хранилищем доверия. Подключайтесь, только если\nотпечаток SHA-256 совпадает с ожидаемым. «Запомнить» сохраняет сертификат в known_hosts\nFreeRDP для этого сервера.", String(describing: info.details))
        alert.addButton(withTitle: L("Отклонить"))
        alert.addButton(withTitle: L("Принять один раз"))
        alert.addButton(withTitle: L("Принять и запомнить"))

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
        guard let client else { return L("нет клиента") }
        switch client.state {
        case .connected:
            return L("подключено, %@×%@, ", String(describing: lastRemoteSize.width), String(describing: lastRemoteSize.height))
                + "\(currentHost):\(currentPort)"
        case .connecting:
            return L("подключение к %@:%@", String(describing: currentHost), String(describing: currentPort))
        case .disconnecting:
            return L("отключение")
        default:
            return L("нет активного сеанса")
        }
    }

    // MARK: - Menu / toolbar actions

    @objc func disconnect(_ sender: Any?) {
        if sessionActive || client?.state == .connecting {
            client?.disconnect()
        } else {
            showForm(message: L("Сеанс не активен."), isError: false)
        }
    }

    @objc func sendCtrlAltDelete(_ sender: Any?) {
        guard connected else {
            LogStore.shared.append(L("Ctrl+Alt+Delete не отправлен: нет активного сеанса"), level: 1)
            return
        }
        client?.sendCtrlAltDelete()
    }

    @objc func toggleFullScreenAction(_ sender: Any?) {
        window?.toggleFullScreen(nil)
    }

    @objc func clipboardSendLocal(_ sender: Any?) {
        guard connected else {
            LogStore.shared.append(L("Буфер: нет активного сеанса"), level: 1)
            return
        }
        client?.clipboardSendLocal()
    }

    @objc func clipboardRequestRemote(_ sender: Any?) {
        guard connected else {
            LogStore.shared.append(L("Буфер: нет активного сеанса"), level: 1)
            return
        }
        client?.clipboardRequestRemote()
    }

    @objc func clipboardResync(_ sender: Any?) {
        guard connected else {
            LogStore.shared.append(L("Буфер: нет активного сеанса"), level: 1)
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
            controller.onReconnect = { [weak self] in self?.reconnectFromDiagnostics() }
            controller.onExportLog = { [weak self] in self?.exportLog(nil) }
            diagnosticsController = controller
        }
        diagnosticsController?.update(diagnostics: client?.clipboardDiagnostics()
                                          ?? clipboardDiagnostics,
                                      session: sessionDescription())
        diagnosticsController?.setSessionActive(connected)
        diagnosticsController?.window?.title = L("Буфер — %@:%@", String(describing: currentHost), String(describing: currentPort))
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
        panel.title = L("Экспорт журнала RDP Mac")
        panel.nameFieldStringValue = "rdp-mac-log.txt"
        panel.allowedContentTypes = [.plainText]
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try LogStore.shared.export(to: url)
                LogStore.shared.append(L("Журнал экспортирован: %@", String(describing: url.lastPathComponent)), level: 0)
            } catch {
                LogStore.shared.append(L("Не удалось экспортировать журнал: ")
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
        AppAbout.show()
    }

    /// Opens the shared user directory. Editing it never touches a running
    /// session: each session already received its own credentials.
    @objc func showCredentials(_ sender: Any?) {
        if credentialsController == nil {
            let controller = CredentialsWindowController()
            controller.onChange = { [weak self] in
                guard let self else { return }
                self.formView.setCredentials(CredentialStore.shared.credentials,
                                             selectedID: self.formView.currentCredential)
                self.formView.setProfiles(self.profileStore.profiles,
                                          selectedID: self.formView.selectedProfile)
                NotificationCenter.default.post(name: Self.sessionDidChange, object: self)
            }
            credentialsController = controller
        }
        credentialsController?.reload()
        credentialsController?.showWindow(nil)
        credentialsController?.window?.makeKeyAndOrderFront(nil)
    }

    /// Opens the editor with an unsaved copy. Nothing is written until the user
    /// saves it, so cancelling leaves no profile and no Keychain change.
    func applyDraftProfile(_ profile: Profile, password: String?) {
        didInitialProfileSelection = true
        formView.setProfiles(profileStore.profiles, selectedID: profile.id)
        formView.setCredentials(CredentialStore.shared.credentials, selectedID: profile.credentialID)
        formView.applyDraft(profile, password: password)
        formView.showMessage(L("Копия профиля «%@». Измените параметры и сохраните.",
                               String(describing: profile.name)), isError: false)
    }

    @objc func showHelp(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = L("RDP Mac: что уже работает")
        alert.informativeText = HelpText.supported
        alert.addButton(withTitle: L("Понятно"))
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
            LogStore.shared.append(L("DisplayControl: не удалось запросить размер %@×%@", String(describing: width), String(describing: height)),
                                   level: 1)
        }
    }

    func windowDidChangeOcclusionState(_ notification: Notification) {
        if window?.occlusionState.contains(.visible) == true {
            sessionView.rdpView.needsDisplay = true
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

    func windowDidBecomeMain(_ notification: Notification) {
        onActivate?(self)
        if !sessionActive {
            formView.setProfiles(profileStore.profiles, selectedID: formView.selectedProfile)
        }
    }

    func windowDidResignMain(_ notification: Notification) { setClipboardActive(false) }

    func windowDidBecomeKey(_ notification: Notification) {
        if connected {
            window?.makeFirstResponder(sessionView.rdpView)
        }
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        frameSize
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if closingSession { return true }
        if sessionActive || client?.state == .connecting || client?.state == .disconnecting {
            let alert = NSAlert()
            alert.messageText = L("Отключить эту сессию и закрыть окно?")
            alert.informativeText = L("Остальные подключения продолжат работу.")
            alert.addButton(withTitle: L("Отключить и закрыть"))
            alert.addButton(withTitle: L("Отмена"))
            guard alert.runModal() == .alertFirstButtonReturn else { return false }
            closingSession = true
            prepareForTermination { [weak self] in self?.window?.performClose(nil) }
            return false
        }
        return true
    }

    func windowWillClose(_ notification: Notification) {
        setClipboardActive(false)
        resizeTimer?.invalidate()
        client?.delegate = nil
        client?.disconnect()
        diagnosticsController?.close()
        logController?.close()
        credentialsController?.close()
        onClose?(self)
    }

    func prepareForTermination(_ completion: @escaping () -> Void) {
        pendingReconnect = false
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
        func poll() {
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
