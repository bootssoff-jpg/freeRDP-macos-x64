import AppKit

/// Saved profiles are shared; each launch creates an independent session window.
final class ConnectionsWindowController: NSWindowController, NSWindowDelegate,
                                         NSTableViewDataSource, NSTableViewDelegate,
                                         NSSearchFieldDelegate {
    enum Row {
        case group(String)
        case profile(Profile)
    }
    var onOpen: ((Profile) -> Void)?
    var onNew: (() -> Void)?
    var onActivate: (() -> Void)?
    var sessionStatus: ((UUID) -> String)?
    private let table = NSTableView()
    private let search = NSSearchField()
    private let openButton = UI.button("Открыть выбранные", target: nil, action: nil)
    private let emptyLabel = UI.label("Нет подключений. Нажмите «Новое подключение» и сохраните профиль.",
                                      size: 13, color: .secondaryLabelColor, lines: 2)
    private(set) var rows: [Row] = []

    convenience init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 650),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Подключения — RDP Mac"
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
        let title = UI.label("Сохранённые подключения", size: 22, weight: .semibold)
        let new = UI.button("Новое подключение", target: self, action: #selector(newConnection(_:)))
        openButton.target = self
        openButton.action = #selector(openSelected(_:))
        search.placeholderString = "Поиск по имени, серверу, пользователю или группе"
        search.delegate = self
        search.widthAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true
        let toolbar = UI.hStack([title, NSView(), new], spacing: 12)
        let actions = UI.hStack([search, openButton], spacing: 12)
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.documentView = table
        table.headerView = NSTableHeaderView()
        for (id, title, width) in [("name", "Подключение", 300.0), ("account", "Пользователь", 220.0),
                                    ("status", "Сессии", 150.0)] {
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
        let hint = UI.label("Двойной щелчок открывает профиль в новом окне. ⌘N — новая сессия. "
                             + "Буфер обмена синхронизируется только с активной сессией.",
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

    static func groupedRows(profiles: [Profile], query: String) -> [Row] {
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
                [.group(name)] + (groups[name] ?? []).sorted {
                    $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
                }.map { .profile($0) }
            }
    }

    @objc func reload() {
        let selection = Set(table.selectedRowIndexes.compactMap { index -> UUID? in
            guard rows.indices.contains(index), case .profile(let profile) = rows[index] else { return nil }
            return profile.id
        })
        rows = Self.groupedRows(profiles: ProfileStore.shared.profiles, query: search.stringValue)
        table.reloadData()
        let indexes = rows.indices.filter {
            if case .profile(let profile) = rows[$0] { return selection.contains(profile.id) }
            return false
        }
        table.selectRowIndexes(IndexSet(indexes), byExtendingSelection: false)
        updateSelectionState()
        emptyLabel.isHidden = !rows.isEmpty
        emptyLabel.stringValue = search.stringValue.isEmpty
            ? "Нет подключений. Нажмите «Новое подключение» и сохраните профиль."
            : "Подключения не найдены."
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
    func tableViewSelectionDidChange(_ notification: Notification) {
        updateSelectionState()
    }
    private func updateSelectionState() {
        openButton.isEnabled = table.selectedRowIndexes.contains { index in
            rows.indices.contains(index) && {
                if case .profile = rows[index] { return true }
                return false
            }()
        }
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
            return UI.label(name, size: 15, weight: .semibold)
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
    @objc func openSelected(_ sender: Any?) {
        let profiles = table.selectedRowIndexes.compactMap { index -> Profile? in
            guard rows.indices.contains(index), case .profile(let profile) = rows[index] else { return nil }
            return profile
        }
        for profile in profiles { onOpen?(profile) }
    }
}
