import AppKit

/// User directory window: add, edit, copy and delete saved accounts. Passwords
/// are only ever written to the Keychain; nothing here displays or logs one.
final class CredentialsWindowController: NSWindowController, NSWindowDelegate,
                                         NSTableViewDataSource, NSTableViewDelegate {
    var onChange: (() -> Void)?
    private var store: CredentialStore = .shared
    private var profiles: ProfileStore = .shared
    private let table = NSTableView()
    private let addButton = UI.button(L("Добавить"), target: nil, action: nil)
    private let editButton = UI.button(L("Изменить"), target: nil, action: nil)
    private let copyButton = UI.button(L("Копировать"), target: nil, action: nil)
    private let deleteButton = UI.button(L("Удалить"), target: nil, action: nil)
    private var rows: [Credential] = []

    convenience init(store: CredentialStore = .shared, profiles: ProfileStore = .shared) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 460),
                              styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        window.title = L("Справочник учётных записей")
        window.minSize = NSSize(width: 560, height: 320)
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window: window)
        self.store = store
        self.profiles = profiles
        window.delegate = self
        buildUI()
        NotificationCenter.default.addObserver(self, selector: #selector(reload),
                                               name: CredentialStore.didChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(reload),
                                               name: ProfileStore.didChange, object: nil)
        reload()
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    private func buildUI() {
        guard let content = window?.contentView else { return }
        let title = UI.label(L("Сохранённые учётные записи"), size: 20, weight: .semibold)
        let hint = UI.label(L("Пароли хранятся только в Keychain. Одна запись может использоваться несколькими подключениями."),
                            size: 11, color: .secondaryLabelColor, lines: 2)
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.documentView = table
        table.headerView = NSTableHeaderView()
        for (id, title, width) in [("name", L("Название"), 220.0),
                                   ("account", L("Пользователь"), 240.0),
                                   ("usage", L("Подключений"), 120.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = title
            column.width = width
            table.addTableColumn(column)
        }
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = false
        table.delegate = self
        table.dataSource = self
        table.target = self
        table.doubleAction = #selector(editSelected(_:))
        for (button, action) in [(addButton, #selector(addCredential(_:))),
                                 (editButton, #selector(editSelected(_:))),
                                 (copyButton, #selector(copySelected(_:))),
                                 (deleteButton, #selector(deleteSelected(_:)))] {
            button.target = self
            button.action = action
        }
        let close = UI.button(L("Закрыть"), target: self, action: #selector(closeWindow(_:)))
        let actions = UI.hStack([addButton, editButton, copyButton, deleteButton, NSView(), close],
                                spacing: 8)
        let stack = UI.vStack([title, hint, scroll, actions], spacing: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        for view in [hint, scroll, actions] {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 180)
        ])
    }

    // MARK: - Table

    @objc func reload() {
        let selected = selectedCredential()?.id
        rows = store.credentials
        table.reloadData()
        if let selected, let index = rows.firstIndex(where: { $0.id == selected }) {
            table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        }
        updateButtons()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableViewSelectionDidChange(_ notification: Notification) { updateButtons() }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?,
                   row: Int) -> NSView? {
        guard rows.indices.contains(row) else { return nil }
        let credential = rows[row]
        switch tableColumn?.identifier.rawValue {
        case "account":
            return UI.label(credential.accountName.isEmpty ? "—" : credential.accountName,
                            size: 12, color: .secondaryLabelColor)
        case "usage":
            let count = useCount(credential)
            return UI.label(count == 0 ? L("не используется")
                                       : L("Подключений: %@", String(describing: count)),
                            size: 12, color: count > 1 ? .systemOrange : .secondaryLabelColor)
        default:
            return UI.vStack([UI.label(credential.displayName, size: 14, weight: .medium),
                              UI.label(store.hasPassword(credential)
                                       ? L("Пароль сохранён в Keychain")
                                       : L("Пароль не сохранён"),
                                       size: 11, color: .secondaryLabelColor)], spacing: 3)
        }
    }

    private func updateButtons() {
        let count = table.selectedRowIndexes.count
        editButton.isEnabled = count == 1
        copyButton.isEnabled = count == 1
        deleteButton.isEnabled = count == 1
    }

    private func useCount(_ credential: Credential) -> Int {
        profiles.profilesUsing(credentialID: credential.id).count
    }

    private func selectedCredential() -> Credential? {
        let index = table.selectedRow
        guard rows.indices.contains(index) else { return nil }
        return rows[index]
    }

    // MARK: - Actions

    @objc private func addCredential(_ sender: Any?) {
        guard let draft = promptForCredential(nil) else { return }
        store.upsert(draft.credential)
        if let password = draft.password, draft.savePassword, !password.isEmpty {
            store.savePassword(password, for: draft.credential)
        }
        reload()
        onChange?()
    }

    @objc private func editSelected(_ sender: Any?) {
        guard let credential = selectedCredential() else { return }
        guard let edited = promptForCredential(credential) else { return }
        store.upsert(edited.credential)
        if let password = edited.password, edited.savePassword, !password.isEmpty {
            store.savePassword(password, for: edited.credential)
        } else if !edited.savePassword {
            store.forgetPassword(for: edited.credential)
        }
        reload()
        onChange?()
    }

    @objc private func copySelected(_ sender: Any?) {
        guard let credential = selectedCredential() else { return }
        let copy = store.duplicate(credential)
        if !store.hasPassword(copy) {
            // Reading the original secret can fail (locked or denied Keychain);
            // the copy still works and can be filled in later.
            LogStore.shared.append(L("Учётная запись скопирована без пароля: Keychain недоступен"),
                                   level: 1)
        }
        reload()
        if let index = rows.firstIndex(where: { $0.id == copy.id }) {
            table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        }
        onChange?()
    }

    @objc private func deleteSelected(_ sender: Any?) {
        guard let credential = selectedCredential() else { return }
        let usage = useCount(credential)
        let alert = NSAlert()
        alert.messageText = L("Удалить учётную запись «%@»?", credential.displayName)
        alert.informativeText = usage == 0
            ? L("Сохранённый пароль будет удалён из Keychain.")
            : L("Запись используется в %@ подключениях. Они останутся, но сохранят только логин и домен; пароль будет удалён из Keychain.",
                String(describing: usage))
        alert.addButton(withTitle: L("Удалить"))
        alert.addButton(withTitle: L("Отмена"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        profiles.detachProfiles(credentialID: credential.id)
        store.delete(id: credential.id)
        reload()
        onChange?()
    }

    @objc private func closeWindow(_ sender: Any?) {
        window?.performClose(nil)
    }

    func windowWillClose(_ notification: Notification) {
        onChange?()
    }

    // MARK: - Editing sheet

    private struct Draft {
        var credential: Credential
        var password: String?
        var savePassword: Bool
    }

    private func promptForCredential(_ existing: Credential?) -> Draft? {
        let usage = existing.map { useCount($0) } ?? 0
        let alert = NSAlert()
        alert.messageText = existing == nil ? L("Новая учётная запись")
                                            : L("Изменить учётную запись")
        if usage > 1 {
            alert.informativeText = L("Запись используется в %@ подключениях: изменение логина, домена или пароля затронет все.",
                                      String(describing: usage))
        } else {
            alert.informativeText = L("Пароль записывается только в Keychain и никогда — в JSON-файлы или журнал.")
        }
        alert.addButton(withTitle: L("Сохранить"))
        alert.addButton(withTitle: L("Отмена"))

        let titleField = UI.textField(placeholder: L("Название (необязательно)"))
        let userField = UI.textField(placeholder: L("Пользователь"))
        let domainField = UI.textField(placeholder: L("Домен (необязательно)"))
        let passwordField = UI.secureField(placeholder: L("Пароль"))
        let saveCheckbox = UI.checkbox(L("Сохранить пароль в Keychain"), target: nil, action: nil)
        titleField.stringValue = existing?.title ?? ""
        userField.stringValue = existing?.username ?? ""
        domainField.stringValue = existing?.domain ?? ""
        saveCheckbox.state = (existing.map { store.hasPassword($0) } ?? false) ? .on : .off

        let form = UI.vStack([titleField, userField, domainField,
                              UI.hStack([passwordField, saveCheckbox], spacing: 10)], spacing: 8)
        form.translatesAutoresizingMaskIntoConstraints = false
        form.widthAnchor.constraint(equalToConstant: 360).isActive = true
        alert.accessoryView = form
        alert.window.initialFirstResponder = userField

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let username = userField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !username.isEmpty else {
            let warning = NSAlert()
            warning.messageText = L("Укажите имя пользователя.")
            warning.addButton(withTitle: L("Понятно"))
            warning.runModal()
            return nil
        }

        var credential = existing ?? Credential()
        credential.title = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        credential.username = username
        credential.domain = domainField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let typed = passwordField.stringValue
        return Draft(credential: credential,
                     password: typed.isEmpty ? nil : typed,
                     savePassword: saveCheckbox.state == .on)
    }
}
