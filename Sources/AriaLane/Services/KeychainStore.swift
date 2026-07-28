import Foundation
import Security

enum KeychainOperation: String, Equatable {
    case add
    case update
    case delete
    case verifyWrite
    case verifyDelete

    var description: String {
        switch self {
        case .add:
            return "add"
        case .update:
            return "update"
        case .delete:
            return "delete"
        case .verifyWrite:
            return "verify write"
        case .verifyDelete:
            return "verify deletion"
        }
    }
}

enum KeychainStoreError: LocalizedError, Equatable {
    case operationFailed(operation: KeychainOperation, status: OSStatus)
    case verificationFailed(operation: KeychainOperation)

    var errorDescription: String? {
        switch self {
        case .operationFailed(let operation, let status):
            let systemMessage =
                SecCopyErrorMessageString(status, nil) as String?
                ?? "OSStatus \(status)"
            return "Keychain \(operation.description) failed: \(systemMessage) (\(status))"
        case .verificationFailed(let operation):
            return "Keychain \(operation.description) did not match the requested result."
        }
    }
}

struct KeychainClient {
    private let readValue: (_ service: String, _ account: String) -> String?
    private let saveValue:
        (_ value: String, _ service: String, _ account: String) throws -> Void

    init(
        read: @escaping (_ service: String, _ account: String) -> String?,
        save: @escaping (
            _ value: String,
            _ service: String,
            _ account: String
        ) throws -> Void
    ) {
        readValue = read
        saveValue = save
    }

    func read(service: String, account: String) -> String? {
        readValue(service, account)
    }

    func save(_ value: String, service: String, account: String) throws {
        try saveValue(value, service, account)
    }

    static let live = KeychainClient(
        read: { service, account in
            KeychainStore.read(service: service, account: account)
        },
        save: { value, service, account in
            try KeychainStore.save(value, service: service, account: account)
        }
    )
}

enum KeychainStore {
    static let service = "dev.arialane.app"

    static func read(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ value: String, service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        if value.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            try validateStatus(
                status,
                operation: .delete,
                allowsItemNotFound: true
            )
            try verifyDeletion(query: query)
            return
        }

        let data = Data(value.utf8)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            attributes.forEach { item[$0.key] = $0.value }
            try validateStatus(
                SecItemAdd(item as CFDictionary, nil),
                operation: .add
            )
        } else {
            try validateStatus(status, operation: .update)
        }

        try verifyWrite(query: query, expectedData: data)
    }

    static func validateStatus(
        _ status: OSStatus,
        operation: KeychainOperation,
        allowsItemNotFound: Bool = false
    ) throws {
        if status == errSecSuccess {
            return
        }
        if allowsItemNotFound, status == errSecItemNotFound {
            return
        }
        throw KeychainStoreError.operationFailed(
            operation: operation,
            status: status
        )
    }

    private static func verifyWrite(
        query: [String: Any],
        expectedData: Data
    ) throws {
        var verificationQuery = query
        verificationQuery[kSecReturnData as String] = true
        verificationQuery[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(
            verificationQuery as CFDictionary,
            &item
        )
        try validateStatus(status, operation: .verifyWrite)
        guard let storedData = item as? Data,
              storedData == expectedData else {
            throw KeychainStoreError.verificationFailed(
                operation: .verifyWrite
            )
        }
    }

    private static func verifyDeletion(query: [String: Any]) throws {
        var verificationQuery = query
        verificationQuery[kSecReturnData as String] = true
        verificationQuery[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(
            verificationQuery as CFDictionary,
            &item
        )
        if status == errSecItemNotFound {
            return
        }
        if status == errSecSuccess {
            throw KeychainStoreError.verificationFailed(
                operation: .verifyDelete
            )
        }
        throw KeychainStoreError.operationFailed(
            operation: .verifyDelete,
            status: status
        )
    }
}
