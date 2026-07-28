import Foundation

enum ArchiveRecovery: Equatable, Sendable {
    case restoredBackup
    case resetCorruptedFile(URL?)
}

struct ArchiveLoadResult<Value> {
    let value: Value
    let recovery: ArchiveRecovery?
}

enum SecureJSONArchive {
    static func load<Value: Codable>(
        _ type: Value.Type,
        from fileURL: URL,
        default defaultValue: @autoclosure () -> Value
    ) throws -> ArchiveLoadResult<Value> {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return ArchiveLoadResult(value: defaultValue(), recovery: nil)
        }

        let primaryData = try Data(contentsOf: fileURL)
        do {
            return ArchiveLoadResult(
                value: try decoder.decode(type, from: primaryData),
                recovery: nil
            )
        } catch {
            let backupURL = backupURL(for: fileURL)
            if fileManager.fileExists(atPath: backupURL.path),
               let backupData = try? Data(contentsOf: backupURL),
               let recovered = try? decoder.decode(type, from: backupData) {
                try? backupData.write(to: fileURL, options: .atomic)
                protect(fileURL)
                return ArchiveLoadResult(
                    value: recovered,
                    recovery: .restoredBackup
                )
            }

            let quarantinedURL = quarantine(fileURL)
            return ArchiveLoadResult(
                value: defaultValue(),
                recovery: .resetCorruptedFile(quarantinedURL)
            )
        }
    }

    static func save<Value: Codable>(_ value: Value, to fileURL: URL) throws {
        let fileManager = FileManager.default
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directory.path
        )

        let data = try encoder.encode(value)
        let backupURL = backupURL(for: fileURL)
        try data.write(to: backupURL, options: .atomic)
        protect(backupURL)
        try data.write(to: fileURL, options: .atomic)
        protect(fileURL)
    }

    static func backupURL(for fileURL: URL) -> URL {
        fileURL.appendingPathExtension("backup")
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.timeIntervalSince1970)
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let timestamp = try? container.decode(Double.self) {
                return Date(timeIntervalSince1970: timestamp)
            }

            let string = try container.decode(String.self)
            if let date = fractionalISO8601Formatter.date(from: string)
                ?? legacyISO8601Formatter.date(from: string) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid archive date: \(string)"
            )
        }
        return decoder
    }

    private static let fractionalISO8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let legacyISO8601Formatter = ISO8601DateFormatter()

    private static func protect(_ fileURL: URL) {
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }

    private static func quarantine(_ fileURL: URL) -> URL? {
        let fileManager = FileManager.default
        let timestamp = Int(Date().timeIntervalSince1970)
        let quarantinedURL = fileURL
            .deletingPathExtension()
            .appendingPathExtension("corrupt-\(timestamp)")
            .appendingPathExtension(fileURL.pathExtension)

        do {
            if fileManager.fileExists(atPath: quarantinedURL.path) {
                try fileManager.removeItem(at: quarantinedURL)
            }
            try fileManager.moveItem(at: fileURL, to: quarantinedURL)
            protect(quarantinedURL)
            return quarantinedURL
        } catch {
            return nil
        }
    }
}
