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

// Remote desktop sizes and their limits live in ResolutionSettings.swift.
struct Profile: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String = ""
    var host: String = ""
    var port: Int = 3389
    var username: String = ""
    var domain: String = ""
    /// Reference to the shared user directory. `nil` keeps the legacy behaviour
    /// where the password (if any) is keyed by host/port/account.
    var credentialID: UUID? = nil
    var security: ConnectionSecurity = .negotiate
    var savePassword: Bool = false
    var clipboardEnabled: Bool = true
    var commandAsControl: Bool = true
    var autoResize: Bool = true
    var resolution: ResolutionPolicy = .default
    var quality: QualityPolicy = .default
    /// Optional keeps old profiles.json files (without this key) decodable.
    var legacyTLS: Bool? = nil
    var group: String? = nil

    var groupName: String {
        let value = group?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? L("Без группы") : value
    }

    init() {}

    init(id: UUID = UUID(), name: String = "", host: String = "", port: Int = 3389,
         username: String = "", domain: String = "", credentialID: UUID? = nil,
         security: ConnectionSecurity = .negotiate, savePassword: Bool = false,
         clipboardEnabled: Bool = true, commandAsControl: Bool = true, autoResize: Bool = true,
         resolution: ResolutionPolicy = .default, quality: QualityPolicy = .default,
         legacyTLS: Bool? = nil, group: String? = nil) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.domain = domain
        self.credentialID = credentialID
        self.security = security
        self.savePassword = savePassword
        self.clipboardEnabled = clipboardEnabled
        self.commandAsControl = commandAsControl
        self.autoResize = autoResize
        self.resolution = resolution
        self.quality = quality
        self.legacyTLS = legacyTLS
        self.group = group
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, host, port, username, domain, credentialID, security, savePassword,
             clipboardEnabled, commandAsControl, autoResize, resolution, quality, legacyTLS, group
    }

    /// Every key is optional on decode so profiles.json files written by older
    /// versions (no `credentialID`, `resolution`, `quality` or `group`) still
    /// load instead of being discarded.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        host = try container.decodeIfPresent(String.self, forKey: .host) ?? ""
        port = try container.decodeIfPresent(Int.self, forKey: .port) ?? 3389
        username = try container.decodeIfPresent(String.self, forKey: .username) ?? ""
        domain = try container.decodeIfPresent(String.self, forKey: .domain) ?? ""
        credentialID = try container.decodeIfPresent(UUID.self, forKey: .credentialID)
        security = try container.decodeIfPresent(ConnectionSecurity.self, forKey: .security)
            ?? .negotiate
        savePassword = try container.decodeIfPresent(Bool.self, forKey: .savePassword) ?? false
        clipboardEnabled =
            try container.decodeIfPresent(Bool.self, forKey: .clipboardEnabled) ?? true
        commandAsControl =
            try container.decodeIfPresent(Bool.self, forKey: .commandAsControl) ?? true
        autoResize = try container.decodeIfPresent(Bool.self, forKey: .autoResize) ?? true
        // A single legacy Int is still accepted for `resolution` by
        // ResolutionPolicy's own decoder.
        resolution = (try? container.decodeIfPresent(ResolutionPolicy.self, forKey: .resolution))
            ?? .default
        quality = (try? container.decodeIfPresent(QualityPolicy.self, forKey: .quality))
            ?? .default
        legacyTLS = try container.decodeIfPresent(Bool.self, forKey: .legacyTLS)
        group = try container.decodeIfPresent(String.self, forKey: .group)
    }

    var displayName: String {
        if !name.isEmpty { return name }
        if host.isEmpty { return L("Новый профиль") }
        return username.isEmpty ? host : "\(username)@\(host)"
    }

    var keychainAccount: String {
        if let credentialID {
            return CredentialStore.keychainAccount(for: credentialID)
        }
        return KeychainStore.account(host: host, port: port, domain: domain, username: username)
    }

    /// Copy for "Duplicate": new identity, same settings and directory record.
    /// Nothing is persisted here and the original profile is not modified.
    func duplicated() -> Profile {
        var copy = self
        copy.id = UUID()
        let base = name.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.name = L("%@ — копия", base.isEmpty ? displayName : base)
        return copy
    }
}

final class ProfileStore {
    static let shared = ProfileStore()
    static let didChange = Notification.Name("RDPMacProfilesDidChange")
    private(set) var profiles: [Profile] = []
    let directory: URL
    private let fileURL: URL

    init(directory: URL? = nil) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                              in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let target = directory ?? support.appendingPathComponent("RDPMac", isDirectory: true)
        try? FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        self.directory = target
        fileURL = target.appendingPathComponent("profiles.json")
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

    func profile(id: UUID) -> Profile? {
        profiles.first { $0.id == id }
    }

    func contains(id: UUID) -> Bool {
        profiles.contains { $0.id == id }
    }

    func profilesUsing(credentialID: UUID) -> [Profile] {
        profiles.filter { $0.credentialID == credentialID }
    }

    /// Detaches every profile that references a removed directory record. The
    /// profiles keep their username/domain and keep working without a saved
    /// password; nothing is deleted.
    func detachProfiles(credentialID: UUID) {
        var changed = false
        for index in profiles.indices where profiles[index].credentialID == credentialID {
            profiles[index].credentialID = nil
            profiles[index].savePassword = false
            changed = true
        }
        guard changed else { return }
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

    /// Deletes a profile's saved password only when it belongs to that profile
    /// alone. Passwords kept in the shared user directory are managed there.
    func forgetPassword(for profile: Profile) {
        guard profile.credentialID == nil else { return }
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

    /// Metadata-only check: does a password exist for this account? No secret
    /// is read, so this is safe for UI state and tests.
    static func hasPassword(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
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
