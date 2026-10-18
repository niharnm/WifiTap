import CoreNFC
import Foundation
import Observation

@MainActor
@Observable
final class ProgramTagModel {
    enum Status: Equatable {
        case idle
        case working(String)
        case written(String)
        case failed(String)
    }

    var ssid = ""
    var password = ""
    var security: WiFiSecurity = .wpa2
    var mode: CardMode = .urlAndWifi
    private(set) var status: Status = .idle

    private let config: Result<AppConfig, AppConfig.ConfigError>
    private var writer: TagWriter?
    private var accessToken: String?

    init(config: Result<AppConfig, AppConfig.ConfigError>) {
        self.config = config
    }

    var isWorking: Bool {
        if case .working = status { return true }
        return false
    }

    var usesLocalTestNetwork: Bool {
        if case .success(let appConfig) = config, case .localTest = appConfig.source { return true }
        return false
    }

    var configError: String? {
        if case .failure(let error) = config { return error.message }
        return nil
    }

    func create() async {
        guard !isWorking else { return }
        let appConfig: AppConfig
        switch config {
        case .success(let value): appConfig = value
        case .failure(let error):
            status = .failed(error.message)
            return
        }

        let credentials: WiFiCredentials
        do {
            credentials = try WiFiCredentials(ssid: ssid, password: security == .open ? nil : password, security: security)
        } catch {
            status = .failed(error.message)
            return
        }

        guard NFCNDEFReaderSession.readingAvailable else {
            status = .failed("This iPhone can't write NFC cards.")
            return
        }

        let url: URL
        switch appConfig.source {
        case .localTest:
            url = CardLink.url(base: appConfig.tagBaseURL, token: CardLink.randomToken())
        case .backend(let api):
            status = .working("Saving card")
            do {
                url = try await register(credentials, api: api, base: appConfig.tagBaseURL)
            } catch {
                status = .failed(error.localizedDescription)
                return
            }
        }

        let message: NFCNDEFMessage
        do {
            message = try CardMessage.make(url: url, wifi: mode == .urlAndWifi ? credentials : nil)
        } catch {
            status = .failed("The card URL \(url.absoluteString) is invalid.")
            return
        }

        status = .working("Hold your iPhone near the card")
        let result = await withCheckedContinuation { continuation in
            let writer = TagWriter(message: message) { continuation.resume(returning: $0) }
            self.writer = writer
            writer.begin()
        }
        writer = nil
        switch result {
        case .success(let report):
            let platforms = mode == .urlAndWifi ? "iPhone and Android" : "iPhone"
            status = .written("Card ready for \(platforms). Wrote \(report.bytesWritten) of \(report.capacity) bytes and verified it.")
        case .failure(.cancelled):
            status = .idle
        case .failure(let error):
            status = .failed(error.message)
        }
    }

    private func register(_ credentials: WiFiCredentials, api: TagAPI, base: URL) async throws -> URL {
        let token: String
        if let accessToken {
            token = accessToken
        } else {
            token = try await api.signInAnonymously()
            accessToken = token
        }

        let created: TagAPI.CreatedTag
        do {
            created = try await api.createTag(credentials, mode: mode, accessToken: token)
        } catch TagAPI.APIError.unauthorized {
            accessToken = nil
            throw TagAPI.APIError.unauthorized
        }

        let url = CardLink.url(base: base, token: created.token)
        guard created.url == url else {
            throw TagAPI.APIError.urlMismatch(server: created.url, app: url)
        }
        return url
    }
}
