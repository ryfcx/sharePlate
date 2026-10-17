import Foundation
import Security
import Supabase

nonisolated struct PendingAccountDeletion: Codable {
    let requestID: UUID
    let userID: UUID
    let secret: String
    var accessToken: String
}

enum AccountDeletionError: LocalizedError {
    case unavailable
    case unfinished
    case secureStorage
    case startFailed

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return String(localized: "Couldn't verify your account. Check your connection and try again.")
        case .unfinished:
            return String(localized: "Deletion hasn't finished. Please retry. Your request is saved securely on this device.")
        case .secureStorage:
            return String(localized: "Couldn't access secure storage. Unlock your device and try again.")
        case .startFailed:
            return String(localized: "Couldn't start again. Check your connection and try again.")
        }
    }
}

enum AccountDeletionStorage {
    static let pendingKey = "sharePlate.deletionPending"
    static let deletedKey = "sharePlate.accountDeleted"
    private static let service = "com.keellabs.shareplate.account-deletion"

    static var preventsAutomaticSignIn: Bool {
        UserDefaults.standard.bool(forKey: pendingKey) || UserDefaults.standard.bool(forKey: deletedKey)
            || (try? load()) != nil
    }

    static func load() throws -> PendingAccountDeletion? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "pending",
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let request = try? JSONDecoder().decode(PendingAccountDeletion.self, from: data) else {
            throw AccountDeletionError.secureStorage
        }
        return request
    }

    static func save(_ request: PendingAccountDeletion) throws {
        let data = try JSONEncoder().encode(request)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "pending"]
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw AccountDeletionError.secureStorage }
        UserDefaults.standard.set(true, forKey: pendingKey)
    }

    static func clear() throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "pending"]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AccountDeletionError.secureStorage
        }
    }
}

enum AccountDeletionService {
    static func prepare() async throws -> PendingAccountDeletion {
        if let saved = try AccountDeletionStorage.load() { return saved }
        // never create a replacement account while trying to delete the old one
        guard !UserDefaults.standard.bool(forKey: AccountDeletionStorage.pendingKey),
              var current = SupabaseManager.client.auth.currentSession else {
            throw AccountDeletionError.unavailable
        }
        let owner = current.user.id
        if current.isExpired { current = try await SupabaseManager.client.auth.refreshSession() }
        guard current.user.id == owner else { throw AccountDeletionError.unavailable }
        let secret = (UUID().uuidString + UUID().uuidString).replacingOccurrences(of: "-", with: "").lowercased()
        let request = PendingAccountDeletion(requestID: UUID(), userID: owner,
            secret: secret, accessToken: current.accessToken)
        try AccountDeletionStorage.save(request)
        return request
    }

    static func execute(_ pending: PendingAccountDeletion, canRefresh: Bool = true) async throws {
        struct Input: Encodable { let requestID: UUID; let secret: String; let confirm: Bool }
        struct Receipt: Decodable { let deleted: Bool }
        var request = URLRequest(url: SupabaseConfig.projectURL.appendingPathComponent("functions/v1/delete-account"))
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseConfig.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(pending.accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(Input(requestID: pending.requestID, secret: pending.secret, confirm: true))
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AccountDeletionError.unfinished }
        if http.statusCode == 401, canRefresh,
           SupabaseManager.client.auth.currentSession?.user.id == pending.userID {
            let renewed = try await SupabaseManager.client.auth.refreshSession()
            guard renewed.user.id == pending.userID else { throw AccountDeletionError.unavailable }
            var retry = pending
            retry.accessToken = renewed.accessToken
            try AccountDeletionStorage.save(retry)
            return try await execute(retry, canRefresh: false)
        }
        guard (200..<300).contains(http.statusCode),
              let receipt = try? JSONDecoder().decode(Receipt.self, from: data), receipt.deleted else {
            throw AccountDeletionError.unfinished
        }
    }
}
