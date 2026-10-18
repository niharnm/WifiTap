import Foundation
import Testing
@testable import WifiTap

struct WiFiCredentialsTests {
    @Test func acceptsValidNetworks() throws {
        #expect(try WiFiCredentials(ssid: "Guest", password: "12345678", security: .wpa2).password == "12345678")
        #expect(try WiFiCredentials(ssid: "Cafe", password: "", security: .open).password == nil)
    }

    @Test(arguments: [
        ("", "password1", WiFiSecurity.wpa2, WiFiCredentials.ValidationError.ssidEmpty),
        (String(repeating: "a", count: 33), "password1", .wpa2, .ssidTooLong),
        ("Guest", "", .wpa2, .passwordRequired),
        ("Guest", "short", .wpa2, .passwordInvalid),
        ("Guest", String(repeating: "a", count: 64), .wpa2, .passwordInvalid),
        ("Guest", "pässword1", .wpa2, .passwordInvalid),
        ("Cafe", "password1", .open, .passwordNotAllowed),
    ])
    func rejectsInvalidNetworks(ssid: String, password: String, security: WiFiSecurity, expected: WiFiCredentials.ValidationError) {
        #expect(throws: expected) {
            try WiFiCredentials(ssid: ssid, password: password, security: security)
        }
    }

    @Test func ssidLimitCountsBytesNotCharacters() {
        // 11 three-byte characters = 33 bytes.
        #expect(throws: WiFiCredentials.ValidationError.ssidTooLong) {
            try WiFiCredentials(ssid: String(repeating: "あ", count: 11), password: nil, security: .open)
        }
    }

    @Test func decodingValidates() {
        let json = Data(#"{"ssid":"Guest","password":"short","security":"wpa2"}"#.utf8)
        #expect(throws: WiFiCredentials.ValidationError.passwordInvalid) {
            try JSONDecoder().decode(WiFiCredentials.self, from: json)
        }
    }
}

struct CardLinkTests {
    let base = URL(string: "https://tap.example.com")!

    @Test func roundTripsToken() {
        let token = CardLink.randomToken()
        #expect(CardLink.isValidToken(token))
        let url = CardLink.url(base: base, token: token)
        #expect(url.absoluteString == "https://tap.example.com/t/\(token)")
        #expect(CardLink.token(from: url) == token)
    }

    @Test func randomTokensAreUnique() {
        let tokens = Set((0..<200).map { _ in CardLink.randomToken() })
        #expect(tokens.count == 200)
    }

    @Test(arguments: [
        "http://tap.example.com/t/AAAAAAAAAAAAAAAAAAAAAA",
        "https://tap.example.com/x/AAAAAAAAAAAAAAAAAAAAAA",
        "https://tap.example.com/t/short",
        "https://tap.example.com/t/AAAAAAAAAAAAAAAAAAAAA+",
        "https://tap.example.com/t/AAAAAAAAAAAAAAAAAAAAAA/extra",
    ])
    func rejectsMalformedLinks(link: String) throws {
        #expect(CardLink.token(from: try #require(URL(string: link))) == nil)
    }
}

struct AppConfigTests {
    let base: [String: Any] = ["TagBaseURL": "https://tap.example.com"]

    @Test func backendWhenSupabaseIsSet() throws {
        var info = base
        info["SupabaseURL"] = "https://project.supabase.co"
        info["SupabaseAnonKey"] = "anon"
        info["LocalTestSSID"] = "Guest"
        guard case .backend(let api) = try AppConfig.load(info: info).source else {
            Issue.record("Expected backend source")
            return
        }
        #expect(api.projectURL.absoluteString == "https://project.supabase.co")
    }

    @Test func localTestNetworkWithoutBackend() throws {
        var info = base
        info["LocalTestSSID"] = "Guest"
        info["LocalTestPassword"] = "guest-password"
        info["LocalTestSecurity"] = "wpa2"
        guard case .localTest(let network) = try AppConfig.load(info: info).source else {
            Issue.record("Expected local test source")
            return
        }
        #expect(network.ssid == "Guest")
    }

    @Test func failsWithoutAnyCredentialSource() {
        #expect(throws: AppConfig.ConfigError.noCredentialSource) {
            try AppConfig.load(info: base)
        }
    }

    @Test func rejectsUnexpandedXcconfigURL() {
        // "https://host" in an xcconfig is cut at "//" unless written as https:/$()/host.
        #expect(throws: AppConfig.ConfigError.invalidURL(key: "TagBaseURL")) {
            try AppConfig.load(info: ["TagBaseURL": "https:"])
        }
    }

    @Test func requiresAnonKeyWithSupabase() {
        var info = base
        info["SupabaseURL"] = "https://project.supabase.co"
        #expect(throws: AppConfig.ConfigError.missing(key: "SupabaseAnonKey")) {
            try AppConfig.load(info: info)
        }
    }
}
