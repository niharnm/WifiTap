import Foundation

/// Client for the Supabase edge functions `create-tag` and `redeem-tag`.
struct TagAPI: Sendable {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    enum APIError: Error, Equatable, LocalizedError {
        case notFound
        case revoked
        case expired
        case rateLimited
        case unauthorized
        case invalidResponse
        case server(status: Int)
        case urlMismatch(server: URL, app: URL)

        var errorDescription: String? {
            switch self {
            case .notFound: "This card isn't set up."
            case .revoked: "This card was turned off by its owner."
            case .expired: "This card has expired."
            case .rateLimited: "This card was tapped too many times. Try again in a few minutes."
            case .unauthorized: "Your session expired. Try again."
            case .invalidResponse: "The server sent an unexpected response."
            case .server(let status): "The server returned an error (\(status))."
            case .urlMismatch(let server, let app):
                "The server's card URL (\(server.absoluteString)) doesn't match this app's domain (\(app.absoluteString))."
            }
        }
    }

    struct CreatedTag: Decodable, Equatable, Sendable {
        let id: UUID
        let token: String
        let url: URL
    }

    let projectURL: URL
    let anonKey: String
    private let transport: Transport

    init(
        projectURL: URL,
        anonKey: String,
        transport: @escaping Transport = { try await URLSession.shared.data(for: $0) }
    ) {
        self.projectURL = projectURL
        self.anonKey = anonKey
        self.transport = transport
    }

    func redeem(token: String) async throws -> WiFiCredentials {
        let url = projectURL
            .appending(path: "functions/v1/redeem-tag")
            .appending(queryItems: [URLQueryItem(name: "token", value: token)])
        var request = URLRequest(url: url)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("ios", forHTTPHeaderField: "X-Client-Platform")

        let (data, status) = try await send(request)
        switch status {
        case 200:
            return try JSONDecoder().decode(WiFiCredentials.self, from: data)
        case 404:
            throw APIError.notFound
        case 410:
            switch try JSONDecoder().decode(ErrorBody.self, from: data).error {
            case "revoked": throw APIError.revoked
            case "expired": throw APIError.expired
            default: throw APIError.server(status: status)
            }
        case 429:
            throw APIError.rateLimited
        default:
            throw APIError.server(status: status)
        }
    }

    /// Supabase anonymous sign-in. Phase 2 replaces this with Sign in with Apple.
    func signInAnonymously() async throws -> String {
        var request = URLRequest(url: projectURL.appending(path: "auth/v1/signup"))
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)

        let (data, status) = try await send(request)
        guard status == 200 else { throw APIError.server(status: status) }
        return try JSONDecoder().decode(AuthSession.self, from: data).accessToken
    }

    func createTag(_ credentials: WiFiCredentials, mode: CardMode, accessToken: String) async throws -> CreatedTag {
        var request = URLRequest(url: projectURL.appending(path: "functions/v1/create-tag"))
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(CreateBody(
            ssid: credentials.ssid,
            password: credentials.password,
            security: credentials.security,
            mode: mode
        ))

        let (data, status) = try await send(request)
        switch status {
        case 201: return try JSONDecoder().decode(CreatedTag.self, from: data)
        case 401: throw APIError.unauthorized
        default: throw APIError.server(status: status)
        }
    }

    private func send(_ request: URLRequest) async throws -> (Data, Int) {
        let (data, response) = try await transport(request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        return (data, http.statusCode)
    }

    private struct ErrorBody: Decodable {
        let error: String
    }

    private struct AuthSession: Decodable {
        let accessToken: String

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
        }
    }

    private struct CreateBody: Encodable {
        let ssid: String
        let password: String?
        let security: WiFiSecurity
        let mode: CardMode
    }
}
