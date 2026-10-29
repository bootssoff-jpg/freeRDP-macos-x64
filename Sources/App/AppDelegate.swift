import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainController: MainWindowController?
    private var terminationReplied = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        mainController = MainWindowController()
        NSApp.mainMenu = buildMenu()
        NSApp.activate(ignoringOtherApps: true)
        LogStore.shared.append("Интерфейс запущен", level: 0)

        // Support/diagnostic launch options; they open the real windows and do
        // not fabricate session data.
        if CommandLine.arguments.contains("--diagnostics") {
            mainController?.showDiagnostics(nil)
        }
        if CommandLine.arguments.contains("--log") {
            mainController?.showLog(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let mainController else { return .terminateNow }
        var synchronous = true
        var completed = false
        terminationReplied = false

        mainController.prepareForTermination { [weak self] in
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
                          target: AnyObject?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = target
        return item
    }

    private func buildMenu() -> NSMenu {
        let main = NSMenu()
        let controller = mainController

        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(menuItem("О программе RDP Mac",
                                 action: #selector(MainWindowController.showAbout(_:)),
                                 target: controller))
        appMenu.addItem(menuItem("Что поддерживается",
                                 action: #selector(MainWindowController.showHelp(_:)),
                                 key: "?",
                                 target: controller))
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
        fileMenu.addItem(menuItem("Параметры подключения",
                                  action: #selector(MainWindowController.showSettings(_:)),
                                  key: ",",
                                  target: controller))
        fileMenu.addItem(.separator())
        fileMenu.addItem(menuItem("Экспорт журнала…",
                                  action: #selector(MainWindowController.exportLog(_:)),
                                  key: "e",
                                  modifiers: [.command, .shift],
                                  target: controller))
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
                                     target: controller))
        sessionMenu.addItem(menuItem("Отправить Ctrl+Alt+Delete",
                                     action: #selector(MainWindowController.sendCtrlAltDelete(_:)),
                                     key: String(UnicodeScalar(NSDeleteCharacter)!),
                                     modifiers: [.command, .shift],
                                     target: controller))
        sessionMenu.addItem(.separator())
        sessionMenu.addItem(menuItem("Полноэкранный режим",
                                     action: #selector(MainWindowController
                                         .toggleFullScreenAction(_:)),
                                     key: "f",
                                     modifiers: [.command, .control],
                                     target: controller))
        sessionItem.submenu = sessionMenu

        let clipboardItem = NSMenuItem()
        main.addItem(clipboardItem)
        let clipboardMenu = NSMenu(title: "Буфер обмена")
        clipboardMenu.addItem(menuItem("Отправить Mac → Windows",
                                       action: #selector(MainWindowController
                                           .clipboardSendLocal(_:)),
                                       key: "c",
                                       modifiers: [.command, .shift],
                                       target: controller))
        clipboardMenu.addItem(menuItem("Запросить Windows → Mac",
                                       action: #selector(MainWindowController
                                           .clipboardRequestRemote(_:)),
                                       key: "v",
                                       modifiers: [.command, .shift],
                                       target: controller))
        clipboardMenu.addItem(menuItem("Полная ресинхронизация",
                                       action: #selector(MainWindowController
                                           .clipboardResync(_:)),
                                       key: "v",
                                       modifiers: [.command, .option, .shift],
                                       target: controller))
        clipboardMenu.addItem(.separator())
        clipboardMenu.addItem(menuItem("Диагностика буфера обмена",
                                       action: #selector(MainWindowController
                                           .showDiagnostics(_:)),
                                       key: "b",
                                       modifiers: [.command, .shift],
                                       target: controller))
        clipboardItem.submenu = clipboardMenu

        let diagnosticsItem = NSMenuItem()
        main.addItem(diagnosticsItem)
        let diagnosticsMenu = NSMenu(title: "Диагностика")
        diagnosticsMenu.addItem(menuItem("Показать журнал",
                                         action: #selector(MainWindowController.showLog(_:)),
                                         key: "l",
                                         modifiers: [.command, .shift],
                                         target: controller))
        diagnosticsMenu.addItem(menuItem("Экспорт журнала…",
                                         action: #selector(MainWindowController.exportLog(_:)),
                                         key: "e",
                                         modifiers: [.command, .option],
                                         target: controller))
        diagnosticsItem.submenu = diagnosticsMenu

        let helpItem = NSMenuItem()
        main.addItem(helpItem)
        let helpMenu = NSMenu(title: "Справка")
        helpMenu.addItem(menuItem("Что поддерживается",
                                  action: #selector(MainWindowController.showHelp(_:)),
                                  key: "/",
                                  modifiers: [.command, .shift],
                                  target: controller))
        helpMenu.addItem(menuItem("FreeRDP — официальный сайт",
                                  action: #selector(openFreeRDP),
                                  target: self))
        helpItem.submenu = helpMenu

        return main
    }

    @objc private func openFreeRDP() {
        if let url = URL(string: "https://www.freerdp.com/") {
            NSWorkspace.shared.open(url)
        }
    }
}
