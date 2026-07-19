//
//  PasswordHasher.swift
//  sharePlate
//
//  Salted SHA-256 password hashing. Adequate for a local prototype; a real
//  backend should use a slow KDF (bcrypt/scrypt/Argon2) server-side.
//

import Foundation
import CryptoKit

enum PasswordHasher {
    static func makeSalt() -> String {
        UUID().uuidString
    }

    static func hash(_ password: String, salt: String) -> String {
        let data = Data((password + salt).utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func verify(_ password: String, salt: String, expectedHash: String) -> Bool {
        hash(password, salt: salt) == expectedHash
    }
}
