import AppKit

/// Saved profiles are shared; each launch creates an independent session window.
final class ConnectionsWindowController: NSWindowController, NSWindowDelegate,
                                         NSTableViewDataSource, NSTableViewDelegate,
                                         NSSearchFieldDelegate, NSMenuDelegate {
    enum Row {
        case group(String)
        case profile(Profile)
    }
    var profilesProvider: () -> [Profile] = { ProfileStore.shared.profiles }
    var onEdit: ((Profile) -> Void)?
    var onDuplicate: ((Profile) -> Void)?
    private var collapsedGroups: Set<String> = []
    var onOpen: ((Profile) -> Void)?
    var onNew: (() -> Void)?
    var onActivate: (() -> Void)?
    var sessionStatus: ((UUID) -> String)?
    private let table = NSTableView()
    private let search = NSSearchField()
    private let openButton = UI.button(L("Открыть выбранные"), target: nil, action: nil)
    private let editButton = UI.button(L("Изменить профиль"), target: nil, action: nil)
    private let duplicateButton = UI.button(L("Дублировать"), target: nil, action: nil)
    private let emptyLabel = UI.label(L("Нет подключений. Нажмите «Новое подключение» и сохраните профиль."),
                                      size: 13, color: .secondaryLabelColor, lines: 2)
    private(set) var rows: [Row] = []

    convenience init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 650),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = L("Подключения — RDP Mac")
        window.minSize = NSSize(width: 760, height: 440)
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("RDPMacConnections")
        self.init(window: window)
        window.delegate = self
        buildUI()
        NotificationCenter.default.addObserver(self, selector: #selector(reload),
                                               name: ProfileStore.didChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(reload),
                                               name: MainWindowController.sessionDidChange, object: nil)
        reload()
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    private func buildUI() {
        guard let content = window?.contentView else { return }
        let title = UI.label(L("Сохранённые подключения"), size: 22, weight: .semibold)
        let new = UI.button(L("Новое подключение"), target: self, action: #selector(newConnection(_:)))
        editButton.target = self
        editButton.action = #selector(editSelected(_:))
        duplicateButton.target = self
        duplicateButton.action = #selector(duplicateSelected(_:))
        openButton.target = self
        openButton.action = #selector(openSelected(_:))
        search.placeholderString = L("Поиск по имени, серверу, пользователю или группе")
        search.delegate = self
        search.widthAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true
        let toolbar = UI.hStack([title, NSView(), new], spacing: 12)
        let actions = UI.hStack([search, editButton, duplicateButton, openButton], spacing: 12)
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.documentView = table
        table.headerView = NSTableHeaderView()
        for (id, title, width) in [("name", L("Подключение"), 300.0), ("account", L("Пользователь"), 220.0),
                                    ("status", L("Сессии"), 150.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = title
            column.width = width
            table.addTableColumn(column)
        }
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = true
        table.delegate = self
        table.dataSource = self
        table.target = self
        table.doubleAction = #selector(openSelected(_:))
        let contextMenu = NSMenu()
        contextMenu.delegate = self
        table.menu = contextMenu
        let hint = UI.label(L("Двойной щелчок открывает профиль в новом окне. ⌘N — новая сессия. ")
                             + L("Буфер обмена синхронизируется только с активной сессией."),
                            size: 11, color: .secondaryLabelColor, lines: 2)
        let stack = UI.vStack([toolbar, actions, emptyLabel, scroll, hint], spacing: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        for view in [toolbar, actions, emptyLabel, scroll, hint] {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 220)
        ])
    }

    static func groupedRows(profiles: [Profile], query: String, collapsedGroups: Set<String> = []) -> [Row] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let profiles = profiles.filter { profile in
            query.isEmpty || [profile.displayName, profile.host, profile.username,
                              profile.domain, profile.groupName].contains {
                $0.localizedCaseInsensitiveContains(query)
            }
        }
        let groups = Dictionary(grouping: profiles, by: { $0.groupName })
        return groups.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .flatMap { name -> [Row] in
                [.group(name)] + (query.isEmpty && collapsedGroups.contains(name) ? [] : (groups[name] ?? [])).sorted {
                    $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
                }.map { .profile($0) }
            }
    }

    @objc func reload() {
        let selection = Set(table.selectedRowIndexes.compactMap { index -> UUID? in
            guard rows.indices.contains(index), case .profile(let profile) = rows[index] else { return nil }
            return profile.id
        })
        rows = Self.groupedRows(profiles: profilesProvider(), query: search.stringValue, collapsedGroups: collapsedGroups)
        table.reloadData()
        let indexes = rows.indices.filter {
            if case .profile(let profile) = rows[$0] { return selection.contains(profile.id) }
            return false
        }
        table.selectRowIndexes(IndexSet(indexes), byExtendingSelection: false)
        updateSelectionState()
        emptyLabel.isHidden = !rows.isEmpty
        emptyLabel.stringValue = search.stringValue.isEmpty
            ? L("Нет подключений. Нажмите «Новое подключение» и сохраните профиль.")
            : L("Подключения не найдены.")
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
    func tableViewSelectionDidChange(_ notification: Notification) {
        updateSelectionState()
    }
    private func updateSelectionState() {
        editButton.isEnabled = table.selectedRowIndexes.count == 1
        duplicateButton.isEnabled = canDuplicateSelection
        openButton.isEnabled = table.selectedRowIndexes.contains { index in
            rows.indices.contains(index) && {
                if case .profile = rows[index] { return true }
                return false
            }()
        }
    }

    /// Exactly one saved profile is selected, so "Duplicate" has a single source.
    var canDuplicateSelection: Bool {
        Self.canDuplicate(rows: rows, selection: table.selectedRowIndexes)
    }

    static func canDuplicate(rows: [Row], selection: IndexSet) -> Bool {
        guard selection.count == 1, let index = selection.first, rows.indices.contains(index) else {
            return false
        }
        if case .profile = rows[index] { return true }
        return false
    }
    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        if case .group = rows[row] { return true }
        return false
    }
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        if case .profile = rows[row] { return true }
        return false
    }
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        if case .group = rows[row] { return 34 }
        return 58
    }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch rows[row] {
        case .group(let name):
            let title = "\(collapsedGroups.contains(name) && search.stringValue.isEmpty ? "▸" : "▾") \(name)"
            let button = NSButton(title: title, target: self, action: #selector(toggleGroup(_:)))
            button.isBordered = false
            button.font = .systemFont(ofSize: 15, weight: .semibold)
            button.alignment = .left
            button.tag = row
            button.setAccessibilityLabel(name)
            return button
        case .profile(let profile):
            switch tableColumn?.identifier.rawValue {
            case "account":
                let account = profile.domain.isEmpty ? profile.username : "\(profile.domain)\\\(profile.username)"
                return UI.label(account, size: 12, color: .secondaryLabelColor)
            case "status":
                return UI.label(sessionStatus?(profile.id) ?? "—", size: 12, color: .secondaryLabelColor)
            default:
                return UI.vStack([UI.label(profile.displayName, size: 14, weight: .medium),
                                  UI.label("\(profile.host):\(profile.port)", size: 11,
                                           color: .secondaryLabelColor)], spacing: 3)
            }
        }
    }
    func controlTextDidChange(_ obj: Notification) { reload() }
    func windowDidBecomeMain(_ notification: Notification) { onActivate?(); reload() }
    @objc private func newConnection(_ sender: Any?) { onNew?() }
    @objc private func toggleGroup(_ sender: NSButton) {
        guard rows.indices.contains(sender.tag), case .group(let name) = rows[sender.tag] else { return }
        if !collapsedGroups.insert(name).inserted { collapsedGroups.remove(name) }
        reload()
    }
    @objc private func editSelected(_ sender: Any?) {
        guard table.selectedRowIndexes.count == 1, let index = table.selectedRowIndexes.first,
              rows.indices.contains(index), case .profile(let profile) = rows[index] else { return }
        onEdit?(profile)
    }

    /// Opens the editor with an unsaved copy of the selected profile.
    @objc func duplicateSelected(_ sender: Any?) {
        guard canDuplicateSelection, let index = table.selectedRowIndexes.first,
              rows.indices.contains(index), case .profile(let profile) = rows[index] else { return }
        onDuplicate?(profile)
    }
    @objc func openSelected(_ sender: Any?) {
        let profiles = table.selectedRowIndexes.compactMap { index -> Profile? in
            guard rows.indices.contains(index), case .profile(let profile) = rows[index] else { return nil }
            return profile
        }
        for profile in profiles { onOpen?(profile) }
    }

    // MARK: - Context menu

    private var clickedProfile: Profile? {
        let index = table.clickedRow
        guard rows.indices.contains(index), case .profile(let profile) = rows[index] else { return nil }
        return profile
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard clickedProfile != nil else { return }
        for (title, action) in [(L("Открыть"), #selector(openClicked(_:))),
                                (L("Изменить"), #selector(editClicked(_:))),
                                (L("Дублировать"), #selector(duplicateClicked(_:)))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
    }

    @objc private func openClicked(_ sender: Any?) {
        guard let profile = clickedProfile else { return }
        onOpen?(profile)
    }

    @objc private func editClicked(_ sender: Any?) {
        guard let profile = clickedProfile else { return }
        onEdit?(profile)
    }

    @objc private func duplicateClicked(_ sender: Any?) {
        guard let profile = clickedProfile else { return }
        onDuplicate?(profile)
    }
}
