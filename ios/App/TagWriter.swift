@preconcurrency import CoreNFC
import os

struct WriteReport: Equatable, Sendable {
    let bytesWritten: Int
    let capacity: Int
}

enum TagWriteError: Error, Equatable, Sendable {
    case cancelled
    case multipleCards
    case notWritable
    case readOnly
    case tooSmall(needed: Int, capacity: Int)
    case verificationFailed
    case nfc(String)

    var message: String {
        switch self {
        case .cancelled: "Cancelled."
        case .multipleCards: "More than one card was detected. Hold a single card to the phone."
        case .notWritable: "This card can't store NFC data. Use an NTAG215 or NTAG216 card."
        case .readOnly: "This card is locked and can't be rewritten."
        case .tooSmall(let needed, let capacity):
            "This card holds \(capacity) bytes but needs \(needed). Use an NTAG215 or NTAG216 card, or choose Link only."
        case .verificationFailed: "The card didn't read back correctly. Try again."
        case .nfc(let detail): detail
        }
    }
}

/// One write attempt: write the message, read it back, compare, then report once.
///
/// CoreNFC predates Swift concurrency and calls back on its own queue, so this type
/// is `@unchecked Sendable`. CoreNFC objects are only used inside CoreNFC callbacks,
/// `session` is set once in `begin()` before any callback, and `completion` is
/// guarded by a lock.
final class TagWriter: NSObject, NFCNDEFReaderSessionDelegate, @unchecked Sendable {
    typealias Completion = @MainActor @Sendable (Result<WriteReport, TagWriteError>) -> Void

    private let message: NFCNDEFMessage
    private let completion: OSAllocatedUnfairLock<Completion?>
    private var session: NFCNDEFReaderSession?

    init(message: NFCNDEFMessage, completion: @escaping Completion) {
        self.message = message
        self.completion = OSAllocatedUnfairLock(initialState: completion)
    }

    func begin() {
        let session = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: false)
        session.alertMessage = "Hold the top of your iPhone near the card."
        self.session = session
        session.begin()
    }

    func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        // Unused: didDetect(tags:) handles detection so the tag can be written.
    }

    func readerSession(_ session: NFCNDEFReaderSession, didDetect tags: [any NFCNDEFTag]) {
        guard tags.count == 1, let first = tags.first else {
            return fail(session, .multipleCards)
        }
        // Each CoreNFC callback below starts only after the previous one finished,
        // so these objects are never used concurrently.
        nonisolated(unsafe) let session = session
        nonisolated(unsafe) let tag = first
        nonisolated(unsafe) let message = message

        session.connect(to: tag) { error in
            if let error { return self.fail(session, .nfc(error.localizedDescription)) }

            tag.queryNDEFStatus { status, capacity, error in
                if let error { return self.fail(session, .nfc(error.localizedDescription)) }
                switch status {
                case .readWrite: break
                case .readOnly: return self.fail(session, .readOnly)
                case .notSupported: return self.fail(session, .notWritable)
                @unknown default: return self.fail(session, .notWritable)
                }
                guard message.length <= capacity else {
                    return self.fail(session, .tooSmall(needed: message.length, capacity: capacity))
                }

                tag.writeNDEF(message) { error in
                    if let error { return self.fail(session, .nfc(error.localizedDescription)) }

                    tag.readNDEF { readBack, error in
                        guard error == nil, let readBack, CardMessage.matches(readBack, message) else {
                            return self.fail(session, .verificationFailed)
                        }
                        session.alertMessage = "Card written and verified."
                        self.finish(.success(WriteReport(bytesWritten: message.length, capacity: capacity)))
                        session.invalidate()
                    }
                }
            }
        }
    }

    func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: any Error) {
        if (error as? NFCReaderError)?.code == .readerSessionInvalidationErrorUserCanceled {
            finish(.failure(.cancelled))
        } else {
            finish(.failure(.nfc(error.localizedDescription)))
        }
    }

    private func fail(_ session: NFCNDEFReaderSession, _ error: TagWriteError) {
        session.invalidate(errorMessage: error.message)
        finish(.failure(error))
    }

    /// Reports once; the invalidation callback that ends every session is then ignored.
    private func finish(_ result: Result<WriteReport, TagWriteError>) {
        let pending = completion.withLock { completion in
            defer { completion = nil }
            return completion
        }
        guard let pending else { return }
        Task { @MainActor in pending(result) }
    }
}
