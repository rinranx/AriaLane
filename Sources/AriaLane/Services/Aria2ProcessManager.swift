import Foundation

enum Aria2ProcessError: LocalizedError {
    case remoteEndpoint
    case binaryMissing
    case invalidEndpoint

    var errorDescription: String? {
        switch self {
        case .remoteEndpoint:
            L10n.string("自动启动只适用于本机 RPC 地址")
        case .binaryMissing:
            L10n.string("找不到 aria2c。请先运行 brew install aria2")
        case .invalidEndpoint:
            L10n.string("无法从 RPC 地址读取端口")
        }
    }
}

@MainActor
final class Aria2ProcessManager {
    private var process: Process?
    private var launchIdentity: String?

    var isRunning: Bool {
        process?.isRunning == true
    }

    var detectedBinaryPath: String? {
        let candidates = [
            "/opt/homebrew/bin/aria2c",
            "/usr/local/bin/aria2c",
            "/usr/bin/aria2c"
        ]
        return candidates.first(where: FileManager.default.isExecutableFile(atPath:))
    }

    func start(
        endpoint: URL,
        secret: String,
        configuration: Aria2Configuration
    ) throws {
        guard let host = endpoint.host?.lowercased(),
              ["127.0.0.1", "localhost", "::1"].contains(host) else {
            throw Aria2ProcessError.remoteEndpoint
        }
        guard let binaryPath = detectedBinaryPath else {
            throw Aria2ProcessError.binaryMissing
        }
        guard let port = endpoint.port ?? (endpoint.scheme == "https" ? 443 : 6800) as Int? else {
            throw Aria2ProcessError.invalidEndpoint
        }

        let nextLaunchIdentity = "\(host):\(port):\(secret)"
        if process?.isRunning == true {
            if launchIdentity == nextLaunchIdentity {
                return
            }
            stop()
        }

        let supportDirectory = try applicationSupportDirectory()
        let sessionFile = supportDirectory.appendingPathComponent("aria2.session")
        if !FileManager.default.fileExists(atPath: sessionFile.path) {
            FileManager.default.createFile(atPath: sessionFile.path, contents: Data())
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: binaryPath)
        task.arguments = [
            "--enable-rpc=true",
            "--rpc-listen-all=false",
            "--rpc-listen-port=\(port)",
            "--rpc-allow-origin-all=false",
            "--rpc-max-request-size=16M",
            "--save-session=\(sessionFile.path)",
            "--input-file=\(sessionFile.path)",
            "--save-session-interval=30",
            "--download-result=full",
            "--summary-interval=0",
            "--console-log-level=warn"
        ] + configuration.commandLineArguments
            + (secret.isEmpty ? [] : ["--rpc-secret=\(secret)"])
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice

        try task.run()
        process = task
        launchIdentity = nextLaunchIdentity
    }

    func stop() {
        guard let process, process.isRunning else {
            self.process = nil
            launchIdentity = nil
            return
        }
        process.terminate()
        process.waitUntilExit()
        self.process = nil
        launchIdentity = nil
    }

    private func applicationSupportDirectory() throws -> URL {
        let root = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directory = root.appendingPathComponent("AriaLane", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }
}
