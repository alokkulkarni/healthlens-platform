import Foundation
import Security
import OSLog

enum KeychainError: LocalizedError {
    case saveFailure(OSStatus)
    case retrievalFailure(OSStatus)
    case deleteFailure(OSStatus)
    case encodingFailure
    case notFound

    var errorDescription: String? {
        switch self {
        case .saveFailure(let status):
            return "Keychain save failed: \(SecCopyErrorMessageString(status, nil) as String? ?? String(status))"
        case .retrievalFailure(let status):
            return "Keychain retrieval failed: \(SecCopyErrorMessageString(status, nil) as String? ?? String(status))"
        case .deleteFailure(let status):
            return "Keychain delete failed: \(SecCopyErrorMessageString(status, nil) as String? ?? String(status))"
        case .encodingFailure:
            return "Failed to encode value for Keychain storage"
        case .notFound:
            return "Key not found in Keychain"
        }
    }
}

struct KeychainService {
    private let service: String

    init(service: String = Constants.Keychain.service) {
        self.service = service
    }

    func save(_ value: String, for key: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingFailure
        }

        // Try updating first
        let updateQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
        ]
        let updateAttributes: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(updateQuery as CFDictionary, updateAttributes as CFDictionary)

        if updateStatus == errSecItemNotFound {
            // Insert new item
            let addQuery: [CFString: Any] = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: service,
                kSecAttrAccount: key,
                kSecValueData: data,
                kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            ]
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                Logger.keychain.error("Save failed for key: \(addStatus)")
                throw KeychainError.saveFailure(addStatus)
            }
        } else if updateStatus != errSecSuccess {
            Logger.keychain.error("Update failed for Keychain item: \(updateStatus)")
            throw KeychainError.saveFailure(updateStatus)
        }
        #if DEBUG
        Logger.keychain.debug("Saved Keychain key '\(key)' successfully")
        #endif
    }

    func retrieve(for key: String) throws -> String {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw KeychainError.notFound
            }
            throw KeychainError.retrievalFailure(status)
        }
        guard let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw KeychainError.encodingFailure
        }
        return value
    }

    func delete(for key: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailure(status)
        }
        #if DEBUG
        Logger.keychain.debug("Deleted Keychain key '\(key)'")
        #endif
    }

    func exists(for key: String) -> Bool {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }
}
