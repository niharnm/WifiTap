import CoreNFC

/// The NDEF message written to a card: a URL record (iPhone App Clip) and,
/// in `urlAndWifi` mode, a Wi-Fi record that Android joins without an app.
enum CardMessage {
    enum BuildError: Error, Equatable {
        case invalidURL
    }

    static func make(url: URL, wifi: WiFiCredentials?) throws(BuildError) -> NFCNDEFMessage {
        guard let urlRecord = NFCNDEFPayload.wellKnownTypeURIPayload(url: url) else {
            throw .invalidURL
        }
        var records = [urlRecord]
        if let wifi {
            records.append(NFCNDEFPayload(
                format: .media,
                type: Data(WSCRecord.mimeType.utf8),
                identifier: Data(),
                payload: WSCRecord.payload(for: wifi)
            ))
        }
        return NFCNDEFMessage(records: records)
    }

    static func matches(_ lhs: NFCNDEFMessage, _ rhs: NFCNDEFMessage) -> Bool {
        lhs.records.count == rhs.records.count && zip(lhs.records, rhs.records).allSatisfy {
            $0.typeNameFormat == $1.typeNameFormat && $0.type == $1.type && $0.payload == $1.payload
        }
    }
}
