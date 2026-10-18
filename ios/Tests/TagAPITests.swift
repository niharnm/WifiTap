import Foundation
import Testing
@testable import WifiTap

struct TagAPITests {
    private func api(status: Int, body: String, check: (@Sendable (URLRequest) -> Void)? = nil) -> TagAPI {
        TagAPI(projectURL: URL(string: "https://project.supabase.co")!, anonKey: "anon") { request in
            check?(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (Data(body.utf8), response)
        }
    }

    @Test func redeemReturnsCredentials() async throws {
        let api = api(status: 200, body: #"{"ssid":"Guest","password":"guest-password","security":"wpa2"}"#) { request in
            #expect(request.url?.absoluteString == "https://project.supabase.co/functions/v1/redeem-tag?token=AAAAAAAAAAAAAAAAAAAAAA")
            #expect(request.value(forHTTPHeaderField: "apikey") == "anon")
            #expect(request.value(forHTTPHeaderField: "X-Client-Platform") == "ios")
        }
        let credentials = try await api.redeem(token: "AAAAAAAAAAAAAAAAAAAAAA")
        #expect(credentials == (try WiFiCredentials(ssid: "Guest", password: "guest-password", security: .wpa2)))
    }

    @Test func redeemOpenNetworkWithNullPassword() async throws {
        let credentials = try await api(status: 200, body: #"{"ssid":"Cafe","password":null,"security":"open"}"#)
            .redeem(token: "AAAAAAAAAAAAAAAAAAAAAA")
        #expect(credentials.password == nil)
    }

    @Test(arguments: [
        (404, #"{"error":"not_found"}"#, TagAPI.APIError.notFound),
        (410, #"{"error":"revoked"}"#, .revoked),
        (410, #"{"error":"expired"}"#, .expired),
        (429, #"{"error":"rate_limited"}"#, .rateLimited),
        (500, #"{"error":"boom"}"#, .server(status: 500)),
    ])
    func redeemMapsErrors(status: Int, body: String, expected: TagAPI.APIError) async {
        await #expect(throws: expected) {
            try await api(status: status, body: body).redeem(token: "AAAAAAAAAAAAAAAAAAAAAA")
        }
    }

    @Test func createTagSendsBodyAndAuth() async throws {
        let api = api(status: 201, body: #"{"id":"7C9E6679-7425-40DE-944B-E07FC1F90AE7","token":"AAAAAAAAAAAAAAAAAAAAAA","url":"https://tap.example.com/t/AAAAAAAAAAAAAAAAAAAAAA"}"#) { request in
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer user-jwt")
            let body = (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: String]
            #expect(body == ["ssid": "Guest", "password": "guest-password", "security": "wpa2", "mode": "url_and_wifi"])
        }
        let credentials = try WiFiCredentials(ssid: "Guest", password: "guest-password", security: .wpa2)
        let created = try await api.createTag(credentials, mode: .urlAndWifi, accessToken: "user-jwt")
        #expect(created.token == "AAAAAAAAAAAAAAAAAAAAAA")
    }

    @Test func createTagUnauthorized() async throws {
        let credentials = try WiFiCredentials(ssid: "Guest", password: "guest-password", security: .wpa2)
        await #expect(throws: TagAPI.APIError.unauthorized) {
            try await api(status: 401, body: "{}").createTag(credentials, mode: .urlOnly, accessToken: "expired")
        }
    }
}
