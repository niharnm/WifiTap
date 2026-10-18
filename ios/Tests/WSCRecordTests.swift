import Foundation
import Testing
@testable import WifiTap

struct WSCRecordTests {
    @Test func encodesWPA2CredentialByteExact() throws {
        let credentials = try WiFiCredentials(ssid: "Guest", password: "password123", security: .wpa2)
        let expected = hex("""
            104A 0001 10
            100E 0033
              1026 0001 01
              1045 0005 4775657374
              1003 0002 0020
              100F 0002 0008
              1027 000B 70617373776F7264313233
              1020 0006 FFFFFFFFFFFF
            """)
        #expect(WSCRecord.payload(for: credentials) == expected)
    }

    @Test func encodesOpenNetworkWithoutNetworkKey() throws {
        let credentials = try WiFiCredentials(ssid: "Cafe", password: nil, security: .open)
        let expected = hex("""
            104A 0001 10
            100E 0023
              1026 0001 01
              1045 0004 43616665
              1003 0002 0001
              100F 0002 0001
              1020 0006 FFFFFFFFFFFF
            """)
        #expect(WSCRecord.payload(for: credentials) == expected)
    }

    @Test func androidParserAcceptsWPA2Payload() throws {
        let credentials = try WiFiCredentials(ssid: "Home Guest 5G", password: "correct horse battery", security: .wpa2)
        let parsed = try #require(AOSPWifiParser.parse(WSCRecord.payload(for: credentials)))
        #expect(parsed.ssid == "Home Guest 5G")
        #expect(parsed.networkKey == "correct horse battery")
        #expect(parsed.authType == 0x0020)
    }

    @Test func androidParserAcceptsOpenPayload() throws {
        let credentials = try WiFiCredentials(ssid: "Cafe", password: nil, security: .open)
        let parsed = try #require(AOSPWifiParser.parse(WSCRecord.payload(for: credentials)))
        #expect(parsed.ssid == "Cafe")
        #expect(parsed.networkKey == nil)
        #expect(parsed.authType == 0x0001)
    }

    @Test func androidParserAcceptsLongestValues() throws {
        let ssid = String(repeating: "S", count: 32)
        let password = String(repeating: "p", count: 63)
        let credentials = try WiFiCredentials(ssid: ssid, password: password, security: .wpa2)
        let parsed = try #require(AOSPWifiParser.parse(WSCRecord.payload(for: credentials)))
        #expect(parsed.ssid == ssid)
        #expect(parsed.networkKey == password)
    }
}

/// Mirrors the parse and parseCredential logic of AOSP's NfcWifiProtectedSetup
/// (packages/modules/Nfc), so tests check what Android's NFC service accepts.
enum AOSPWifiParser {
    struct Result {
        var ssid: String?
        var networkKey: String?
        var authType: UInt16?
    }

    static func parse(_ payload: Data) -> Result? {
        var reader = Reader(bytes: [UInt8](payload))
        while reader.hasRemaining {
            guard let field = reader.uint16(), let size = reader.uint16() else { return nil }
            if field == 0x100E { return parseCredential(&reader, size: Int(size)) }
            reader.skip(Int(size))
        }
        return nil
    }

    private static func parseCredential(_ reader: inout Reader, size: Int) -> Result? {
        let end = reader.position + size
        var result = Result()
        while reader.position < end {
            guard let field = reader.uint16(), let fieldSize = reader.uint16().map(Int.init) else { return nil }
            guard reader.position + fieldSize <= end else { return nil }
            switch field {
            case 0x1045:
                result.ssid = String(decoding: reader.take(fieldSize), as: UTF8.self)
            case 0x1027:
                guard fieldSize <= 64 else { return nil }
                let key = reader.take(fieldSize)
                if fieldSize > 0 { result.networkKey = String(decoding: key, as: UTF8.self) }
            case 0x1003:
                guard fieldSize == 2, let auth = reader.uint16() else { return nil }
                result.authType = auth
            default:
                reader.skip(fieldSize)
            }
        }
        guard result.ssid != nil else { return nil }
        let isOpen = result.authType == 0x0001
        return isOpen == (result.networkKey == nil) ? result : nil
    }

    private struct Reader {
        let bytes: [UInt8]
        var position = 0

        var hasRemaining: Bool { position < bytes.count }

        mutating func uint16() -> UInt16? {
            guard position + 2 <= bytes.count else { return nil }
            defer { position += 2 }
            return UInt16(bytes[position]) << 8 | UInt16(bytes[position + 1])
        }

        mutating func take(_ count: Int) -> [UInt8] {
            defer { position += count }
            return Array(bytes[position..<position + count])
        }

        mutating func skip(_ count: Int) {
            position += count
        }
    }
}

func hex(_ string: String) -> Data {
    let digits = string.filter(\.isHexDigit)
    var data = Data()
    var index = digits.startIndex
    while index < digits.endIndex {
        let next = digits.index(index, offsetBy: 2)
        data.append(UInt8(digits[index..<next], radix: 16)!)
        index = next
    }
    return data
}
