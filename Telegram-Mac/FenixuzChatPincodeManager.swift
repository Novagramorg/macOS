//
//  FenixuzChatPincodeManager.swift
//  Telegram-Mac
//
//  iOS portasi: submodules/Fenixuz/ChatLock/Sources/ChatPincodeManager.swift
//
//  Per-chat pincode'ni Keychain'da saqlaydi (`uz.fenixuz.app.ChatLock` service
//  identifier ostida). Eski UserDefaults-based plaintext storage Wave 1 (iOS)
//  da bekor qilingan; Mac uchun yangi orniftiqliq holatdan boshlanadi.
//
//  Bu modul faqat DATA layer — UI (pin entry view, lock state monitor) Wave 5
//  da AppKit ostida yoziladi. Hozircha Mac consumer'lar hech qanday joydan
//  bu manager'ni chaqirmaydi; ammo siyosatga ko'ra modul mavjud bo'lib turadi,
//  shunda kelajakda biror joy locked chat'ga kirmoqchi bo'lsa, `getPincode`,
//  `setPincode`, `removePincode`, `verify` API'lari tayyor.
//
//  Constant-time compare timing side-channel'larga qarshi.

import Foundation
import Security
import CryptoKit
import Postbox

private let keychainService = "uz.fenixuz.app.ChatLock"

// Fallback store (UserDefaults) — engaged only when the keychain rejects writes
// (fake-codesigned / unsigned dev builds get errSecMissingEntitlement -34018, so
// SecItemAdd silently fails and the lock never engages). The credential is stored
// here as a salted SHA-256 hash — never plaintext.
private let fallbackSaltKey = "fenixuz_chatlock_fb_salt"
private let fallbackPwPrefix = "fenixuz_chatlock_fb_pw_"

public final class FenixuzChatPincodeManager {
    public static let shared = FenixuzChatPincodeManager()

    private init() {}

    // MARK: - Public API

    public func getPincode(for peerId: PeerId) -> String? {
        return read(account: account(for: peerId))
    }

    public func setPincode(_ code: String, for peerId: PeerId) {
        write(code, account: account(for: peerId))
    }

    public func removePincode(for peerId: PeerId) {
        delete(account: account(for: peerId))
        deleteFallback(account: account(for: peerId))
    }

    public func isLocked(_ peerId: PeerId) -> Bool {
        let key = account(for: peerId)
        return read(account: key) != nil || readFallbackHash(account: key) != nil
    }

    public func verify(_ code: String, for peerId: PeerId) -> Bool {
        let key = account(for: peerId)
        if let stored = read(account: key) {
            return constantTimeEquals(stored, code)
        }
        if let hash = readFallbackHash(account: key) {
            return constantTimeEquals(hash, fallbackHash(of: code))
        }
        return false
    }

    // MARK: - Master pincode API
    //
    // The "master" gates whether the per-chat lock feature is available at all,
    // and doubles as a recovery key ("Forgot pincode?") to clear a single chat's
    // lock. It reuses the same keychain + salted-hash fallback plumbing under a
    // reserved account key that can never collide with a numeric peerId.toInt64().
    private let masterAccount = "__fenix_master__"

    public func isMasterEnabled() -> Bool {
        return read(account: masterAccount) != nil || readFallbackHash(account: masterAccount) != nil
    }

    public func setMasterPincode(_ code: String) {
        write(code, account: masterAccount)
    }

    public func verifyMaster(_ code: String) -> Bool {
        if let stored = read(account: masterAccount) {
            return constantTimeEquals(stored, code)
        }
        if let hash = readFallbackHash(account: masterAccount) {
            return constantTimeEquals(hash, fallbackHash(of: code))
        }
        return false
    }

    public func removeMaster() {
        delete(account: masterAccount)
        deleteFallback(account: masterAccount)
    }

    /// Turn the whole chat-lock feature off: wipe the master AND every per-chat
    /// credential so nothing is stranded and re-enabling later starts clean.
    public func disableChatLock() {
        // Keychain: drop every item under our service in one sweep.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService
        ]
        _ = SecItemDelete(query as CFDictionary)
        // UserDefaults fallback: remove every per-account password key.
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(fallbackPwPrefix) {
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: - Keychain plumbing

    private func account(for peerId: PeerId) -> String {
        return "\(peerId.toInt64())"
    }

    private func baseQuery(account: String) -> [String: Any] {
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account
        ]
    }

    private func read(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    private func write(_ value: String, account: String) {
        guard let data = value.data(using: .utf8) else { return }

        let updateQuery = baseQuery(account: account)
        let updateAttributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        if SecItemUpdate(updateQuery as CFDictionary, updateAttributes as CFDictionary) == errSecSuccess {
            deleteFallback(account: account)
            return
        }

        var addQuery = baseQuery(account: account)
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        if SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess {
            deleteFallback(account: account)
        } else {
            // Keychain rejected the write (dev/unsigned builds get -34018
            // errSecMissingEntitlement) — persist a salted hash instead so the
            // lock still engages rather than silently failing open.
            writeFallbackHash(value, account: account)
        }
    }

    private func delete(account: String) {
        let query = baseQuery(account: account)
        _ = SecItemDelete(query as CFDictionary)
    }

    // MARK: - UserDefaults fallback (keychain-unavailable builds)

    private let saltLock = NSLock()

    /// Per-install random salt for the fallback hash. Created lazily on first use.
    private func fallbackSalt() -> String {
        saltLock.lock()
        defer { saltLock.unlock() }
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: fallbackSaltKey) {
            return existing
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            for i in 0..<bytes.count {
                bytes[i] = UInt8.random(in: .min ... .max)
            }
        }
        let salt = Data(bytes).base64EncodedString()
        defaults.set(salt, forKey: fallbackSaltKey)
        return salt
    }

    private func fallbackHash(of code: String) -> String {
        let payload = Data((fallbackSalt() + code).utf8)
        return SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
    }

    private func writeFallbackHash(_ value: String, account: String) {
        UserDefaults.standard.set(fallbackHash(of: value), forKey: fallbackPwPrefix + account)
    }

    private func readFallbackHash(account: String) -> String? {
        return UserDefaults.standard.string(forKey: fallbackPwPrefix + account)
    }

    private func deleteFallback(account: String) {
        UserDefaults.standard.removeObject(forKey: fallbackPwPrefix + account)
    }
}

// MARK: - Constant-time compare

private func constantTimeEquals(_ a: String, _ b: String) -> Bool {
    let aBytes = Array(a.utf8)
    let bBytes = Array(b.utf8)
    if aBytes.count != bBytes.count {
        return false
    }
    var diff: UInt8 = 0
    for i in 0..<aBytes.count {
        diff |= aBytes[i] ^ bBytes[i]
    }
    return diff == 0
}
