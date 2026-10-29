import Foundation
import Security

/// A seam so tests never touch, or get prompted by, the real Keychain.
protocol TokenStorage {
    func load() -> String

    /// An empty token removes the stored one. `false` means the token is memory-only from here
    /// on, which nothing else would reveal to the user.
    func save(_ token: String) -> Bool
}

/// Not `UserDefaults`: any process running as the user can read a preferences plist without a
/// prompt, and Time Machine backs it up in the clear.
struct KeychainTokenStore: TokenStorage {
    private static let service = "dev.nevermind.sugarglider"
    private static let account = "nightscout-token"

    /// The data-protection Keychain never prompts but needs the `keychain-access-groups`
    /// entitlement, which only a build with a provisioning profile has (docs/signing.md); the
    /// login Keychain takes any signature but prompts when it changes. Probed once, because
    /// deciding per call risks writing to one Keychain and reading the other.
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
        // A build signed differently stores the token in the other Keychain, so a release that
        // starts or stops shipping the profile would otherwise appear to lose it.
        guard let stray = Self.read(dataProtection: !Self.usesDataProtection) else { return "" }
        // Only a copy that arrived may replace the stray one, or a refused write loses the token.
        if Self.write(stray, dataProtection: Self.usesDataProtection) {
            Self.remove(dataProtection: !Self.usesDataProtection)
        }
        return stray
    }

    func save(_ token: String) -> Bool {
        guard !token.isEmpty else {
            // Both, or load() would resurrect the stray copy of a token the user just deleted.
            return Self.remove(dataProtection: true) && Self.remove(dataProtection: false)
        }
        guard Self.write(token, dataProtection: Self.usesDataProtection) else { return false }
        // The copy in the other Keychain is stale now, like load() removes it after its write.
        Self.remove(dataProtection: !Self.usesDataProtection)
        return true
    }

    private static func baseQuery(dataProtection: Bool) -> [CFString: Any] {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
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

    private static func write(_ token: String, dataProtection: Bool) -> Bool {
        let query = baseQuery(dataProtection: dataProtection)
        let data = Data(token.utf8)
        // Updating in place keeps the item's ACL, which is what spares the next launch a prompt.
        if SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary) == errSecSuccess {
            return true
        }
        var item = query
        item[kSecValueData] = data
        if dataProtection {
            // Only this Keychain has the attribute. AfterFirstUnlock lets a login-item launch read
            // the token; ThisDeviceOnly keeps it out of iCloud Keychain.
            item[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        }
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    /// True when the item is gone; a failed delete must report the token as memory-only.
    private static func remove(dataProtection: Bool) -> Bool {
        let status = SecItemDelete(baseQuery(dataProtection: dataProtection) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
