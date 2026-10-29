import Foundation
import AppKit
import Security

enum ConnectionSecurity: Int, Codable, CaseIterable {
    case negotiate = 0
    case tls = 1
    case legacyRDP = 2

    var title: String {
        switch self {
        case .negotiate:
            return L("NLA / TLS — рекомендуется")
        case .tls:
            return L("Только TLS (без NLA)")
        case .legacyRDP:
            return L("RDP security (небезопасно, старые серверы)")
        }
    }

    var bridgeValue: RDPMacSecurityMode {
        switch self {
        case .negotiate:
            return .negotiate
        case .tls:
            return .TLS
        case .legacyRDP:
            return .legacyRDP
        }
    }
}

enum ResolutionMode: Int, Codable, CaseIterable {
    case window = 0
    case hd = 1
    case fullHD = 2
    case wqxga = 3

    var title: String {
        switch self {
        case .window:
            return L("Как в окне (Retina)")
        case .hd:
            return "1280 × 720"
        case .fullHD:
            return "1920 × 1080"
        case .wqxga:
            return "2560 × 1440"
        }
    }

    /// Returns the remote desktop size in pixels for the current window.
    func size(for contentSize: NSSize, backingScale: CGFloat) -> (width: Int, height: Int) {
        let scale = max(1.0, backingScale)
        switch self {
        case .window:
            let width = Int((contentSize.width * scale).rounded(.down))
            let height = Int((contentSize.height * scale).rounded(.down))
            return (clampDimension(width, min: 800, max: 2560),
                    clampDimension(height, min: 600, max: 1600))
        case .hd:
            return (1280, 720)
        case .fullHD:
            return (1920, 1080)
        case .wqxga:
            return (2560, 1440)
        }
    }

    private func clampDimension(_ value: Int, min lower: Int, max upper: Int) -> Int {
        let even = value & ~1
        return max(lower, min(even, upper))
    }
}

struct Profile: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String = ""
    var host: String = ""
    var port: Int = 3389
    var username: String = ""
    var domain: String = ""
    var security: ConnectionSecurity = .negotiate
    var savePassword: Bool = false
    var clipboardEnabled: Bool = true
    var commandAsControl: Bool = true
    var autoResize: Bool = true
    var resolution: ResolutionMode = .window
    /// Optional keeps old profiles.json files (without this key) decodable.
    var legacyTLS: Bool? = nil
    var group: String? = nil

    var groupName: String {
        let value = group?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? L("Без группы") : value
    }

    var displayName: String {
        if !name.isEmpty { return name }
        if host.isEmpty { return L("Новый профиль") }
        return username.isEmpty ? host : "\(username)@\(host)"
    }

    var keychainAccount: String {
        KeychainStore.account(host: host, port: port, domain: domain, username: username)
    }
}

final class ProfileStore {
    static let shared = ProfileStore()
    static let didChange = Notification.Name("RDPMacProfilesDidChange")
    private(set) var profiles: [Profile] = []
    private let fileURL: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                              in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let directory = support.appendingPathComponent("RDPMac", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("profiles.json")
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            profiles = try JSONDecoder().decode([Profile].self, from: data)
        } catch {
            LogStore.shared.append(L("Не удалось прочитать профили: %@", String(describing: error.localizedDescription)), level: 2)
            profiles = []
        }
    }

    func upsert(_ profile: Profile) {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        persist()
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }

    func delete(id: UUID) {
        profiles.removeAll { $0.id == id }
        persist()
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }

    private func persist() {
        do {
            let data = try JSONEncoder.pretty.encode(profiles)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            LogStore.shared.append(L("Не удалось сохранить профили: %@", String(describing: error.localizedDescription)), level: 2)
        }
    }

    func password(for profile: Profile) -> String? {
        KeychainStore.password(account: profile.keychainAccount)
    }

    func forgetPassword(for profile: Profile) {
        KeychainStore.delete(account: profile.keychainAccount)
    }
}

extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

enum KeychainStore {
    static let service: String = Bundle.main.bundleIdentifier ?? "com.rdpmac.client"

    static func account(host: String, port: Int, domain: String, username: String) -> String {
        "\(host.lowercased()):\(port)/\(domain)\\\(username)"
    }

    static func password(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let password = String(data: data, encoding: .utf8) else {
            if status != errSecItemNotFound {
                LogStore.shared.append(L("Keychain: не удалось прочитать пароль (код %@)", String(describing: status)), level: 1)
            }
            return nil
        }
        return password
    }

    @discardableResult
    static func save(password: String, account: String) -> Bool {
        guard let data = password.data(using: .utf8) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add.merge(attributes) { _, new in new }
            status = SecItemAdd(add as CFDictionary, nil)
        }
        if status != errSecSuccess {
            LogStore.shared.append(L("Keychain: не удалось сохранить пароль (код %@)", String(describing: status)), level: 1)
            return false
        }
        return true
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            LogStore.shared.append(L("Keychain: не удалось удалить пароль (код %@)", String(describing: status)), level: 1)
        }
    }
}
