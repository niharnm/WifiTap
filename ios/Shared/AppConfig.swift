import Foundation

/// Build-time configuration from Info.plist (populated by Config/*.xcconfig).
struct AppConfig: Sendable {
    enum CredentialSource: Sendable {
        /// Phase 1b: credentials come from the Supabase backend.
        case backend(TagAPI)
        /// Phase 1a: Debug-only test network from Local.xcconfig, no backend.
        case localTest(WiFiCredentials)
    }

    enum ConfigError: Error, Equatable, Sendable {
        case missing(key: String)
        case invalidURL(key: String)
        case invalidLocalTestNetwork
        case noCredentialSource

        var message: String {
            switch self {
            case .missing(let key): "Build setting \(key) is missing."
            case .invalidURL(let key): "Build setting \(key) must be an https URL."
            case .invalidLocalTestNetwork: "The local test network in Local.xcconfig is invalid."
            case .noCredentialSource: "Set SUPABASE_URL or a local test network in Local.xcconfig."
            }
        }
    }

    let tagBaseURL: URL
    let source: CredentialSource

    static func fromMainBundle() -> Result<AppConfig, ConfigError> {
        Result { () throws(ConfigError) in try load(info: Bundle.main.infoDictionary ?? [:]) }
    }

    static func load(info: [String: Any]) throws(ConfigError) -> AppConfig {
        let tagBaseURL = try httpsURL(info, key: "TagBaseURL")

        if !string(info, "SupabaseURL").isEmpty {
            let projectURL = try httpsURL(info, key: "SupabaseURL")
            let anonKey = string(info, "SupabaseAnonKey")
            guard !anonKey.isEmpty else { throw .missing(key: "SupabaseAnonKey") }
            return AppConfig(tagBaseURL: tagBaseURL, source: .backend(TagAPI(projectURL: projectURL, anonKey: anonKey)))
        }

        let ssid = string(info, "LocalTestSSID")
        guard !ssid.isEmpty else { throw .noCredentialSource }
        guard let security = WiFiSecurity(rawValue: string(info, "LocalTestSecurity")) else {
            throw .invalidLocalTestNetwork
        }
        let password = security == .open ? nil : string(info, "LocalTestPassword")
        do {
            let credentials = try WiFiCredentials(ssid: ssid, password: password, security: security)
            return AppConfig(tagBaseURL: tagBaseURL, source: .localTest(credentials))
        } catch {
            throw .invalidLocalTestNetwork
        }
    }

    private static func string(_ info: [String: Any], _ key: String) -> String {
        (info[key] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
    }

    private static func httpsURL(_ info: [String: Any], key: String) throws(ConfigError) -> URL {
        let value = string(info, key)
        guard !value.isEmpty else { throw .missing(key: key) }
        guard let url = URL(string: value), url.scheme == "https", url.host() != nil else {
            throw .invalidURL(key: key)
        }
        return url
    }
}
