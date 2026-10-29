import AppKit

struct ConnectionRequest {
    let host: String
    let port: Int
    let username: String
    let domain: String
    let password: String
    let security: ConnectionSecurity
    let clipboardEnabled: Bool
    let commandAsControl: Bool
    let autoResize: Bool
    let resolution: ResolutionMode
    let savePassword: Bool
    let profileID: UUID?
    let legacyTLS: Bool

    func withLegacyTLS() -> ConnectionRequest {
        ConnectionRequest(host: host,
                          port: port,
                          username: username,
                          domain: domain,
                          password: password,
                          security: security,
                          clipboardEnabled: clipboardEnabled,
                          commandAsControl: commandAsControl,
                          autoResize: autoResize,
                          resolution: resolution,
                          savePassword: savePassword,
                          profileID: profileID,
                          legacyTLS: true)
    }
}

final class ConnectFormView: NSView {
    var onConnect: ((ConnectionRequest) -> Void)?
    var onSaveProfile: ((Profile) -> Void)?
    var onDeleteProfile: ((UUID) -> Void)?
    var onForgetPassword: (() -> Void)?
    var onProfileSelected: ((UUID?) -> Void)?
    var onShowDiagnostics: (() -> Void)?
    var onShowLog: (() -> Void)?

    private let profilePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let saveProfileButton = UI.button(L("Сохранить профиль"), target: nil, action: nil)
    private let deleteProfileButton = UI.button(L("Удалить профиль"), target: nil, action: nil)
    private let groupField = UI.textField(placeholder: L("Например: Работа или Дом"), width: 300)
    private let hostField = UI.textField(placeholder: "server.example.local", width: 300)
    private let portField = UI.textField(placeholder: "3389", width: 70)
    private let usernameField = UI.textField(placeholder: L("Пользователь"), width: 220)
    private let domainField = UI.textField(placeholder: L("Домен (необязательно)"), width: 200)
    private let passwordField = UI.secureField(placeholder: L("Пароль"), width: 300)
    private let savePasswordCheckbox =
        UI.checkbox(L("Сохранить пароль в Keychain"), target: nil, action: nil)
    private let forgetPasswordButton = UI.button(L("Забыть пароль"), target: nil, action: nil)
    private let securityPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let resolutionPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let clipboardCheckbox =
        UI.checkbox(L("Двусторонний текстовый буфер обмена"), target: nil, action: nil, state: true)
    private let commandAsControlCheckbox =
        UI.checkbox(L("Передавать Command как Ctrl (Cmd+C → Ctrl+C)"), target: nil, action: nil,
                    state: true)
    private let autoResizeCheckbox =
        UI.checkbox(L("Подстраивать разрешение под окно (DisplayControl)"), target: nil, action: nil,
                    state: true)
    private let legacyTLSCheckbox =
        UI.checkbox(L("Совместимость TLS со старыми серверами (снижает стойкость)"),
                    target: nil, action: nil, state: false)
    private let connectButton = UI.button(L("Подключиться"), target: nil, action: nil)
    private let progress = NSProgressIndicator()
    private let statusLabel = UI.label("", size: 12, color: .secondaryLabelColor, lines: 3)
    private let diagnosticsButton = UI.button(L("Диагностика буфера"), target: nil, action: nil)
    private let logButton = UI.button(L("Журнал"), target: nil, action: nil)

    private var advancedView: NSView?
    private var advancedToggle: NSButton?
    private var profiles: [Profile] = []
    private var selectedProfileID: UUID?
    private var programmaticSelection = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    private func buildUI() {
        translatesAutoresizingMaskIntoConstraints = false

        let title = UI.label(L("Подключение к удалённому рабочему столу"), size: 20, weight: .semibold)
        let subtitle = UI.label(L("FreeRDP 3.32.2 · нативный клиент для macOS x86_64"),
                                size: 12, color: .secondaryLabelColor)

        profilePopup.translatesAutoresizingMaskIntoConstraints = false
        profilePopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 240).isActive = true
        profilePopup.target = self
        profilePopup.action = #selector(profileChanged(_:))
        saveProfileButton.target = self
        saveProfileButton.action = #selector(saveProfile(_:))
        deleteProfileButton.target = self
        deleteProfileButton.action = #selector(deleteProfile(_:))
        forgetPasswordButton.target = self
        forgetPasswordButton.action = #selector(forgetPassword(_:))
        connectButton.target = self
        connectButton.action = #selector(connect(_:))
        connectButton.keyEquivalent = "\r"
        diagnosticsButton.target = self
        diagnosticsButton.action = #selector(showDiagnostics(_:))
        logButton.target = self
        logButton.action = #selector(showLog(_:))
        savePasswordCheckbox.target = self
        savePasswordCheckbox.action = #selector(savePasswordToggled(_:))
        legacyTLSCheckbox.target = self
        legacyTLSCheckbox.action = #selector(legacyTLSToggled(_:))

        securityPopup.addItems(withTitles: ConnectionSecurity.allCases.map { $0.title })
        securityPopup.selectItem(at: 0)
        resolutionPopup.addItems(withTitles: ResolutionMode.allCases.map { $0.title })
        resolutionPopup.selectItem(at: 0)

        progress.style = .spinning
        progress.controlSize = .small
        progress.isDisplayedWhenStopped = false

        let profileRow = UI.hStack([profilePopup, saveProfileButton, deleteProfileButton])
        let serverRow = UI.hStack([hostField, UI.label(L("Порт")), portField])
        let userRow = UI.hStack([usernameField, UI.label(L("Домен")), domainField])
        let passwordRow = UI.hStack([passwordField, savePasswordCheckbox, forgetPasswordButton])
        let securityRow = UI.hStack([securityPopup])
        let resolutionRow = UI.hStack([resolutionPopup])
        legacyTLSCheckbox.toolTip =
            L("Разрешает TLS SECLEVEL=0 для серверов со старыми сертификатами ")
            + L("(например, SHA-1/RSA-1024). Сертификат всё равно нужно подтвердить вручную.")
        let options = UI.vStack([clipboardCheckbox, commandAsControlCheckbox, autoResizeCheckbox,
                                 legacyTLSCheckbox], spacing: 5)
        let actionRow = UI.hStack([connectButton, progress], spacing: 12)
        let footer = UI.hStack([diagnosticsButton, logButton], spacing: 8)

        let grid = NSGridView(views: [
            [UI.label(L("Профиль"), weight: .medium), profileRow],
            [UI.label(L("Группа"), weight: .medium), groupField],
            [UI.label(L("Сервер"), weight: .medium), serverRow],
            [UI.label(L("Пользователь"), weight: .medium), userRow],
            [UI.label(L("Пароль"), weight: .medium), passwordRow]
        ])
        let advanced = NSGridView(views: [
            [UI.label(L("Безопасность"), weight: .medium), securityRow],
            [UI.label(L("Разрешение"), weight: .medium), resolutionRow],
            [NSGridCell.emptyContentView, options]
        ])
        for section in [grid, advanced] {
            section.translatesAutoresizingMaskIntoConstraints = false
            section.rowSpacing = 10
            section.columnSpacing = 14
            section.column(at: 0).xPlacement = .trailing
            section.rowAlignment = .firstBaseline
        }
        advanced.isHidden = true
        advancedView = advanced
        let disclosure = NSButton(checkboxWithTitle: L("Дополнительные параметры"), target: self,
                                  action: #selector(toggleAdvanced(_:)))
        disclosure.setButtonType(.onOff)
        advancedToggle = disclosure
        for (field, label) in [(hostField, L("Сервер")), (portField, L("Порт")),
                               (usernameField, L("Пользователь")), (domainField, L("Домен")),
                               (passwordField, L("Пароль")), (groupField, L("Группа"))] {
            field.setAccessibilityLabel(label)
        }

        let hint = UI.label(L("Пароль не сохраняется в JSON-профиле. Keychain используется только при ")
                            + L("явном согласии. Проверка сертификата включена всегда."),
                            size: 11, color: .tertiaryLabelColor, lines: 2)

        let stack = UI.vStack([title, subtitle, UI.divider(), grid, disclosure, advanced, actionRow, statusLabel,
                               footer, hint], spacing: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -20),
            grid.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor)
        ])
    }

    @objc private func toggleAdvanced(_ sender: NSButton) {
        advancedView?.isHidden = sender.state != .on
    }

    // MARK: - Public API

    func setProfiles(_ profiles: [Profile], selectedID: UUID?) {
        self.profiles = profiles
        self.selectedProfileID = selectedID
        programmaticSelection = true
        profilePopup.removeAllItems()
        profilePopup.addItem(withTitle: L("— Новый профиль —"))
        for profile in profiles {
            profilePopup.addItem(withTitle: profile.displayName)
        }
        if let selectedID,
           let index = profiles.firstIndex(where: { $0.id == selectedID }) {
            profilePopup.selectItem(at: index + 1)
        } else {
            self.selectedProfileID = nil
            profilePopup.selectItem(at: 0)
        }
        programmaticSelection = false
        deleteProfileButton.isEnabled = self.selectedProfileID != nil
    }

    func applyProfile(_ profile: Profile, password: String?) {
        groupField.stringValue = profile.group ?? ""
        hostField.stringValue = profile.host
        portField.stringValue = String(profile.port)
        usernameField.stringValue = profile.username
        domainField.stringValue = profile.domain
        let hasAdvancedSettings = profile.security != .negotiate || (profile.legacyTLS ?? false)
        advancedView?.isHidden = !hasAdvancedSettings
        advancedToggle?.state = hasAdvancedSettings ? .on : .off
        securityPopup.selectItem(at: profile.security.rawValue)
        resolutionPopup.selectItem(at: profile.resolution.rawValue)
        clipboardCheckbox.state = profile.clipboardEnabled ? .on : .off
        commandAsControlCheckbox.state = profile.commandAsControl ? .on : .off
        autoResizeCheckbox.state = profile.autoResize ? .on : .off
        legacyTLSCheckbox.state = (profile.legacyTLS ?? false) ? .on : .off
        savePasswordCheckbox.state = profile.savePassword ? .on : .off
        passwordField.stringValue = password ?? ""
        selectedProfileID = profile.id
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            programmaticSelection = true
            profilePopup.selectItem(at: index + 1)
            programmaticSelection = false
        }
        deleteProfileButton.isEnabled = true
    }

    func clearProfileSelection() {
        selectedProfileID = nil
        programmaticSelection = true
        profilePopup.selectItem(at: 0)
        programmaticSelection = false
        deleteProfileButton.isEnabled = false
    }

    func makeProfile(name: String) -> Profile {
        Profile(id: selectedProfileID ?? UUID(),
                name: name,
                host: hostField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
                port: Int(portField.stringValue) ?? 3389,
                username: usernameField.stringValue,
                domain: domainField.stringValue,
                security: selectedSecurity,
                savePassword: savePasswordCheckbox.state == .on,
                clipboardEnabled: clipboardCheckbox.state == .on,
                commandAsControl: commandAsControlCheckbox.state == .on,
                autoResize: autoResizeCheckbox.state == .on,
                resolution: selectedResolution,
                legacyTLS: legacyTLSCheckbox.state == .on,
                group: groupField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var selectedProfile: UUID? { selectedProfileID }
    var currentPassword: String { passwordField.stringValue }

    var currentAccount: String {
        KeychainStore.account(host: hostField.stringValue,
                              port: Int(portField.stringValue) ?? 3389,
                              domain: domainField.stringValue,
                              username: usernameField.stringValue)
    }

    func clearPassword() {
        passwordField.stringValue = ""
    }

    func setLegacyTLS(_ enabled: Bool) {
        legacyTLSCheckbox.state = enabled ? .on : .off
    }

    func focusHost() {
        window?.makeFirstResponder(hostField)
    }

    func showMessage(_ text: String, isError: Bool) {
        statusLabel.stringValue = text
        statusLabel.textColor = isError ? .systemRed : .secondaryLabelColor
    }

    func setBusy(_ busy: Bool, message: String? = nil) {
        connectButton.isEnabled = !busy
        saveProfileButton.isEnabled = !busy
        deleteProfileButton.isEnabled = !busy && selectedProfileID != nil
        profilePopup.isEnabled = !busy
        groupField.isEnabled = !busy
        hostField.isEnabled = !busy
        portField.isEnabled = !busy
        usernameField.isEnabled = !busy
        domainField.isEnabled = !busy
        passwordField.isEnabled = !busy
        securityPopup.isEnabled = !busy
        resolutionPopup.isEnabled = !busy
        if busy {
            progress.startAnimation(nil)
            connectButton.title = L("Подключение…")
            if let message { showMessage(message, isError: false) }
        } else {
            progress.stopAnimation(nil)
            connectButton.title = L("Подключиться")
        }
    }

    private var selectedSecurity: ConnectionSecurity {
        ConnectionSecurity(rawValue: securityPopup.indexOfSelectedItem) ?? .negotiate
    }

    private var selectedResolution: ResolutionMode {
        ResolutionMode(rawValue: resolutionPopup.indexOfSelectedItem) ?? .window
    }

    // MARK: - Actions

    @objc private func profileChanged(_ sender: NSPopUpButton) {
        guard !programmaticSelection else { return }
        let index = sender.indexOfSelectedItem
        if index <= 0 {
            selectedProfileID = nil
            deleteProfileButton.isEnabled = false
            onProfileSelected?(nil)
            return
        }
        let profile = profiles[index - 1]
        selectedProfileID = profile.id
        deleteProfileButton.isEnabled = true
        onProfileSelected?(profile.id)
    }

    @objc private func saveProfile(_ sender: Any?) {
        let host = hostField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else {
            showMessage(L("Укажите адрес сервера перед сохранением профиля."), isError: true)
            return
        }
        onSaveProfile?(makeProfile(name: ""))
    }

    @objc private func deleteProfile(_ sender: Any?) {
        guard let selectedProfileID else { return }
        onDeleteProfile?(selectedProfileID)
    }

    @objc private func forgetPassword(_ sender: Any?) {
        onForgetPassword?()
    }

    @objc private func savePasswordToggled(_ sender: Any?) {
        if savePasswordCheckbox.state == .off {
            showMessage(L("Пароль не будет сохранён. Уже сохранённый можно удалить кнопкой ")
                        + L("«Забыть пароль»."), isError: false)
        }
    }

    @objc private func legacyTLSToggled(_ sender: Any?) {
        if legacyTLSCheckbox.state == .on {
            showMessage(L("Включён совместимый TLS (SECLEVEL=0). Используйте только для доверенных ")
                        + L("старых серверов; сертификат всё равно проверяется вручную."),
                        isError: false)
        }
    }

    @objc private func showDiagnostics(_ sender: Any?) {
        onShowDiagnostics?()
    }

    @objc private func showLog(_ sender: Any?) {
        onShowLog?()
    }

    func submitConnection() { connect(nil) }

    @objc private func connect(_ sender: Any?) {
        let host = hostField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else {
            showMessage(L("Укажите адрес сервера."), isError: true)
            focusHost()
            return
        }
        guard let port = Int(portField.stringValue), port >= 1, port <= 65535 else {
            showMessage(L("Порт должен быть числом от 1 до 65535."), isError: true)
            return
        }
        let username = usernameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !username.isEmpty else {
            showMessage(L("Укажите имя пользователя."), isError: true)
            window?.makeFirstResponder(usernameField)
            return
        }

        let request = ConnectionRequest(host: host,
                                        port: port,
                                        username: username,
                                        domain: domainField.stringValue
                                            .trimmingCharacters(in: .whitespacesAndNewlines),
                                        password: passwordField.stringValue,
                                        security: selectedSecurity,
                                        clipboardEnabled: clipboardCheckbox.state == .on,
                                        commandAsControl: commandAsControlCheckbox.state == .on,
                                        autoResize: autoResizeCheckbox.state == .on,
                                        resolution: selectedResolution,
                                        savePassword: savePasswordCheckbox.state == .on,
                                        profileID: selectedProfileID,
                                        legacyTLS: legacyTLSCheckbox.state == .on)
        onConnect?(request)
    }
}
