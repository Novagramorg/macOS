import Foundation

/// Shared config for the Novagram ad-serving integrations (search + chat ads).
///
/// `apiKey` is the server-to-server `X-API-Key` the serving endpoints require
/// since NovagramAds 2.1.0. The clients authenticate ad serving with this key
/// (never the user JWT — that is admin-panel only), so impression/click stats
/// stay trustworthy.
///
/// The key is XOR-obfuscated below so it is not a plain, greppable string in the
/// shipped binary. ⚠️ This only deters casual `strings` extraction — it is NOT
/// real secrecy: a determined attacker can still recover it at runtime. The only
/// true fix is a backend proxy that holds the key. Rotate the key on every publish.
///
/// This is a byte-for-byte mirror of the iOS
/// `submodules/Fenixuz/NovagramAds/Sources/FenixNovagramAds/FenixNovagramAdsConfig.swift`
/// so both clients send the same key. Keep them in sync on every key rotation.
enum FenixNovagramAdsConfig {
    /// The de-obfuscated X-API-Key for ad serving.
    static var apiKey: String {
        let obfuscated: [UInt8] = [
            0x25, 0x5c, 0x04, 0x5c, 0x32, 0x46, 0x5b, 0x2c, 0x77, 0x1c, 0x6b, 0x34,
            0x2d, 0x2f, 0x4b, 0x73, 0x54, 0x1d, 0x7a, 0x23, 0x17, 0x10, 0x1f, 0x05,
            0x34, 0x54, 0x25, 0x49, 0x29, 0x7d, 0x15, 0x4b, 0x0c, 0x38, 0x7f, 0x1c,
            0x70, 0x29, 0x38, 0x10, 0x6b, 0x63, 0x54, 0x3b, 0x49, 0x20, 0x36, 0x06,
            0x0f, 0x0d, 0x1c, 0x30, 0x0c, 0x7c, 0x17, 0x19, 0x3d, 0x16, 0x65, 0x0a,
            0x6e, 0x08, 0x01, 0x21
        ]
        let pad: [UInt8] = [
            0x6e, 0x30, 0x76, 0x34, 0x67, 0x72, 0x34, 0x6d, 0x2d, 0x66, 0x33, 0x6e,
            0x69, 0x78, 0x2d, 0x34, 0x64, 0x73, 0x2d, 0x73, 0x65, 0x72, 0x76, 0x69,
            0x6e, 0x67
        ]
        var bytes = [UInt8]()
        bytes.reserveCapacity(obfuscated.count)
        for (index, byte) in obfuscated.enumerated() {
            bytes.append(byte ^ pad[index % pad.count])
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}
