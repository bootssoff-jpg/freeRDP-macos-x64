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

let duplicateItem = findItem(emptyMenu, action: #selector(AppDelegate.duplicateProfile(_:)))
expect(duplicateItem != nil && duplicateItem?.keyEquivalent == "d" &&
       duplicateItem?.keyEquivalentModifierMask == [.command, .shift],
       "duplicate connection uses a free Cmd+Shift+D shortcut")
expect(duplicateItem.map { launchDelegate.validateMenuItem($0) } == false,
       "duplicate connection is disabled without a selected profile")

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
expect(restored.groupName == L("Без группы"), "existing profiles without group still decode")
let accountA = KeychainStore.account(host: "server", port: 3389, domain: "EXAMPLE", username: "alice")
let accountB = KeychainStore.account(host: "server", port: 3389, domain: "EXAMPLE", username: "bob")
expect(accountA != accountB, "different accounts on one server use different Keychain keys")
let encoded = String(data: try JSONEncoder().encode(a), encoding: .utf8) ?? ""
expect(!encoded.contains("\"password\":"), "profile JSON contains no password value field")
let collapsed = ConnectionsWindowController.groupedRows(profiles: [a,b,c], query: "", collapsedGroups: ["Work"])
expect(collapsed.count == 3, "collapsed group keeps its header and hides its profiles")
expect(ConnectionsWindowController.groupedRows(profiles: [a,b,c], query: "Work", collapsedGroups: ["Work"]).count == 3,
       "search expands matching profiles even when their group is collapsed")
let language = ProcessInfo.processInfo.environment["RDPMAC_LANGUAGE"] ?? "ru"
expect(L("Подключиться") == (language == "en" ? "Connect" : "Подключиться"), "selected UI language loads from bundled resources")
expect(L("Активных: %@", "2") == (language == "en" ? "Active: 2" : "Активных: 2"), "localized dynamic status preserves its argument")
expect(RDPMacLocalizedString("Неверное имя пользователя или пароль.") ==
       (language == "en" ? "Incorrect user name or password." : "Неверное имя пользователя или пароль."),
       "Objective-C errors use the same language as Swift")
expect(RDPMacLocalizedString("missing-localization-key") == "missing-localization-key", "missing key falls back safely")
let form = ConnectFormView()
var safeProfile = Profile(); safeProfile.host = "demo.invalid"; safeProfile.username = "demo"
form.applyProfile(safeProfile, password: nil)
expect(form.makeProfile(name: "Demo").host == "demo.invalid", "localized form preserves profile values")
let manager = ConnectionsWindowController()
manager.profilesProvider = { [a,b,c] }
manager.reload()
expect(manager.rows.count == 5, "manager renders shared demo profiles without persistence")
manager.window?.close()

// MARK: - Duplicate profiles and the account directory

let scratch = FileManager.default.temporaryDirectory
    .appendingPathComponent("rdpmac-tests-\(UUID().uuidString)", isDirectory: true)
try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: scratch) }

var original = Profile(); original.name = "Office"; original.host = "demo.invalid"
original.username = "demo"; original.domain = "EXAMPLE"; original.group = "Work"
let copy = original.duplicated()
expect(copy.id != original.id, "duplicate gets a new identity")
expect(copy.name != original.name && copy.name.hasPrefix("Office"),
       "duplicate is named after the original with a copy suffix")
expect(copy.host == original.host && copy.username == original.username &&
       copy.domain == original.domain && copy.group == original.group,
       "duplicate keeps every connection setting and the group")
expect(original.host == "demo.invalid" && original.name == "Office",
       "duplicating never modifies the original profile")

let draftStore = ProfileStore(directory: scratch)
draftStore.upsert(original)
expect(draftStore.profiles.count == 1, "saved profile is persisted in the scratch store")
expect(!draftStore.contains(id: copy.id), "an unsaved duplicate is not in the store")
expect(draftStore.profile(id: original.id)?.host == "demo.invalid",
       "the original profile stays unchanged after duplicating")

let credential = Credential(title: "Demo account", username: "demo", domain: "EXAMPLE")
let memorySecrets = MemorySecretStore()
let directory = CredentialStore(directory: scratch, secrets: memorySecrets)
directory.upsert(credential)
expect(directory.password(for: credential) == nil, "a new account has no saved password")
expect(directory.savePassword("s3cret-value", for: credential), "password can be stored for an account")
expect(directory.hasPassword(credential), "stored password is reported as present")
expect(directory.password(for: credential) == "s3cret-value", "stored password reads back in memory")

let credentialCopy = directory.duplicate(credential)
expect(credentialCopy.id != credential.id, "copied account gets a new identity")
expect(directory.password(for: credentialCopy) == "s3cret-value",
       "copied account receives its own copy of the secret")
expect(CredentialStore.keychainAccount(for: credential.id) !=
       CredentialStore.keychainAccount(for: credentialCopy.id),
       "each account uses a distinct Keychain item")

var sharedProfile = original
sharedProfile.credentialID = credential.id
sharedProfile.savePassword = true
draftStore.upsert(sharedProfile)
var secondProfile = original
secondProfile.id = UUID()
secondProfile.credentialID = credential.id
draftStore.upsert(secondProfile)
expect(directory.profilesUsing(credential.id, in: draftStore).count == 2,
       "one account is shared by several profiles")
draftStore.detachProfiles(credentialID: credential.id)
expect(directory.profilesUsing(credential.id, in: draftStore).isEmpty,
       "deleting an account detaches its profiles")
expect(draftStore.profiles.count == 2 && draftStore.profiles.allSatisfy { $0.credentialID == nil },
       "detached profiles are kept without a directory reference")

let encodedCredentials = String(data: try JSONEncoder().encode([credential]),
                                encoding: .utf8) ?? ""
expect(!encodedCredentials.lowercased().contains("password"),
       "credentials JSON contains no password field")
expect(!encodedCredentials.contains("s3cret-value"), "credentials JSON never contains the secret")

// MARK: - Migration of host-keyed Keychain entries

let legacyDir = scratch.appendingPathComponent("migration", isDirectory: true)
let legacyProfiles = ProfileStore(directory: legacyDir)
let legacySecrets = MemorySecretStore()
var legacyProfile = Profile(); legacyProfile.name = "Legacy"; legacyProfile.host = "legacy.invalid"
legacyProfile.username = "alice"; legacyProfile.domain = "EXAMPLE"
legacyProfile.savePassword = true
legacyProfiles.upsert(legacyProfile)
let legacyAccount = KeychainStore.account(host: legacyProfile.host, port: legacyProfile.port,
                                          domain: legacyProfile.domain,
                                          username: legacyProfile.username)
legacySecrets.save(password: "legacy-secret", account: legacyAccount)
let legacyDirectory = CredentialStore(directory: legacyDir, secrets: legacySecrets)

expect(legacyDirectory.migrateLegacyPasswords(profiles: legacyProfiles) == 1,
       "legacy password is migrated into the account directory")
let migratedProfile = legacyProfiles.profile(id: legacyProfile.id)
expect(migratedProfile?.credentialID != nil, "migrated profile references a directory record")
if let migratedID = migratedProfile?.credentialID,
   let migratedCredential = legacyDirectory.credential(id: migratedID) {
    expect(legacyDirectory.password(for: migratedCredential) == "legacy-secret",
           "migrated account holds the original secret")
    expect(migratedCredential.legacyAccount == nil, "migration marker is cleared after linking")
} else {
    expect(false, "migrated account exists")
}
expect(legacySecrets.password(account: legacyAccount) == "legacy-secret",
       "the legacy Keychain item is never deleted by migration")
expect(legacyDirectory.migrateLegacyPasswords(profiles: legacyProfiles) == 0,
       "running migration again changes nothing")
expect(legacyDirectory.credentials.count == 1, "repeated migration creates no duplicates")

let reloadedDirectory = CredentialStore(directory: legacyDir, secrets: legacySecrets)
expect(reloadedDirectory.credentials.count == 1, "directory survives a restart without duplicates")
let reloadedProfiles = ProfileStore(directory: legacyDir)
expect(reloadedProfiles.profile(id: legacyProfile.id)?.credentialID == migratedProfile?.credentialID,
       "profile keeps its directory reference after a restart")

// A second profile with the same login must not be merged into one record.
var sibling = legacyProfile
sibling.id = UUID()
sibling.host = "other.invalid"
sibling.credentialID = nil
legacyProfiles.upsert(sibling)
let siblingAccount = KeychainStore.account(host: sibling.host, port: sibling.port,
                                           domain: sibling.domain, username: sibling.username)
legacySecrets.save(password: "other-secret", account: siblingAccount)
_ = legacyDirectory.migrateLegacyPasswords(profiles: legacyProfiles)
expect(legacyDirectory.credentials.count == 2, "equal logins on different servers stay separate records")

// MARK: - Resolution presets

let legacyFixed = try JSONDecoder().decode(ResolutionPolicy.self, from: Data("2".utf8))
expect(legacyFixed.preset == .r1920x1080 && !legacyFixed.retina,
       "legacy resolution 2 maps to 1920 × 1080 without Retina")
let legacyWindow = try JSONDecoder().decode(ResolutionPolicy.self, from: Data("0".utf8))
expect(legacyWindow.preset == .window, "legacy resolution 0 keeps following the window")
let legacyProfileJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(a)) as! [String: Any]
var upgradedLegacyJSON = legacyProfileJSON
upgradedLegacyJSON["resolution"] = 3
let upgradedLegacy = try JSONDecoder().decode(Profile.self,
    from: JSONSerialization.data(withJSONObject: upgradedLegacyJSON))
expect(upgradedLegacy.resolution.preset == .r2560x1440 && !upgradedLegacy.resolution.retina,
       "a 1.0.x profile keeps its fixed size after upgrade")
let customResolution = ResolutionPolicy(preset: .custom, customWidth: 1440, customHeight: 900,
                                        retina: false)
let restoredResolution = try JSONDecoder().decode(ResolutionPolicy.self,
                                                  from: JSONEncoder().encode(customResolution))
expect(restoredResolution == customResolution, "custom resolution survives a JSON round trip")
let fullHDResolution = ResolutionPolicy(preset: .r1920x1080, retina: true)
expect(fullHDResolution.size(forWindow: NSSize(width: 4000, height: 3000), backingScale: 2)
        == (1920, 1080),
       "a fixed preset ignores window size and backing scale")
expect(fullHDResolution.allowsAutoResize == false && fullHDResolution.desktopScaleFactor == 200,
       "Retina on a fixed preset only requests Windows 200 % scaling")
let windowResolution = ResolutionPolicy(preset: .window, retina: true)
let clampedWindow = windowResolution.size(forWindow: NSSize(width: 5000, height: 4000),
                                          backingScale: 2)
expect(clampedWindow == (4096, 2560), "window mode clamps to the 4096 × 2560 memory limit")
expect(clampedWindow.width % 2 == 0 && clampedWindow.height % 2 == 0,
       "window mode sends even dimensions")
expect(ResolutionPolicy(preset: .window, retina: false)
        .size(forWindow: NSSize(width: 1280, height: 800), backingScale: 2) == (1280, 800),
       "Retina off uses logical points")
expect(ResolutionPolicy(preset: .window, retina: true)
        .size(forWindow: NSSize(width: 1280, height: 800), backingScale: 2) == (2560, 1600),
       "Retina on doubles the remote size on a 2× display")
let oddCustom = ResolutionPolicy(preset: .custom, customWidth: 1441, customHeight: 901)
expect(oddCustom.size(forWindow: .zero, backingScale: 1) == (1440, 900),
       "odd custom sizes are rounded down to even values")
expect(oddCustom.customSizeWarning == nil, "an in-range custom size has no warning")
let bigCustom = ResolutionPolicy(preset: .custom, customWidth: 5000, customHeight: 3000)
expect(bigCustom.size(forWindow: .zero, backingScale: 1) == (4096, 2560),
       "oversized custom sizes are clamped")
expect(bigCustom.customSizeWarning != nil, "oversized custom sizes are reported to the user")
let smallCustom = ResolutionPolicy(preset: .custom, customWidth: 320, customHeight: 200)
expect(smallCustom.customSizeWarning != nil, "undersized custom sizes are reported")
expect(ResolutionPolicy(preset: .custom, customWidth: 640, customHeight: 480).customSizeWarning == nil,
       "the minimum custom size is accepted")

// MARK: - Quality policy

let normalQuality = QualityPolicy()
var normalOptions = RDPMacSessionOptions.defaultOptions(withWidth: 1920, height: 1080)
normalQuality.apply(to: normalOptions)
expect(normalOptions.colorDepth == 32 && normalOptions.compressionLevel == 3
        && !normalOptions.disableWallpaper && !normalOptions.disableThemes,
       "normal quality keeps wallpaper, themes and 32-bit colour")
var slowQuality = QualityPolicy()
slowQuality.preset = .slow
var slowOptions = RDPMacSessionOptions.defaultOptions(withWidth: 1280, height: 720)
slowOptions.desktopScaleFactor = 200
slowQuality.apply(to: slowOptions)
expect(slowOptions.disableWallpaper && slowOptions.disableThemes
        && !slowOptions.allowFontSmoothing && !slowOptions.allowDesktopComposition,
       "slow preset disables wallpaper, themes, font smoothing and composition")
expect(slowOptions.desktopScaleFactor == 200 && slowOptions.colorDepth == 32,
       "the slow preset does not silently change resolution or colour depth")
expect(slowQuality.effectiveResizeThrottle > normalQuality.effectiveResizeThrottle,
       "slow preset sends fewer DisplayControl resizes")
expect(QualityPolicy.slowStartResolution.preset == .r1280x720
        && !QualityPolicy.slowStartResolution.retina,
       "slow preset starts from 1280 × 720 without Retina")
var customQuality = QualityPolicy()
customQuality.preset = .custom
customQuality.colorDepth = 16
customQuality.compressionLevel = 1
customQuality.disableWallpaper = true
var customOptions = RDPMacSessionOptions.defaultOptions(withWidth: 800, height: 600)
customQuality.apply(to: customOptions)
expect(customOptions.colorDepth == 16 && customOptions.compressionLevel == 1
        && customOptions.disableWallpaper,
       "custom quality maps 16-bit colour, 64K compression and wallpaper")
var noQualityJSON = legacyProfileJSON
noQualityJSON.removeValue(forKey: "quality")
let oldQualityProfile = try JSONDecoder().decode(Profile.self,
    from: JSONSerialization.data(withJSONObject: noQualityJSON))
expect(oldQualityProfile.quality.preset == .normal, "profiles without a quality key default to normal")
let slowReport = RDPMacClient.optionsReport(slowOptions)
expect((slowReport["colorDepth"] as? NSNumber)?.uintValue == 32,
       "options report exposes the requested colour depth")
expect((slowReport["compressionLevel"] as? NSNumber)?.uintValue == 3,
       "options report exposes the compression level")
expect((slowReport["desktopScaleFactor"] as? NSNumber)?.uintValue == 200
        && (slowReport["deviceScaleFactor"] as? NSNumber)?.uintValue == 200,
       "options report sends the DPI scale factors")
expect((slowReport["performanceFlags"] as? NSNumber)?.uint32Value ?? 0 != 0,
       "slow preset produces non-zero Client Info performance flags")
expect((slowReport["autoAcceptCertificate"] as? NSNumber)?.boolValue == false,
       "session options never accept certificates automatically")
expect((slowReport["networkAutoDetect"] as? NSNumber)?.boolValue == false,
       "options report keeps NetworkAutoDetect disabled")

// MARK: - Session toolbar

let toolbarView = SessionView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
expect(toolbarView.isToolbarVisible
        && toolbarView.desktopAreaHeight == SessionView.toolbarHeightValue,
       "the session toolbar is visible by default")
toolbarView.setToolbarVisible(false)
expect(!toolbarView.isToolbarVisible && toolbarView.desktopAreaHeight == 0,
       "hiding the toolbar releases the whole 44 pt row")
toolbarView.setFullScreen(true)
toolbarView.setToolbarVisible(true)
expect(!toolbarView.isToolbarVisible, "full screen hides the toolbar even when it is enabled")
toolbarView.setFullScreen(false)
expect(toolbarView.isToolbarVisible, "leaving full screen restores the enabled toolbar")
UserDefaults.standard.removeObject(forKey: MainWindowController.toolbarPreferenceKey)
let toolbarSession = delegate.createSession(showWindow: false)
toolbarSession.toggleSessionToolbar(nil)
expect(UserDefaults.standard.object(forKey: MainWindowController.toolbarPreferenceKey) as? Bool
        == false, "hiding the toolbar is remembered for new windows")
toolbarSession.toggleSessionToolbar(nil)
expect(UserDefaults.standard.object(forKey: MainWindowController.toolbarPreferenceKey) as? Bool
        == true, "showing the toolbar is remembered too")
let toolbarItem = findItem(menu, action: #selector(MainWindowController.toggleSessionToolbar(_:)))
expect(toolbarItem?.keyEquivalent == "t"
        && toolbarItem?.keyEquivalentModifierMask == [.command, .shift],
       "show/hide session toolbar uses Cmd+Shift+T")
_ = toolbarSession.validateMenuItem(toolbarItem!)
expect(toolbarItem?.state == .on, "the menu check mark follows the current toolbar state")
UserDefaults.standard.removeObject(forKey: MainWindowController.toolbarPreferenceKey)
toolbarSession.window?.close()

// MARK: - Duplicate selection rules

let duplicateRows = ConnectionsWindowController.groupedRows(profiles: [a, b], query: "")
expect(ConnectionsWindowController.canDuplicate(rows: duplicateRows, selection: IndexSet(integer: 0)) == false,
       "a group header cannot be duplicated")
if let profileRow = duplicateRows.firstIndex(where: {
    if case .profile = $0 { return true }
    return false
}) {
    expect(ConnectionsWindowController.canDuplicate(rows: duplicateRows,
                                                    selection: IndexSet(integer: profileRow)),
           "a single selected profile can be duplicated")
    expect(!ConnectionsWindowController.canDuplicate(rows: duplicateRows,
                                                     selection: IndexSet([0, profileRow])),
           "duplicate requires exactly one selected profile")
} else {
    expect(false, "profile row found for duplicate selection test")
}
let resourceRoot = Bundle.main.resourceURL!
func stringsTable(_ language: String) throws -> [String: String] {
    let data = try Data(contentsOf: resourceRoot.appendingPathComponent("\(language).lproj/Localizable.strings"))
    return try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: String]
}
let english = try stringsTable("en")
let russian = try stringsTable("ru")
expect(Set(english.keys) == Set(russian.keys), "EN/RU contain exactly the same localization keys")
let formatPattern = try NSRegularExpression(pattern: "%([0-9]+\\$)?[0-9.]*[a-zA-Z@]+")
func formatTokens(_ value: String) -> [String] {
    let range = NSRange(value.startIndex..., in: value)
    return formatPattern.matches(in: value, range: range).map { (value as NSString).substring(with: $0.range) }
}
expect(english.allSatisfy { formatTokens($0.key) == formatTokens($0.value) },
       "all English format strings preserve their argument types and order")
let repositoryItem = findItem(emptyMenu, action: #selector(AppDelegate.openProjectRepository(_:)))
expect(repositoryItem?.target === launchDelegate, "project GitHub link is available without a session")
expect(AppAbout.repositoryURL.absoluteString == "https://github.com/bootssoff-jpg/freeRDP-macos-x64",
       "Help and About link to the application repository")
let credits = AppAbout.options[.credits] as? NSAttributedString
expect(credits?.string.contains("NFreeZr") == true, "About panel explicitly credits NFreeZr")
if let credits {
    let links = (0..<credits.length).compactMap { credits.attribute(.link, at: $0, effectiveRange: nil) as? URL }
    expect(links.contains(AppAbout.repositoryURL), "About repository credit is a clickable link")
}
expect((AppAbout.options[NSApplication.AboutPanelOptionKey(rawValue: "Copyright")] as? String)?.contains("NFreeZr") == true,
       "About copyright is independent of stale bundle metadata")
print(failures == 0 ? "RESULT: OK" : "RESULT: \(failures) FAILURES")
exit(failures == 0 ? 0 : 1)
