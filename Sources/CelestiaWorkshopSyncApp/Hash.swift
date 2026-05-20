import CryptoKit
import Foundation

func sha256(_ string: String) -> String {
    let digest = SHA256.hash(data: Data(string.utf8))
    return "sha256:" + digest.map { String(format: "%02x", $0) }.joined()
}
