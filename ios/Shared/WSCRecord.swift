import Foundation

/// Wi-Fi Simple Configuration credential, the NDEF record Android's built-in
/// NFC service reads to offer "Connect to network" without any app installed.
/// Field IDs follow the WFA Wi-Fi Simple Configuration specification.
enum WSCRecord {
    static let mimeType = "application/vnd.wfa.wsc"

    private enum Field: UInt16 {
        case version = 0x104A
        case credential = 0x100E
        case networkIndex = 0x1026
        case ssid = 0x1045
        case authType = 0x1003
        case encryptionType = 0x100F
        case networkKey = 0x1027
        case macAddress = 0x1020
    }

    static func payload(for credentials: WiFiCredentials) -> Data {
        let authType: UInt16
        let encryptionType: UInt16
        switch credentials.security {
        case .open:
            (authType, encryptionType) = (0x0001, 0x0001)
        case .wpa2:
            (authType, encryptionType) = (0x0020, 0x0008)
        }

        var credential = tlv(.networkIndex, Data([0x01]))
        credential += tlv(.ssid, Data(credentials.ssid.utf8))
        credential += tlv(.authType, bigEndian(authType))
        credential += tlv(.encryptionType, bigEndian(encryptionType))
        if let password = credentials.password {
            credential += tlv(.networkKey, Data(password.utf8))
        }
        // Broadcast MAC: the credential applies to any access point with this SSID.
        credential += tlv(.macAddress, Data(repeating: 0xFF, count: 6))

        return tlv(.version, Data([0x10])) + tlv(.credential, credential)
    }

    // Lengths are bounded by WiFiCredentials validation (SSID 32, key 63).
    private static func tlv(_ field: Field, _ value: Data) -> Data {
        bigEndian(field.rawValue) + bigEndian(UInt16(value.count)) + value
    }

    private static func bigEndian(_ value: UInt16) -> Data {
        Data([UInt8(value >> 8), UInt8(value & 0xFF)])
    }
}
