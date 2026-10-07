// Maintainer-only signing helper. The private key stays in login Keychain.
import CryptoKit
import Foundation
import Security

let service="com.gemst.media-support-master.tool-updates.signing"
let query:[String:Any]=[kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,
                       kSecAttrAccount as String:"Ed25519",kSecReturnData as String:true,kSecMatchLimit as String:kSecMatchLimitOne]
var found:CFTypeRef?
let status=SecItemCopyMatching(query as CFDictionary,&found)
let key:Curve25519.Signing.PrivateKey
if status==errSecSuccess,let data=found as? Data {
    key=try Curve25519.Signing.PrivateKey(rawRepresentation:data)
} else if status==errSecItemNotFound {
    key=Curve25519.Signing.PrivateKey()
    let add:[String:Any]=[kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,
        kSecAttrAccount as String:"Ed25519",kSecAttrLabel as String:"Media Support Master Tool Update Signing",
        kSecValueData as String:key.rawRepresentation,kSecAttrAccessible as String:kSecAttrAccessibleWhenUnlocked]
    guard SecItemAdd(add as CFDictionary,nil)==errSecSuccess else { fatalError("Cannot store signing key") }
} else { fatalError("Cannot access signing key: \(status)") }
struct Envelope:Encodable { let payload:Data;let signature:Data }
if CommandLine.arguments.count==3 {
    let data=try Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))
    let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
    try encoder.encode(Envelope(payload:data,signature:try key.signature(for:data)))
        .write(to:URL(fileURLWithPath:CommandLine.arguments[2]),options:.atomic)
}
print(key.publicKey.rawRepresentation.base64EncodedString())
