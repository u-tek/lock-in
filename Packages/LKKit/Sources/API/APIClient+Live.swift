import Core
import Foundation
import Model

// The live view of a session: `GET /sessions/:id/live`, a WebSocket (docs/milestones/M3.md).
//
// The room sends `{"type":"state","status","contentState"}` on connecting and right after every
// change, and closes the socket with 1000 once the room has ended. The app pings it with
// `{"type":"ping"}` every 30 seconds so idle connections aren't dropped along the way.

extension APIClient {
    /// How often the live view pings the room.
    static let livePingInterval: Duration = .seconds(30)

    public func liveUpdates(sessionId: String) -> AsyncThrowingStream<LiveMessage, any Error> {
        let request: URLRequest
        do {
            request = try liveRequest(sessionId: sessionId)
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }
        let socket = session.webSocketTask(with: request)
        return AsyncThrowingStream { continuation in
            let pinger = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: Self.livePingInterval)
                    guard !Task.isCancelled else { return }
                    try? await socket.send(.string(LiveMessage.ping))
                }
            }
            let reader = Task {
                defer { pinger.cancel() }
                do {
                    while !Task.isCancelled {
                        let frame = try await socket.receive()
                        guard let message = Self.liveMessage(from: frame) else { continue }
                        continuation.yield(message)
                        if message.isEnded {
                            // The room closes the socket after this; nothing more will come.
                            socket.cancel(with: .normalClosure, reason: nil)
                            break
                        }
                    }
                    continuation.finish()
                } catch {
                    if let failure = Self.liveFailure(error, closeCode: socket.closeCode, response: socket.response) {
                        Log.api.info("GET /sessions live view closed")
                        continuation.finish(throwing: failure)
                    } else {
                        continuation.finish()
                    }
                }
            }
            // The consumer stopped (or the stream finished): close the connection.
            continuation.onTermination = { _ in
                reader.cancel()
                pinger.cancel()
                socket.cancel(with: .goingAway, reason: nil)
            }
            socket.resume()
        }
    }

    /// The WebSocket handshake for a session's live view: `wss://` (URLSession's WebSocket tasks
    /// take only `ws` and `wss`), with the bearer token.
    func liveRequest(sessionId: String) throws -> URLRequest {
        var request = try self.request(.get, ["sessions", sessionId, "live"])
        guard let url = request.url, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw APIError.notConfigured
        }
        switch components.scheme?.lowercased() {
        case "https": components.scheme = "wss"
        case "http": components.scheme = "ws"
        default: break
        }
        request.url = components.url
        return request
    }

    /// One frame as a message: text or binary JSON. Nil for anything the live view skips.
    static func liveMessage(from frame: URLSessionWebSocketTask.Message) -> LiveMessage? {
        switch frame {
        case .string(let text):
            return LiveMessage(text: text)
        case .data(let data):
            return LiveMessage(json: data)
        @unknown default:
            return nil
        }
    }

    /// Why the live view stopped, as the error the stream ends with; nil for a normal close
    /// (the room closes with 1000 once it has ended).
    static func liveFailure(
        _ error: any Error,
        closeCode: URLSessionWebSocketTask.CloseCode,
        response: URLResponse?
    ) -> (any Error)? {
        if closeCode == .normalClosure {
            return nil
        }
        // The handshake was turned down: 401, 403 `not_member`, 404 `session_not_found`, …
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            return APIError(status: http.statusCode, body: Data())
        }
        if let urlError = error as? URLError {
            // Nil for a cancelled task: the consumer stopped listening.
            if let failure = APIError(urlError) {
                return failure
            }
            return CancellationError()
        }
        if error is CancellationError {
            return error
        }
        return APIError.network(code: URLError.Code.unknown.rawValue)
    }
}
