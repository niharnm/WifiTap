import Foundation
import Observation

/// Handles a card tap: card URL -> credentials -> iOS Wi-Fi join request.
@MainActor
@Observable
final class JoinModel {
    enum State: Equatable {
        case waiting
        case fetching
        case joining(ssid: String)
        case requested(ssid: String)
        case alreadyConnected(ssid: String)
        case declined(ssid: String)
        case unavailable(String)
        case failed(String)
    }

    private(set) var state: State = .waiting
    private(set) var usesLocalTestNetwork = false
    private let config: Result<AppConfig, AppConfig.ConfigError>

    init(config: Result<AppConfig, AppConfig.ConfigError>) {
        self.config = config
    }

    func handle(url: URL) async {
        switch state {
        case .fetching, .joining: return
        default: break
        }

        guard let token = CardLink.token(from: url) else {
            state = .unavailable("This link isn't a Wi-Fi card.")
            return
        }

        let appConfig: AppConfig
        switch config {
        case .success(let value): appConfig = value
        case .failure(let error):
            state = .failed(error.message)
            return
        }

        let credentials: WiFiCredentials
        switch appConfig.source {
        case .localTest(let testNetwork):
            usesLocalTestNetwork = true
            credentials = testNetwork
        case .backend(let api):
            state = .fetching
            do {
                credentials = try await api.redeem(token: token)
            } catch let error as TagAPI.APIError {
                switch error {
                case .notFound, .revoked, .expired, .rateLimited:
                    state = .unavailable(error.errorDescription ?? "This card is unavailable.")
                default:
                    state = .failed(error.errorDescription ?? "Something went wrong.")
                }
                return
            } catch {
                state = .failed(error.localizedDescription)
                return
            }
        }

        state = .joining(ssid: credentials.ssid)
        do {
            switch try await WiFiJoiner.join(credentials) {
            case .requested: state = .requested(ssid: credentials.ssid)
            case .alreadyConnected: state = .alreadyConnected(ssid: credentials.ssid)
            case .declined: state = .declined(ssid: credentials.ssid)
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
