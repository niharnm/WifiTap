import Foundation

enum WiFiSecurity: String, Codable, CaseIterable, Sendable {
    case open
    /// WPA2 or WPA3 Personal (passphrase networks).
    case wpa2
}

enum CardMode: String, Codable, CaseIterable, Sendable {
    /// URL record for iPhone plus a Wi-Fi record Android reads without an app.
    case urlAndWifi = "url_and_wifi"
    /// URL record only; the password stays on the server.
    case urlOnly = "url_only"
}

struct WiFiCredentials: Equatable, Codable, Sendable {
    enum ValidationError: Error, Equatable, Sendable {
        case ssidEmpty
        case ssidTooLong
        case passwordRequired
        case passwordInvalid
        case passwordNotAllowed

        var message: String {
            switch self {
            case .ssidEmpty: "Enter the network name."
            case .ssidTooLong: "Network names can be at most 32 bytes."
            case .passwordRequired: "Enter the Wi-Fi password."
            case .passwordInvalid: "Wi-Fi passwords are 8 to 63 standard keyboard characters."
            case .passwordNotAllowed: "Open networks don't use a password."
            }
        }
    }

    let ssid: String
    let password: String?
    let security: WiFiSecurity

    init(ssid: String, password: String?, security: WiFiSecurity) throws(ValidationError) {
        let ssidBytes = ssid.utf8.count
        guard ssidBytes > 0 else { throw .ssidEmpty }
        guard ssidBytes <= 32 else { throw .ssidTooLong }

        switch security {
        case .open:
            guard password?.isEmpty ?? true else { throw .passwordNotAllowed }
            self.password = nil
        case .wpa2:
            guard let password, !password.isEmpty else { throw .passwordRequired }
            guard Self.isValidPassphrase(password) else { throw .passwordInvalid }
            self.password = password
        }
        self.ssid = ssid
        self.security = security
    }

    /// WPA passphrases are 8 to 63 printable ASCII characters.
    static func isValidPassphrase(_ passphrase: String) -> Bool {
        (8...63).contains(passphrase.unicodeScalars.count)
            && passphrase.unicodeScalars.allSatisfy { (0x20...0x7E).contains($0.value) }
    }

    enum CodingKeys: String, CodingKey {
        case ssid, password, security
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            ssid: container.decode(String.self, forKey: .ssid),
            password: container.decodeIfPresent(String.self, forKey: .password),
            security: container.decode(WiFiSecurity.self, forKey: .security)
        )
    }
}
