// ABOUTME: Stores FAL generation and account-administration credentials under separate identities.
// ABOUTME: Provides a Keychain production adapter and injectable storage for deterministic tests.

import Foundation
import Security

public enum CredentialSlot: String, Sendable {
    case generation = "fal-generation"
    case accountAdministration = "fal-account-administration"
}

public protocol CredentialStorage: AnyObject {
    func value(for slot: CredentialSlot) throws -> String?
    func setValue(_ value: String, for slot: CredentialSlot) throws
    func removeValue(for slot: CredentialSlot) throws
}

public final class KeychainCredentialStorage: CredentialStorage {
    private let service: String

    public init(service: String = "org.tigoss.superscale.generation") {
        self.service = service
    }

    public func value(for slot: CredentialSlot) throws -> String? {
        var query = baseQuery(for: slot)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainCredentialError(status: status) }
        guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw KeychainCredentialError.invalidStoredValue
        }
        return value
    }

    public func setValue(_ value: String, for slot: CredentialSlot) throws {
        let data = Data(value.utf8)
        let updateStatus = SecItemUpdate(
            baseQuery(for: slot) as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainCredentialError(status: updateStatus)
        }

        var attributes = baseQuery(for: slot)
        attributes[kSecValueData as String] = data
        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw KeychainCredentialError(status: addStatus) }
    }

    public func removeValue(for slot: CredentialSlot) throws {
        let status = SecItemDelete(baseQuery(for: slot) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainCredentialError(status: status)
        }
    }

    private func baseQuery(for slot: CredentialSlot) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: slot.rawValue,
        ]
    }
}

public final class GenerationCredentialService {
    private let storage: any CredentialStorage

    public init(storage: any CredentialStorage) {
        self.storage = storage
    }

    public func generationKey() throws -> String? {
        try storage.value(for: .generation)
    }

    public func setGenerationKey(_ value: String) throws {
        try storage.setValue(value, for: .generation)
    }

    public func removeGenerationKey() throws {
        try storage.removeValue(for: .generation)
    }

    public func accountAdministrationKey() throws -> String? {
        try storage.value(for: .accountAdministration)
    }

    public func setAccountAdministrationKey(_ value: String) throws {
        try storage.setValue(value, for: .accountAdministration)
    }

    public func removeAccountAdministrationKey() throws {
        try storage.removeValue(for: .accountAdministration)
    }
}

public enum KeychainCredentialError: LocalizedError {
    case status(OSStatus)
    case invalidStoredValue

    init(status: OSStatus) {
        self = .status(status)
    }

    public var errorDescription: String? {
        switch self {
        case let .status(status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "unknown Keychain error"
            return "Unable to update Superscale credentials: \(message)."
        case .invalidStoredValue:
            return "A Superscale credential in Keychain cannot be read."
        }
    }
}
