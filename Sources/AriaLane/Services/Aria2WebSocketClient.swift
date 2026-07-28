import Foundation

actor Aria2WebSocketClient {
    typealias EventHandler = @MainActor @Sendable (Aria2NotificationEvent) -> Void
    typealias StateHandler = @MainActor @Sendable (Aria2EventStreamState) -> Void

    private struct AuthenticationRequest: Encodable {
        let jsonrpc = "2.0"
        let id = "arialane-events"
        let method = "aria2.getVersion"
        let params: [String]
    }

    private struct EventParameter: Decodable {
        let gid: String
    }

    private struct EventEnvelope: Decodable {
        let method: String?
        let params: [EventParameter]?
    }

    private var loopTask: Task<Void, Never>?
    private var socket: URLSessionWebSocketTask?
    private var generation = 0

    func connect(
        endpoint: URL?,
        secret: String,
        onEvent: @escaping EventHandler,
        onStateChange: @escaping StateHandler
    ) {
        cancelConnection()
        generation += 1
        let currentGeneration = generation

        guard let endpoint, let webSocketURL = Self.webSocketURL(from: endpoint) else {
            Task { @MainActor in
                onStateChange(.disabled)
            }
            return
        }

        loopTask = Task { [weak self] in
            await self?.runConnectionLoop(
                endpoint: webSocketURL,
                secret: secret,
                generation: currentGeneration,
                onEvent: onEvent,
                onStateChange: onStateChange
            )
        }
    }

    func disconnect() {
        generation += 1
        cancelConnection()
    }

    private func cancelConnection() {
        loopTask?.cancel()
        loopTask = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
    }

    private func runConnectionLoop(
        endpoint: URL,
        secret: String,
        generation expectedGeneration: Int,
        onEvent: @escaping EventHandler,
        onStateChange: @escaping StateHandler
    ) async {
        var retryDelaySeconds = 2

        while !Task.isCancelled, expectedGeneration == generation {
            await onStateChange(.connecting)
            let nextSocket = URLSession.shared.webSocketTask(with: endpoint)
            socket = nextSocket
            nextSocket.resume()

            do {
                let request = AuthenticationRequest(
                    params: secret.isEmpty ? [] : ["token:\(secret)"]
                )
                let requestData = try JSONEncoder().encode(request)
                guard let requestText = String(data: requestData, encoding: .utf8) else {
                    throw Aria2ClientError.invalidResponse
                }
                try await nextSocket.send(.string(requestText))
                await onStateChange(.connected)
                retryDelaySeconds = 2

                while !Task.isCancelled, expectedGeneration == generation {
                    let message = try await nextSocket.receive()
                    guard let event = try Self.decodeEvent(message) else { continue }
                    await onEvent(event)
                }
            } catch {
                if !Task.isCancelled, expectedGeneration == generation {
                    await onStateChange(
                        .disconnected(message: error.localizedDescription)
                    )
                }
            }

            nextSocket.cancel(with: .goingAway, reason: nil)
            if socket === nextSocket {
                socket = nil
            }
            guard !Task.isCancelled, expectedGeneration == generation else { break }

            try? await Task.sleep(for: .seconds(retryDelaySeconds))
            retryDelaySeconds = min(retryDelaySeconds * 2, 30)
        }
    }

    private static func decodeEvent(
        _ message: URLSessionWebSocketTask.Message
    ) throws -> Aria2NotificationEvent? {
        let data: Data
        switch message {
        case .data(let value):
            data = value
        case .string(let value):
            data = Data(value.utf8)
        @unknown default:
            return nil
        }

        let envelope = try JSONDecoder().decode(EventEnvelope.self, from: data)
        guard let methodName = envelope.method,
              let method = Aria2NotificationMethod(rawValue: methodName),
              let gid = envelope.params?.first?.gid,
              !gid.isEmpty else {
            return nil
        }
        return Aria2NotificationEvent(method: method, gid: gid)
    }

    nonisolated static func webSocketURL(from endpoint: URL) -> URL? {
        guard var components = URLComponents(
            url: endpoint,
            resolvingAgainstBaseURL: false
        ) else {
            return nil
        }
        switch components.scheme?.lowercased() {
        case "http", "ws":
            components.scheme = "ws"
        case "https", "wss":
            components.scheme = "wss"
        default:
            return nil
        }
        if components.path.isEmpty || components.path == "/" {
            components.path = "/jsonrpc"
        }
        return components.url
    }
}
