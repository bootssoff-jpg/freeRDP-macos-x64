import Foundation

/// A saved account (user directory entry). Passwords are never stored in this
/// type or in `credentials.json`; they live in the Keychain under
/// `credential/<uuid>`, so the key does not depend on a server address.
struct Credential: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var title: String = ""
    var username: String = ""
    var domain: String = ""
    /// Keychain account this record was migrated from (host-derived). It is
    /// metadata only, never a secret, and is cleared once every profile that
    /// used it is linked. Kept so an interrupted migration can be resumed.
    var legacyAccount: String? = nil
    var createdAt: Date = Date()

    var keychainAccount: String { CredentialStore.keychainAccount(for: id) }

    var accountName: String {
        let trimmedDomain = domain.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedDomain.isEmpty { return trimmedUser }
        return "\(trimmedDomain)\\\(trimmedUser)"
    }

    var displayName: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let account = accountName
        return account.isEmpty ? L("Учётная запись") : account
    }
}

/// Abstraction over secret storage. The app always uses the Keychain; tests use
/// an in-memory store so automated runs never read or write real credentials.
protocol SecretStore {
    func password(account: String) -> String?
    @discardableResult func save(password: String, account: String) -> Bool
    func delete(account: String)
    func hasPassword(account: String) -> Bool
}

struct KeychainSecretStore: SecretStore {
    func password(account: String) -> String? { KeychainStore.password(account: account) }

    @discardableResult
    func save(password: String, account: String) -> Bool {
        KeychainStore.save(password: password, account: account)
    }

    func delete(account: String) { KeychainStore.delete(account: account) }

    func hasPassword(account: String) -> Bool { KeychainStore.hasPassword(account: account) }
}

/// Test double: keeps secrets in memory only.
final class MemorySecretStore: SecretStore {
    private(set) var items: [String: String] = [:]

    func password(account: String) -> String? { items[account] }

    @discardableResult
    func save(password: String, account: String) -> Bool {
        items[account] = password
        return true
    }

    func delete(account: String) { items.removeValue(forKey: account) }

    func hasPassword(account: String) -> Bool { items[account] != nil }
}


/// Shared user directory persisted in `credentials.json` (JSON, no secrets).
final class CredentialStore {
    static let shared = CredentialStore()
    static let didChange = Notification.Name("RDPMacCredentialsDidChange")

    let directory: URL
    private(set) var credentials: [Credential] = []
    private let secrets: SecretStore
    private let fileURL: URL

    init(directory: URL? = nil, secrets: SecretStore = KeychainSecretStore()) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                              in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let target = directory ?? support.appendingPathComponent("RDPMac", isDirectory: true)
        try? FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        self.directory = target
        self.secrets = secrets
        fileURL = target.appendingPathComponent("credentials.json")
        load()
    }

    static func keychainAccount(for id: UUID) -> String {
        "credential/\(id.uuidString.lowercased())"
    }

    // MARK: - Directory

    func credential(id: UUID?) -> Credential? {
        guard let id else { return nil }
        return credentials.first { $0.id == id }
    }

    func credential(matchingLegacyAccount legacyAccount: String) -> Credential? {
        credentials.first { $0.legacyAccount == legacyAccount }
    }

    func upsert(_ credential: Credential) {
        if let index = credentials.firstIndex(where: { $0.id == credential.id }) {
            credentials[index] = credential
        } else {
            credentials.append(credential)
        }
        persist()
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }

    /// Removes the directory record and its Keychain item. Callers must detach
    /// profiles first and explain the consequence to the user.
    func delete(id: UUID) {
        guard let credential = credential(id: id) else { return }
        secrets.delete(account: credential.keychainAccount)
        credentials.removeAll { $0.id == id }
        persist()
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }

    /// Copy of a directory record with a new id. The saved password is copied
    /// when it can be read; the copy then works independently.
    @discardableResult
    func duplicate(_ credential: Credential, title: String? = nil) -> Credential {
        var copy = credential
        copy.id = UUID()
        copy.title = title ?? L("%@ — копия", credential.displayName)
        copy.legacyAccount = nil
        copy.createdAt = Date()
        if let secret = secrets.password(account: credential.keychainAccount) {
            secrets.save(password: secret, account: copy.keychainAccount)
        }
        upsert(copy)
        return copy
    }

    func profilesUsing(_ id: UUID, in store: ProfileStore = .shared) -> [Profile] {
        store.profilesUsing(credentialID: id)
    }

    // MARK: - Secrets

    func hasPassword(_ credential: Credential) -> Bool {
        secrets.hasPassword(account: credential.keychainAccount)
    }

    func password(for credential: Credential) -> String? {
        secrets.password(account: credential.keychainAccount)
    }

    @discardableResult
    func savePassword(_ password: String, for credential: Credential) -> Bool {
        secrets.save(password: password, account: credential.keychainAccount)
    }

    func forgetPassword(for credential: Credential) {
        secrets.delete(account: credential.keychainAccount)
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            credentials = try JSONDecoder().decode([Credential].self, from: data)
        } catch {
            LogStore.shared.append(L("Не удалось прочитать справочник учётных записей: %@",
                                     String(describing: error.localizedDescription)), level: 2)
            credentials = []
        }
    }

    private func persist() {
        do {
            let data = try JSONEncoder.pretty.encode(credentials)
            try data.write(to: fileURL, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                                   ofItemAtPath: fileURL.path)
        } catch {
            LogStore.shared.append(L("Не удалось сохранить справочник учётных записей: %@",
                                     String(describing: error.localizedDescription)), level: 2)
        }
    }
}


// MARK: - Migration from host-keyed Keychain entries (1.0.x)

extension CredentialStore {
    /// Links profiles that still store their password under the legacy
    /// `host:port/domain\user` Keychain key to a directory record.
    ///
    /// Idempotent and safe to interrupt: the record is persisted before the
    /// secret is copied, and the profile is persisted before the legacy marker
    /// is cleared. Legacy Keychain entries are never deleted here, so an older
    /// build keeps working. Nothing is logged except counts and status codes.
    @discardableResult
    func migrateLegacyPasswords(profiles store: ProfileStore) -> Int {
        var migrated = 0
        for var profile in store.profiles {
            guard profile.credentialID == nil, profile.savePassword else { continue }
            let username = profile.username.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !username.isEmpty else { continue }

            let legacy = KeychainStore.account(host: profile.host, port: profile.port,
                                               domain: profile.domain, username: profile.username)
            let record: Credential
            if let existing = credential(matchingLegacyAccount: legacy) {
                record = existing
            } else {
                var created = Credential(title: profile.displayName,
                                         username: profile.username,
                                         domain: profile.domain)
                created.legacyAccount = legacy
                upsert(created) // persisted before the secret is touched
                record = created
            }

            let target = record.keychainAccount
            if !secrets.hasPassword(account: target) {
                guard let secret = secrets.password(account: legacy),
                      secrets.save(password: secret, account: target),
                      secrets.password(account: target) == secret else {
                    // No readable secret (missing item or denied access). Leave
                    // the profile on the legacy key so nothing is lost and try
                    // again on the next launch.
                    continue
                }
            }

            profile.credentialID = record.id
            store.upsert(profile) // persisted before the marker is cleared

            if record.legacyAccount != nil {
                var updated = record
                updated.legacyAccount = nil
                upsert(updated)
            }
            migrated += 1
        }

        // Drop stale markers that no unmigrated legacy profile still needs.
        for var credential in credentials {
            guard let legacy = credential.legacyAccount else { continue }
            let stillUsed = store.profiles.contains { profile in
                profile.credentialID == nil && profile.savePassword &&
                    KeychainStore.account(host: profile.host, port: profile.port,
                                          domain: profile.domain,
                                          username: profile.username) == legacy
            }
            if !stillUsed {
                credential.legacyAccount = nil
                upsert(credential)
            }
        }
        return migrated
    }

    /// Creates a directory record for a profile whose password still lives
    /// under the legacy key and copies the secret into it. Returns nil when the
    /// secret cannot be read; the caller then asks for a password instead.
    /// `secret` may be passed when the caller already read it, so a Keychain
    /// prompt is never shown twice for the same lookup.
    func attachLegacyPassword(for profile: Profile, secret: String? = nil) -> Credential? {
        guard !profile.username.isEmpty else { return nil }
        let legacy = KeychainStore.account(host: profile.host, port: profile.port,
                                           domain: profile.domain, username: profile.username)
        guard let secret = secret ?? secrets.password(account: legacy) else { return nil }

        var credential = Credential(title: profile.displayName,
                                    username: profile.username,
                                    domain: profile.domain)
        guard secrets.save(password: secret, account: credential.keychainAccount),
              secrets.password(account: credential.keychainAccount) == secret else { return nil }
        credential.legacyAccount = nil
        upsert(credential)
        return credential
    }
}
