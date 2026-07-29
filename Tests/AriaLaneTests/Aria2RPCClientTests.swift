import Foundation
import XCTest
@testable import AriaLane

final class Aria2RPCClientTests: XCTestCase {
    override func tearDown() {
        RPCURLProtocolStub.handler = nil
        super.tearDown()
    }

    func testHTTP400JSONRPCErrorPreservesMissingGIDError() async throws {
        let (client, session) = await makeClient(
            statusCode: 400,
            body: """
            {
              "jsonrpc": "2.0",
              "id": "arialane-1",
              "error": {
                "code": 1,
                "message": "GID 97f78f3885aa44d0 is not found"
              }
            }
            """
        )
        defer { session.invalidateAndCancel() }

        do {
            _ = try await client.status(gid: "97f78f3885aa44d0")
            XCTFail("Expected aria2 to report the missing GID")
        } catch let error as Aria2ClientError {
            guard case .rpc(let code, let message) = error else {
                return XCTFail("Expected an RPC error, got \(error)")
            }
            XCTAssertEqual(code, 1)
            XCTAssertEqual(message, "GID 97f78f3885aa44d0 is not found")
        }
    }

    func testHTTP400WithoutJSONRPCEnvelopeRemainsHTTPError() async throws {
        let (client, session) = await makeClient(
            statusCode: 400,
            body: "<html><body>Bad Request</body></html>"
        )
        defer { session.invalidateAndCancel() }

        do {
            _ = try await client.version()
            XCTFail("Expected the HTTP request to fail")
        } catch let error as Aria2ClientError {
            guard case .httpStatus(let statusCode) = error else {
                return XCTFail("Expected an HTTP status error, got \(error)")
            }
            XCTAssertEqual(statusCode, 400)
        }
    }

    func testAddUriEncodesMultipleSourcesHeadersAndToken() async throws {
        let (client, session) = await makeClient(
            statusCode: 200,
            body: """
            {"jsonrpc":"2.0","id":"arialane-1","result":"gid-1"}
            """,
            secret: "rpc-secret"
        ) { payload in
            XCTAssertEqual(payload["method"] as? String, "aria2.addUri")
            let params = try XCTUnwrap(payload["params"] as? [Any])
            XCTAssertEqual(params[0] as? String, "token:rpc-secret")
            XCTAssertEqual(
                params[1] as? [String],
                [
                    "https://one.example.test/file",
                    "sftp://two.example.test/file"
                ]
            )
            let options = try XCTUnwrap(params[2] as? [String: Any])
            XCTAssertEqual(options["dir"] as? String, "/tmp")
            XCTAssertEqual(
                options["header"] as? [String],
                ["Authorization: Bearer test"]
            )
        }
        defer { session.invalidateAndCancel() }

        let gid = try await client.add(
            uris: [
                "https://one.example.test/file",
                "sftp://two.example.test/file"
            ],
            options: ["dir": "/tmp"],
            headers: ["Authorization: Bearer test"]
        )
        XCTAssertEqual(gid, "gid-1")
    }

    func testCertificateVerificationSettingIsSynchronizedGlobally() async throws {
        let (client, session) = await makeClient(
            statusCode: 200,
            body: """
            {"jsonrpc":"2.0","id":"arialane-1","result":"OK"}
            """
        ) { payload in
            XCTAssertEqual(
                payload["method"] as? String,
                "aria2.changeGlobalOption"
            )
            let params = try XCTUnwrap(payload["params"] as? [Any])
            let options = try XCTUnwrap(params[0] as? [String: Any])
            XCTAssertEqual(options["check-certificate"] as? String, "true")
        }
        defer { session.invalidateAndCancel() }

        try await client.updateGlobalOptions([
            "check-certificate": "true"
        ])
    }

    func testSystemMulticallAuthenticatesEachAria2Invocation() async throws {
        let (client, session) = await makeClient(
            statusCode: 200,
            body: """
            {
              "jsonrpc":"2.0",
              "id":"arialane-1",
              "result":[
                ["gid-1"],
                {"faultCode":1,"faultString":"GID not found"}
              ]
            }
            """,
            secret: "rpc-secret"
        ) { payload in
            XCTAssertEqual(payload["method"] as? String, "system.multicall")
            let params = try XCTUnwrap(payload["params"] as? [Any])
            XCTAssertEqual(params.count, 1)
            let calls = try XCTUnwrap(params[0] as? [[String: Any]])
            XCTAssertEqual(calls.count, 2)
            XCTAssertEqual(calls[0]["methodName"] as? String, "aria2.pause")
            XCTAssertEqual(
                calls[0]["params"] as? [String],
                ["token:rpc-secret", "gid-1"]
            )
            XCTAssertEqual(
                calls[1]["params"] as? [String],
                ["token:rpc-secret", "gid-2"]
            )
        }
        defer { session.invalidateAndCancel() }

        let results = try await client.multicall([
            Aria2MulticallInvocation(method: "aria2.pause", parameters: ["gid-1"]),
            Aria2MulticallInvocation(method: "aria2.pause", parameters: ["gid-2"])
        ])
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results[0].isSuccess)
        XCTAssertFalse(results[1].isSuccess)
        XCTAssertEqual(results[1].errorCode, 1)
        XCTAssertEqual(results[1].errorMessage, "GID not found")
    }

    func testAddTorrentEncodesWebSeedURIs() async throws {
        let torrentData = Data("torrent-data".utf8)
        let (client, session) = await makeClient(
            statusCode: 200,
            body: """
            {"jsonrpc":"2.0","id":"arialane-1","result":"torrent-gid"}
            """
        ) { payload in
            XCTAssertEqual(payload["method"] as? String, "aria2.addTorrent")
            let params = try XCTUnwrap(payload["params"] as? [Any])
            XCTAssertEqual(
                params[0] as? String,
                torrentData.base64EncodedString()
            )
            XCTAssertEqual(
                params[1] as? [String],
                [
                    "https://seed.example.test/files/",
                    "ftp://seed.example.test/files/"
                ]
            )
            XCTAssertEqual(
                (params[2] as? [String: Any])?["pause"] as? String,
                "true"
            )
        }
        defer { session.invalidateAndCancel() }

        let gid = try await client.addTorrent(
            data: torrentData,
            webSeedURIs: [
                "https://seed.example.test/files/",
                "ftp://seed.example.test/files/"
            ],
            options: ["pause": "true"]
        )
        XCTAssertEqual(gid, "torrent-gid")
    }

    private func makeClient(
        statusCode: Int,
        body: String,
        secret: String = "",
        inspectPayload: (([String: Any]) throws -> Void)? = nil
    ) async -> (Aria2RPCClient, URLSession) {
        RPCURLProtocolStub.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "Content-Type"),
                "application/json"
            )
            if let inspectPayload {
                let data = try requestBodyData(request)
                let payload = try XCTUnwrap(
                    JSONSerialization.jsonObject(with: data) as? [String: Any]
                )
                try inspectPayload(payload)
            }

            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )
            return (try XCTUnwrap(response), Data(body.utf8))
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RPCURLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        let client = Aria2RPCClient(session: session)
        await client.configure(
            endpoint: URL(string: "http://127.0.0.1:6800/jsonrpc"),
            secret: secret
        )
        return (client, session)
    }
}

private final class RPCURLProtocolStub: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(
                self,
                didFailWithError: URLError(.resourceUnavailable)
            )
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(
                self,
                didReceive: response,
                cacheStoragePolicy: .notAllowed
            )
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func requestBodyData(_ request: URLRequest) throws -> Data {
    if let body = request.httpBody {
        return body
    }
    let stream = try XCTUnwrap(request.httpBodyStream)
    stream.open()
    defer { stream.close() }

    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4_096)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count < 0 {
            throw stream.streamError ?? URLError(.cannotDecodeContentData)
        }
        if count == 0 {
            break
        }
        data.append(buffer, count: count)
    }
    return data
}
