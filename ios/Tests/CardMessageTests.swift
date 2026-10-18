import CoreNFC
import Foundation
import Testing
@testable import WifiTap

struct CardMessageTests {
    let url = URL(string: "https://tap.example.com/t/AAAAAAAAAAAAAAAAAAAAAA")!

    @Test func urlAndWifiModeHasURLFirstThenWifiRecord() throws {
        let credentials = try WiFiCredentials(ssid: "Guest", password: "guest-password", security: .wpa2)
        let message = try CardMessage.make(url: url, wifi: credentials)

        #expect(message.records.count == 2)
        let uri = message.records[0]
        #expect(uri.typeNameFormat == .nfcWellKnown)
        #expect(uri.type == Data("U".utf8))
        // 0x04 is the NDEF URI prefix code for "https://".
        #expect(uri.payload == Data([0x04]) + Data("tap.example.com/t/AAAAAAAAAAAAAAAAAAAAAA".utf8))

        let wifi = message.records[1]
        #expect(wifi.typeNameFormat == .media)
        #expect(wifi.type == Data("application/vnd.wfa.wsc".utf8))
        #expect(wifi.payload == WSCRecord.payload(for: credentials))
    }

    @Test func urlOnlyModeHasNoPasswordOnCard() throws {
        let message = try CardMessage.make(url: url, wifi: nil)
        #expect(message.records.count == 1)
        #expect(!message.records[0].payload.contains(Data("guest-password".utf8)))
    }

    @Test func worstCaseFitsNTAG215ButNotNTAG213() throws {
        let credentials = try WiFiCredentials(
            ssid: String(repeating: "S", count: 32),
            password: String(repeating: "p", count: 63),
            security: .wpa2
        )
        let message = try CardMessage.make(url: url, wifi: credentials)
        // NXP user memory: NTAG213 144 bytes, NTAG215 504 bytes.
        // The card also stores an NDEF TLV header and terminator (up to 5 bytes).
        #expect(message.length > 144)
        #expect(message.length + 5 <= 504)
    }

    @Test func matchesComparesRecordContents() throws {
        let a = try CardMessage.make(url: url, wifi: nil)
        let b = try CardMessage.make(url: url, wifi: nil)
        let other = try CardMessage.make(url: URL(string: "https://tap.example.com/t/BBBBBBBBBBBBBBBBBBBBBB")!, wifi: nil)
        #expect(CardMessage.matches(a, b))
        #expect(!CardMessage.matches(a, other))
    }
}
