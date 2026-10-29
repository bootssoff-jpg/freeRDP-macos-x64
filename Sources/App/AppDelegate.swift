import AppKit
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var sessionControllers: [MainWindowController] = []
    private var connectionsController: ConnectionsWindowController?
    private var globalLogController: LogWindowController?
    private var sessionMenuItems: [NSMenuItem] = []
    private weak var activeController: MainWindowController?

    /// The session that should receive menu commands. A key session window wins
    /// over the last activated one (for example after using the Window menu).
    private var commandTarget: MainWindowController? {
        if let key = NSApp.keyWindow?.windowController as? MainWindowController {
            return key
        }
        return activeController
    }

    @discardableResult
    func createSession(profile: Profile? = nil, showWindow: Bool = true) -> MainWindowController {
        let controller = MainWindowController(showWindow: showWindow)
        sessionControllers.append(controller)
        controller.onActivate = { [weak self] controller in self?.activateSession(controller) }
        controller.onClose = { [weak self] controller in
            guard let self else { return }
            self.sessionControllers.removeAll { $0 === controller }
            if self.activeController === controller { self.activateSession(nil) }
            self.connectionsController?.reload()
        }
        if let profile { controller.openProfile(profile) }
        if showWindow {
            controller.window?.cascadeTopLeft(from: NSPoint(x: 100 + sessionControllers.count * 24,
                                                          y: 850 - sessionControllers.count * 24))
            controller.showWindow(nil)
            controller.window?.makeKeyAndOrderFront(nil)
            activateSession(controller)
        }
        return controller
    }

    func activateSession(_ controller: MainWindowController?) {
        activeController = controller
        for item in sessionMenuItems { item.target = controller }
        for session in sessionControllers {
            session.setClipboardActive(session === controller && NSApp.isActive)
        }
    }

    @objc func newSession(_ sender: Any?) { createSession() }

    @objc func showConnections(_ sender: Any?) {
        if connectionsController == nil {
            let controller = ConnectionsWindowController()
            controller.onOpen = { [weak self] profile in self?.createSession(profile: profile) }
            controller.sessionStatus = { [weak self] id in
                let sessions = self?.sessionControllers.filter { $0.runningProfileID == id } ?? []
                let connected = sessions.filter { $0.isConnected }.count
                return sessions.isEmpty ? "—" : "Подключено: \(connected), всего: \(sessions.count)"
            }
            controller.onNew = { [weak self] in self?.createSession() }
            controller.onActivate = { [weak self] in self?.activateSession(nil) }
            connectionsController = controller
        }
        connectionsController?.reload()
        connectionsController?.showWindow(nil)
        connectionsController?.window?.makeKeyAndOrderFront(nil)
        activateSession(nil)
    }

    func applicationDidResignActive(_ notification: Notification) {
        for controller in sessionControllers { controller.setClipboardActive(false) }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        if let key = NSApp.keyWindow?.windowController as? MainWindowController {
            activateSession(key)
            return
        }
        // Log/diagnostics panels belong to the active session. The connection
        // manager, however, explicitly pauses clipboard synchronization.
        if connectionsController?.window?.isKeyWindow == true {
            activateSession(nil)
            return
        }
        if let active = activeController, active.window?.isVisible == true {
            activateSession(active)
            return
        }
        activateSession(sessionControllers.first { $0.window?.isMainWindow == true })
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showConnections(nil) }
        return true
    }

    func prepareAllSessionsForTermination(_ completion: @escaping () -> Void) {
        let controllers = sessionControllers
        guard !controllers.isEmpty else { completion(); return }
        var remaining = controllers.count
        for controller in controllers {
            controller.prepareForTermination {
                remaining -= 1
                if remaining == 0 { completion() }
            }
        }
    }
    private var terminationReplied = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.mainMenu = buildMenu()
        showConnections(nil)
        NSApp.activate(ignoringOtherApps: true)
        LogStore.shared.append("Интерфейс запущен. Сессий: 0", level: 0)

        // Diagnostic launch options open real windows; they never fabricate a
        // session or connect anywhere.
        if CommandLine.arguments.contains("--diagnostics") {
            showLog(nil)
        }
        if CommandLine.arguments.contains("--log") {
            showLog(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        var synchronous = true
        var completed = false
        terminationReplied = false

        prepareAllSessionsForTermination { [weak self] in
            completed = true
            guard let self else { return }
            if synchronous {
                return
            }
            guard !self.terminationReplied else { return }
            self.terminationReplied = true
            NSApp.reply(toApplicationShouldTerminate: true)
        }

        synchronous = false
        if completed {
            terminationReplied = true
            return .terminateNow
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        LogStore.shared.append("Приложение завершено", level: 0)
    }

    // MARK: - Menu

    private func menuItem(_ title: String,
                          action: Selector?,
                          key: String = "",
                          modifiers: NSEvent.ModifierFlags = .command,
                          target: AnyObject?,
                          sessionScoped: Bool = false) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = target
        if sessionScoped { sessionMenuItems.append(item) }
        return item
    }

    func buildMenu() -> NSMenu {
        let main = NSMenu()
        let controller = commandTarget ?? sessionControllers.first

        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(menuItem("О программе RDP Mac",
                                 action: #selector(showAbout(_:)),
                                 target: self))
        appMenu.addItem(menuItem("Что поддерживается",
                                 action: #selector(showHelp(_:)),
                                 key: "?",
                                 target: self))
        appMenu.addItem(.separator())
        appMenu.addItem(menuItem("Скрыть RDP Mac",
                                 action: #selector(NSApplication.hide(_:)),
                                 key: "h",
                                 target: NSApp))
        appMenu.addItem(menuItem("Скрыть остальные",
                                 action: #selector(NSApplication.hideOtherApplications(_:)),
                                 key: "h",
                                 modifiers: [.command, .option],
                                 target: NSApp))
        appMenu.addItem(menuItem("Показать все",
                                 action: #selector(NSApplication.unhideAllApplications(_:)),
                                 target: NSApp))
        appMenu.addItem(.separator())
        appMenu.addItem(menuItem("Завершить RDP Mac",
                                 action: #selector(NSApplication.terminate(_:)),
                                 key: "q",
                                 target: NSApp))
        appItem.submenu = appMenu

        let fileItem = NSMenuItem()
        main.addItem(fileItem)
        let fileMenu = NSMenu(title: "Файл")
        fileMenu.addItem(menuItem("Новая сессия", action: #selector(newSession(_:)),
                                  key: "n", target: self))
        fileMenu.addItem(menuItem("Подключения…", action: #selector(showConnections(_:)),
                                  key: "0", target: self))
        fileMenu.addItem(.separator())
        fileMenu.addItem(menuItem("Параметры подключения",
                                  action: #selector(MainWindowController.showSettings(_:)),
                                  key: ",",
                                  target: controller,
                                  sessionScoped: true))
        fileMenu.addItem(.separator())
        fileMenu.addItem(menuItem("Экспорт журнала…",
                                  action: #selector(exportLog(_:)),
                                  key: "e",
                                  modifiers: [.command, .shift],
                                  target: self))
        fileMenu.addItem(.separator())
        fileMenu.addItem(menuItem("Закрыть окно",
                                  action: #selector(NSWindow.performClose(_:)),
                                  key: "w",
                                  target: nil))
        fileItem.submenu = fileMenu

        let editItem = NSMenuItem()
        main.addItem(editItem)
        let editMenu = NSMenu(title: "Правка")
        editMenu.addItem(menuItem("Отменить", action: NSSelectorFromString("undo:"), key: "z",
                                  target: nil))
        editMenu.addItem(menuItem("Повторить", action: NSSelectorFromString("redo:"), key: "z",
                                  modifiers: [.command, .shift], target: nil))
        editMenu.addItem(.separator())
        editMenu.addItem(menuItem("Вырезать", action: NSSelectorFromString("cut:"), key: "x",
                                  target: nil))
        editMenu.addItem(menuItem("Копировать", action: NSSelectorFromString("copy:"), key: "c",
                                  target: nil))
        editMenu.addItem(menuItem("Вставить", action: NSSelectorFromString("paste:"), key: "v",
                                  target: nil))
        editMenu.addItem(menuItem("Выбрать всё", action: NSSelectorFromString("selectAll:"),
                                  key: "a", target: nil))
        editItem.submenu = editMenu

        let sessionItem = NSMenuItem()
        main.addItem(sessionItem)
        let sessionMenu = NSMenu(title: "Сеанс")
        sessionMenu.addItem(menuItem("Отключиться",
                                     action: #selector(MainWindowController.disconnect(_:)),
                                     key: "d",
                                     target: controller,
                                     sessionScoped: true))
        sessionMenu.addItem(menuItem("Отправить Ctrl+Alt+Delete",
                                     action: #selector(MainWindowController.sendCtrlAltDelete(_:)),
                                     key: String(UnicodeScalar(NSDeleteCharacter)!),
                                     modifiers: [.command, .shift],
                                     target: controller,
                                     sessionScoped: true))
        sessionMenu.addItem(.separator())
        sessionMenu.addItem(menuItem("Полноэкранный режим",
                                     action: #selector(MainWindowController
                                         .toggleFullScreenAction(_:)),
                                     key: "f",
                                     modifiers: [.command, .control],
                                     target: controller,
                                     sessionScoped: true))
        sessionItem.submenu = sessionMenu

        let clipboardItem = NSMenuItem()
        main.addItem(clipboardItem)
        let clipboardMenu = NSMenu(title: "Буфер обмена")
        clipboardMenu.addItem(menuItem("Отправить Mac → Windows",
                                       action: #selector(MainWindowController
                                           .clipboardSendLocal(_:)),
                                       key: "c",
                                       modifiers: [.command, .shift],
                                       target: controller,
                                       sessionScoped: true))
        clipboardMenu.addItem(menuItem("Запросить Windows → Mac",
                                       action: #selector(MainWindowController
                                           .clipboardRequestRemote(_:)),
                                       key: "v",
                                       modifiers: [.command, .shift],
                                       target: controller,
                                       sessionScoped: true))
        clipboardMenu.addItem(menuItem("Полная ресинхронизация",
                                       action: #selector(MainWindowController
                                           .clipboardResync(_:)),
                                       key: "v",
                                       modifiers: [.command, .option, .shift],
                                       target: controller,
                                       sessionScoped: true))
        clipboardMenu.addItem(.separator())
        clipboardMenu.addItem(menuItem("Диагностика буфера обмена",
                                       action: #selector(MainWindowController
                                           .showDiagnostics(_:)),
                                       key: "b",
                                       modifiers: [.command, .shift],
                                       target: controller,
                                       sessionScoped: true))
        clipboardItem.submenu = clipboardMenu

        let diagnosticsItem = NSMenuItem()
        main.addItem(diagnosticsItem)
        let diagnosticsMenu = NSMenu(title: "Диагностика")
        diagnosticsMenu.addItem(menuItem("Показать журнал",
                                         action: #selector(showLog(_:)),
                                         key: "l",
                                         modifiers: [.command, .shift],
                                         target: self))
        diagnosticsMenu.addItem(menuItem("Экспорт журнала…",
                                         action: #selector(exportLog(_:)),
                                         key: "e",
                                         modifiers: [.command, .option],
                                         target: self))
        diagnosticsItem.submenu = diagnosticsMenu

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Окно")
        windowMenu.addItem(menuItem("Свернуть", action: #selector(NSWindow.performMiniaturize(_:)),
                                    key: "m", target: nil))
        windowMenu.addItem(menuItem("Все окна на передний план",
                                    action: #selector(NSApplication.arrangeInFront(_:)), target: NSApp))
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApp.windowsMenu = windowMenu

        let helpItem = NSMenuItem()
        main.addItem(helpItem)
        let helpMenu = NSMenu(title: "Справка")
        helpMenu.addItem(menuItem("Что поддерживается",
                                  action: #selector(showHelp(_:)),
                                  key: "/",
                                  modifiers: [.command, .shift],
                                  target: self))
        helpMenu.addItem(menuItem("FreeRDP — официальный сайт",
                                  action: #selector(openFreeRDP),
                                  target: self))
        helpItem.submenu = helpMenu

        return main
    }

    @objc func showAbout(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc func showHelp(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "RDP Mac: что уже работает"
        alert.informativeText = HelpText.supported
        alert.addButton(withTitle: "Понятно")
        alert.runModal()
    }

    /// Opens the active session's log when one is selected; otherwise the
    /// shared application log remains available from the connection manager.
    @objc func showLog(_ sender: Any?) {
        if let controller = commandTarget {
            controller.showLog(sender)
            return
        }
        if globalLogController == nil {
            globalLogController = LogWindowController()
        }
        globalLogController?.refresh()
        globalLogController?.showWindow(nil)
        globalLogController?.window?.makeKeyAndOrderFront(nil)
    }

    @objc func exportLog(_ sender: Any?) {
        if let controller = commandTarget {
            controller.exportLog(sender)
            return
        }
        let panel = NSSavePanel()
        panel.title = "Экспорт журнала RDP Mac"
        panel.nameFieldStringValue = "rdp-mac-log.txt"
        panel.allowedContentTypes = [.plainText]
        if let window = NSApp.keyWindow {
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
        } else if panel.runModal() == .OK, let url = panel.url {
            do {
                try LogStore.shared.export(to: url)
                LogStore.shared.append("Журнал экспортирован: \(url.lastPathComponent)", level: 0)
            } catch {
                LogStore.shared.append("Не удалось экспортировать журнал: "
                                       + error.localizedDescription, level: 2)
            }
        }
    }

    @objc private func openFreeRDP() {
        if let url = URL(string: "https://www.freerdp.com/") {
            NSWorkspace.shared.open(url)
        }
    }
}
