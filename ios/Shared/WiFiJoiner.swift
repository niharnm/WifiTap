import NetworkExtension

enum WiFiJoiner {
    enum Outcome: Equatable, Sendable {
        /// iOS accepted the configuration and showed (or skipped) its join prompt.
        /// iOS does not tell the caller whether the join itself succeeded.
        case requested
        case alreadyConnected
        case declined
    }

    static func join(_ credentials: WiFiCredentials) async throws -> Outcome {
        let configuration: NEHotspotConfiguration
        switch credentials.security {
        case .open:
            configuration = NEHotspotConfiguration(ssid: credentials.ssid)
        case .wpa2:
            guard let password = credentials.password else {
                throw WiFiCredentials.ValidationError.passwordRequired
            }
            configuration = NEHotspotConfiguration(ssid: credentials.ssid, passphrase: password, isWEP: false)
        }
        // Keep the network saved so the guest reconnects later without the card.
        configuration.joinOnce = false

        do {
            try await NEHotspotConfigurationManager.shared.apply(configuration)
            return .requested
        } catch let error as NSError where error.domain == NEHotspotConfigurationErrorDomain {
            switch NEHotspotConfigurationError(rawValue: error.code) {
            case .alreadyAssociated: return .alreadyConnected
            case .userDenied: return .declined
            default: throw error
            }
        }
    }
}
