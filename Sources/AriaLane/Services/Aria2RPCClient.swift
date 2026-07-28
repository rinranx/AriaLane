import Foundation

private indirect enum JSONValue: Encodable, Sendable {
    case string(String)
    case integer(Int)
    case boolean(Bool)
    case array([JSONValue])
    case object([String: JSONValue])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .integer(let value):
            try container.encode(value)
        case .boolean(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }
}

private struct RPCRequest: Encodable {
    let jsonrpc = "2.0"
    let id: String
    let method: String
    let params: [JSONValue]
}

private struct RPCErrorPayload: Decodable {
    let code: Int
    let message: String
}

private struct RPCResponse<Result: Decodable>: Decodable {
    let result: Result?
    let error: RPCErrorPayload?
}

private indirect enum RPCDecodedValue: Decodable {
    case string(String)
    case integer(Int)
    case boolean(Bool)
    case array([RPCDecodedValue])
    case object([String: RPCDecodedValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Int.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .boolean(value)
        } else if let value = try? container.decode([RPCDecodedValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: RPCDecodedValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON-RPC result value"
            )
        }
    }

    var integerValue: Int? {
        if case .integer(let value) = self {
            return value
        }
        return nil
    }

    var stringValue: String? {
        if case .string(let value) = self {
            return value
        }
        return nil
    }
}

enum Aria2ClientError: LocalizedError {
    case invalidEndpoint
    case invalidResponse
    case httpStatus(Int)
    case rpc(code: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            L10n.string("RPC 地址无效")
        case .invalidResponse:
            L10n.string("aria2 返回了无法识别的数据")
        case .httpStatus(let status):
            L10n.string("RPC 服务返回 HTTP \(status)")
        case .rpc(_, let message):
            message
        }
    }
}

actor Aria2RPCClient {
    private var endpoint: URL?
    private var secret = ""
    private var requestID = 0
    private let session: URLSession

    private let taskKeys = [
        "gid",
        "status",
        "totalLength",
        "completedLength",
        "uploadLength",
        "downloadSpeed",
        "uploadSpeed",
        "dir",
        "connections",
        "numSeeders",
        "seeder",
        "pieceLength",
        "numPieces",
        "bitfield",
        "verifiedLength",
        "verifyIntegrityPending",
        "infoHash",
        "errorCode",
        "errorMessage",
        "files",
        "bittorrent"
    ]

    init(session: URLSession = .shared) {
        self.session = session
    }

    func configure(endpoint: URL?, secret: String) {
        self.endpoint = endpoint
        self.secret = secret
    }

    func version() async throws -> Aria2Version {
        try await call(method: "aria2.getVersion")
    }

    func activeTransfers() async throws -> [TransferItem] {
        try await call(
            method: "aria2.tellActive",
            params: [.array(taskKeys.map(JSONValue.string))]
        )
    }

    func waitingTransfers() async throws -> [TransferItem] {
        try await call(
            method: "aria2.tellWaiting",
            params: [
                .integer(0),
                .integer(1_000),
                .array(taskKeys.map(JSONValue.string))
            ]
        )
    }

    func stoppedTransfers() async throws -> [TransferItem] {
        try await call(
            method: "aria2.tellStopped",
            params: [
                .integer(0),
                .integer(1_000),
                .array(taskKeys.map(JSONValue.string))
            ]
        )
    }

    func globalStats() async throws -> GlobalStats {
        try await call(method: "aria2.getGlobalStat")
    }

    func add(uri: String, directory: String) async throws -> String {
        let options: [String: String] = directory.trimmed.isEmpty
            ? [:]
            : ["dir": directory]
        return try await add(uris: [uri], options: options)
    }

    func add(
        uri: String,
        options: [String: String],
        headers: [String] = []
    ) async throws -> String {
        try await add(uris: [uri], options: options, headers: headers)
    }

    func add(
        uris: [String],
        options: [String: String],
        headers: [String] = []
    ) async throws -> String {
        guard !uris.isEmpty else {
            throw Aria2ClientError.invalidResponse
        }
        var encodedOptions = options.mapValues(JSONValue.string)
        if !headers.isEmpty {
            encodedOptions["header"] = .array(headers.map(JSONValue.string))
        }

        return try await call(
            method: "aria2.addUri",
            params: [
                .array(uris.map(JSONValue.string)),
                .object(encodedOptions)
            ]
        )
    }

    func addTorrent(
        data: Data,
        webSeedURIs: [String] = [],
        options: [String: String]
    ) async throws -> String {
        try await call(
            method: "aria2.addTorrent",
            params: [
                .string(data.base64EncodedString()),
                .array(webSeedURIs.map(JSONValue.string)),
                .object(options.mapValues(JSONValue.string))
            ]
        )
    }

    func addMetalink(data: Data, options: [String: String]) async throws -> [String] {
        try await call(
            method: "aria2.addMetalink",
            params: [
                .string(data.base64EncodedString()),
                .object(options.mapValues(JSONValue.string))
            ]
        )
    }

    func status(gid: String) async throws -> TransferItem {
        try await call(
            method: "aria2.tellStatus",
            params: [
                .string(gid),
                .array(taskKeys.map(JSONValue.string))
            ]
        )
    }

    func files(gid: String) async throws -> [TransferFile] {
        try await call(
            method: "aria2.getFiles",
            params: [.string(gid)]
        )
    }

    func uris(gid: String) async throws -> [TransferURI] {
        try await call(
            method: "aria2.getUris",
            params: [.string(gid)]
        )
    }

    func peers(gid: String) async throws -> [Aria2Peer] {
        try await call(
            method: "aria2.getPeers",
            params: [.string(gid)]
        )
    }

    func servers(gid: String) async throws -> [Aria2ServerGroup] {
        try await call(
            method: "aria2.getServers",
            params: [.string(gid)]
        )
    }

    func pause(gid: String) async throws {
        let _: String = try await call(method: "aria2.pause", params: [.string(gid)])
    }

    func forcePause(gid: String) async throws {
        let _: String = try await call(
            method: "aria2.forcePause",
            params: [.string(gid)]
        )
    }

    func resume(gid: String) async throws {
        let _: String = try await call(method: "aria2.unpause", params: [.string(gid)])
    }

    func remove(gid: String) async throws {
        let _: String = try await call(method: "aria2.remove", params: [.string(gid)])
    }

    func forceRemove(gid: String) async throws {
        let _: String = try await call(method: "aria2.forceRemove", params: [.string(gid)])
    }

    func removeResult(gid: String) async throws {
        let _: String = try await call(method: "aria2.removeDownloadResult", params: [.string(gid)])
    }

    func pauseAll() async throws {
        let _: String = try await call(method: "aria2.pauseAll")
    }

    func forcePauseAll() async throws {
        let _: String = try await call(method: "aria2.forcePauseAll")
    }

    func resumeAll() async throws {
        let _: String = try await call(method: "aria2.unpauseAll")
    }

    func updateGlobalOptions(_ options: [String: String]) async throws {
        let _: String = try await call(
            method: "aria2.changeGlobalOption",
            params: [.object(options.mapValues(JSONValue.string))]
        )
    }

    func globalOptions() async throws -> [String: String] {
        try await call(method: "aria2.getGlobalOption")
    }

    func updateTaskOptions(gid: String, options: [String: String]) async throws {
        let _: String = try await call(
            method: "aria2.changeOption",
            params: [
                .string(gid),
                .object(options.mapValues(JSONValue.string))
            ]
        )
    }

    func taskOptions(gid: String) async throws -> [String: String] {
        try await call(
            method: "aria2.getOption",
            params: [.string(gid)]
        )
    }

    func changePosition(
        gid: String,
        position: Int,
        relativeTo how: String
    ) async throws -> Int {
        try await call(
            method: "aria2.changePosition",
            params: [
                .string(gid),
                .integer(position),
                .string(how)
            ]
        )
    }

    func changeURIs(
        gid: String,
        fileIndex: Int,
        removing removedURIs: [String],
        adding addedURIs: [String],
        position: Int? = nil
    ) async throws -> [Int] {
        var params: [JSONValue] = [
            .string(gid),
            .integer(max(fileIndex, 1)),
            .array(removedURIs.map(JSONValue.string)),
            .array(addedURIs.map(JSONValue.string))
        ]
        if let position {
            params.append(.integer(max(position, 0)))
        }
        return try await call(method: "aria2.changeUri", params: params)
    }

    func purgeDownloadResults() async throws {
        let _: String = try await call(method: "aria2.purgeDownloadResult")
    }

    func sessionInfo() async throws -> Aria2SessionInfo {
        try await call(method: "aria2.getSessionInfo")
    }

    func saveSession() async throws {
        let _: String = try await call(method: "aria2.saveSession")
    }

    func shutdown(force: Bool = false) async throws {
        let _: String = try await call(
            method: force ? "aria2.forceShutdown" : "aria2.shutdown"
        )
    }

    func rpcMethods() async throws -> [String] {
        try await call(method: "system.listMethods", authenticate: false)
    }

    func rpcNotifications() async throws -> [String] {
        try await call(method: "system.listNotifications", authenticate: false)
    }

    func multicall(
        _ invocations: [Aria2MulticallInvocation]
    ) async throws -> [Aria2MulticallResult] {
        guard !invocations.isEmpty else { return [] }
        let methods = invocations.map { invocation -> JSONValue in
            var parameters = invocation.parameters.map(JSONValue.string)
            if invocation.method.hasPrefix("aria2."), !secret.isEmpty {
                parameters.insert(.string("token:\(secret)"), at: 0)
            }
            return .object([
                "methodName": .string(invocation.method),
                "params": .array(parameters)
            ])
        }
        let values: [RPCDecodedValue] = try await call(
            method: "system.multicall",
            params: [.array(methods)],
            authenticate: false
        )
        return values.map { value in
            if case .object(let object) = value {
                return .failure(
                    code: object["faultCode"]?.integerValue,
                    message: object["faultString"]?.stringValue
                )
            }
            return .success
        }
    }

    private func call<Result: Decodable>(
        method: String,
        params: [JSONValue] = [],
        authenticate: Bool = true
    ) async throws -> Result {
        guard let endpoint else {
            throw Aria2ClientError.invalidEndpoint
        }

        requestID += 1
        var authenticatedParams = params
        if authenticate, !secret.isEmpty {
            authenticatedParams.insert(.string("token:\(secret)"), at: 0)
        }

        let payload = RPCRequest(
            id: "arialane-\(requestID)",
            method: method,
            params: authenticatedParams
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 5
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw Aria2ClientError.invalidResponse
        }

        let envelope: RPCResponse<Result>
        do {
            envelope = try JSONDecoder().decode(RPCResponse<Result>.self, from: data)
        } catch {
            guard (200..<300).contains(httpResponse.statusCode) else {
                throw Aria2ClientError.httpStatus(httpResponse.statusCode)
            }
            throw Aria2ClientError.invalidResponse
        }

        if let error = envelope.error {
            throw Aria2ClientError.rpc(code: error.code, message: error.message)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw Aria2ClientError.httpStatus(httpResponse.statusCode)
        }
        guard let result = envelope.result else {
            throw Aria2ClientError.invalidResponse
        }
        return result
    }
}
