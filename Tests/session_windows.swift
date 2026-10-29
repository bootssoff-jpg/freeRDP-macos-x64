import AppKit

// No network connections, passwords, profile writes or visible session windows.
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
var failures = 0
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if condition() { print("ok: \(message)") }
    else { fputs("FAIL: \(message)\n", stderr); failures += 1 }
}
func findItem(_ menu: NSMenu, action: Selector) -> NSMenuItem? {
    for item in menu.items {
        if item.action == action { return item }
        if let sub = item.submenu, let found = findItem(sub, action: action) { return found }
    }
    return nil
}
let launchDelegate = AppDelegate()
expect(launchDelegate.sessionControllers.isEmpty, "launch delegate starts without a session window")
let emptyMenu = launchDelegate.buildMenu()
expect(findItem(emptyMenu, action: #selector(AppDelegate.newSession(_:)))?.target === launchDelegate,
       "global New Session works without a session")
expect(findItem(emptyMenu, action: #selector(AppDelegate.showHelp(_:)))?.target === launchDelegate,
       "global help works without a session")
expect(findItem(emptyMenu, action: #selector(MainWindowController.disconnect(_:)))?.target == nil,
       "session commands have no target before a session exists")

let delegate = AppDelegate()
let first = delegate.createSession(showWindow: false)
let second = delegate.createSession(showWindow: false)
expect(delegate.sessionControllers.count == 2, "two independently retained session controllers")
expect(first.window !== second.window, "independent session windows")
let menu = delegate.buildMenu()
let disconnect = findItem(menu, action: #selector(MainWindowController.disconnect(_:)))
delegate.activateSession(first)
expect(disconnect?.target === first, "session menu targets first window")
delegate.activateSession(second)
expect(disconnect?.target === second, "session menu switches to second window")
delegate.activateSession(nil)
expect(disconnect?.target == nil, "no stale session target in connection manager")
expect(findItem(menu, action: #selector(AppDelegate.newSession(_:)))?.keyEquivalent == "n",
       "Cmd+N creates another session")
first.window?.close()
expect(delegate.sessionControllers.count == 1 && delegate.sessionControllers.first === second,
       "closing one window preserves the other controller")
var completions = 0
delegate.prepareAllSessionsForTermination { completions += 1 }
expect(completions == 1, "shutdown completes once for remaining sessions")
second.window?.close()
expect(delegate.sessionControllers.isEmpty, "last session is released")
delegate.prepareAllSessionsForTermination { completions += 1 }
expect(completions == 2, "shutdown with zero sessions completes")
var a = Profile(); a.name = "Server 10"; a.host = "test-a"; a.group = "Work"; a.username = "admin"
var b = Profile(); b.name = "Server 2"; b.host = "test-b"; b.group = "Work"
var c = Profile(); c.name = "Home"; c.host = "home"; c.group = "Home"
let rows = ConnectionsWindowController.groupedRows(profiles: [a,b,c], query: "Work")
expect(rows.count == 3, "group filter includes its header and two profiles")
if rows.count == 3, case .profile(let firstProfile) = rows[1] {
    expect(firstProfile.id == b.id, "profiles use natural name sorting")
} else { expect(false, "profile sorting returned expected rows") }
expect(ConnectionsWindowController.groupedRows(profiles: [a,b,c], query: "ADMIN").count == 2,
       "case-insensitive search includes account names")
let data = try JSONEncoder().encode(a)
var old = try JSONSerialization.jsonObject(with: data) as! [String: Any]
old.removeValue(forKey: "group")
let restored = try JSONDecoder().decode(Profile.self, from: JSONSerialization.data(withJSONObject: old))
expect(restored.groupName == "Без группы", "existing profiles without group still decode")
let accountA = KeychainStore.account(host: "server", port: 3389, domain: "EXAMPLE", username: "alice")
let accountB = KeychainStore.account(host: "server", port: 3389, domain: "EXAMPLE", username: "bob")
expect(accountA != accountB, "different accounts on one server use different Keychain keys")
let encoded = String(data: try JSONEncoder().encode(a), encoding: .utf8) ?? ""
expect(!encoded.contains("\"password\":"), "profile JSON contains no password value field")
print(failures == 0 ? "RESULT: OK" : "RESULT: \(failures) FAILURES")
exit(failures == 0 ? 0 : 1)
