import Foundation

/// Strings are resolved once per process. Changing the preference never
/// interrupts a session or changes the keyboard layout sent to Windows.
enum AppLanguage {
    static var preference: String { UserDefaults.standard.string(forKey: "RDPMacLanguage") ?? "system" }
}

func L(_ key: String, _ arguments: CVarArg...) -> String {
    let value = RDPMacLocalizedString(key)
    return arguments.isEmpty ? value : String(format: value, locale: Locale.current, arguments: arguments)
}
