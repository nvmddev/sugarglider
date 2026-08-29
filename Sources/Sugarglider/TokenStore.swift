import Foundation
import Security

/// Where the Nightscout access token is persisted. A seam rather than an
/// abstraction for its own sake: `KeychainTokenStore` is the only implementation
/// that ships, but `AppSettings.init` takes one the way it takes a
/// `UserDefaults`, so the test suite never touches — or prompts against — the
/// real login Keychain.
@MainActor
protocol TokenStorage {
    /// The stored token, or `""` when there is none.
    func load() -> String

    /// Persists `token`, removing the item when it is empty. `false` means the
    /// token is memory-only from here on and won't survive a relaunch — the one
    /// failure worth telling the user about, since nothing else reveals it.
    @discardableResult
    func save(_ token: String) -> Bool
}

/// Keychain-backed storage for the access token: one generic-password item,
/// ACL'd to this app. The token used to live in `UserDefaults`, i.e. in
/// `~/Library/Preferences/dev.nevermind.sugarglider.plist`, which *any* process
/// running as the user can read with a plain `defaults read` — no prompt, no
/// entitlement — and which rides along in Time Machine backups in the clear.
@MainActor
struct KeychainTokenStore: TokenStorage {
    static let service = "dev.nevermind.sugarglider"
    static let account = "nightscout-token"

    /// macOS exposes two Keychains through one API, and the app's *signature*
    /// decides which of them it may use. The modern data-protection Keychain
    /// needs a `keychain-access-groups` entitlement, which only a build carrying
    /// a provisioning profile has (see docs/signing.md), and reads without ever
    /// prompting; the older file-based login Keychain takes anyone, at the price
    /// of an access prompt whenever the signature changes. Probe once and cache
    /// the answer — asking per call risks writing to one and reading the other.
    private static let usesDataProtection: Bool = {
        var probe = baseQuery(dataProtection: true)
        probe[kSecAttrAccount] = "\(account).probe"
        probe[kSecValueData] = Data("probe".utf8)
        let status = SecItemAdd(probe as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else { return false }
        probe.removeValue(forKey: kSecValueData)
        SecItemDelete(probe as CFDictionary)
        return true
    }()

    func load() -> String {
        if let token = Self.read(dataProtection: Self.usesDataProtection) { return token }
        // Nothing there — so look in the *other* Keychain, in case the copy that
        // stored the token was signed differently. A release that starts (or
        // stops) shipping the provisioning profile switches Keychains, and would
        // otherwise find an empty one and silently drop a token the user had
        // already entered. Moving the item across makes that cost one extra
        // lookup exactly once.
        guard let stray = Self.read(dataProtection: !Self.usesDataProtection) else { return "" }
        Self.write(stray, dataProtection: Self.usesDataProtection)
        Self.remove(dataProtection: !Self.usesDataProtection)
        return stray
    }

    @discardableResult
    func save(_ token: String) -> Bool {
        guard !token.isEmpty else {
            // Clear both, or the stray-item lookup in `load()` resurrects a
            // token the user just deleted.
            Self.remove(dataProtection: true)
            Self.remove(dataProtection: false)
            return true
        }
        return Self.write(token, dataProtection: Self.usesDataProtection)
    }

    // MARK: - Keychain plumbing

    private static func baseQuery(dataProtection: Bool) -> [CFString: Any] {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        if dataProtection { query[kSecUseDataProtectionKeychain] = true }
        return query
    }

    private static func read(dataProtection: Bool) -> String? {
        var query = baseQuery(dataProtection: dataProtection)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty
        else { return nil }
        return token
    }

    @discardableResult
    private static func write(_ token: String, dataProtection: Bool) -> Bool {
        let query = baseQuery(dataProtection: dataProtection)
        let data = Data(token.utf8)
        // Update in place when the item already exists, so its ACL — the thing
        // that keeps the next launch from prompting — survives a token change.
        if SecItemUpdate(query as CFDictionary,
                         [kSecValueData: data] as CFDictionary) == errSecSuccess { return true }
        var item = query
        item[kSecValueData] = data
        if dataProtection {
            // Only the data-protection Keychain has an accessibility attribute.
            // "AfterFirstUnlock" so a login-item launch can read the token
            // before anyone has touched the keyboard; "ThisDevice" keeps it out
            // of iCloud Keychain — this token belongs to one Mac.
            item[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        }
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    private static func remove(dataProtection: Bool) {
        SecItemDelete(baseQuery(dataProtection: dataProtection) as CFDictionary)
    }
}
