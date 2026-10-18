import Foundation
import Security

/// Card URLs have the form https://<domain>/t/<token>, where the token is
/// 128 random bits in unpadded base64url (22 characters).
enum CardLink {
    static func url(base: URL, token: String) -> URL {
        base.appending(path: "t/\(token)")
    }

    static func token(from url: URL) -> String? {
        let parts = url.pathComponents
        guard url.scheme == "https", parts.count == 3, parts[1] == "t", isValidToken(parts[2]) else {
            return nil
        }
        return parts[2]
    }

    static func isValidToken(_ token: String) -> Bool {
        token.count == 22 && token.unicodeScalars.allSatisfy {
            ($0.isASCII && CharacterSet.alphanumerics.contains($0)) || $0 == "-" || $0 == "_"
        }
    }

    static func randomToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed: \(status)")
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
