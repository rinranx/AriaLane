import Foundation
import XCTest
@testable import AriaLane

final class PendingDownloadTests: XCTestCase {
    func testSubmissionGIDsAreValidAndUnique() {
        let gids = DownloadSubmissionIdentifier.makeGIDs(count: 100)

        XCTAssertEqual(gids.count, 100)
        XCTAssertEqual(Set(gids).count, 100)
        XCTAssertTrue(gids.allSatisfy(DownloadSubmissionIdentifier.isValidGID))
    }

    func testRetryPolicyUsesBoundedExponentialBackoff() {
        let policy = PendingDownloadRetryPolicy(
            initialDelay: 5,
            maximumDelay: 60
        )

        XCTAssertEqual(policy.delay(afterAttempt: 0), 0)
        XCTAssertEqual(policy.delay(afterAttempt: 1), 5)
        XCTAssertEqual(policy.delay(afterAttempt: 2), 10)
        XCTAssertEqual(policy.delay(afterAttempt: 5), 60)
        XCTAssertEqual(policy.delay(afterAttempt: 20), 60)
    }

    func testPendingEntryTracksFailuresAndManualRetry() {
        let start = Date(timeIntervalSince1970: 1_000)
        var entry = PendingDownload(
            url: "https://example.com/archive.zip",
            taskOptions: .defaults(directory: "/tmp"),
            createdAt: start
        )
        let policy = PendingDownloadRetryPolicy(
            initialDelay: 10,
            maximumDelay: 60
        )

        XCTAssertTrue(entry.isEligibleForAutomaticRetry(at: start, policy: policy))
        entry.recordFailure("Connection lost", at: start)

        XCTAssertTrue(entry.hasFailed)
        XCTAssertEqual(entry.attemptCount, 1)
        XCTAssertFalse(
            entry.isEligibleForAutomaticRetry(
                at: start.addingTimeInterval(9),
                policy: policy
            )
        )
        XCTAssertTrue(
            entry.isEligibleForAutomaticRetry(
                at: start.addingTimeInterval(10),
                policy: policy
            )
        )

        entry.prepareForManualRetry()
        XCTAssertFalse(entry.hasFailed)
        XCTAssertTrue(entry.isEligibleForAutomaticRetry(at: start, policy: policy))
    }

    func testArchiveDeduplicatesScheduleOriginAcrossGIDRegeneration() {
        let scheduleID = UUID()
        let options = DownloadTaskOptions.defaults(directory: "/tmp")
        let first = PendingDownload(
            url: "https://example.com/file.zip",
            taskOptions: options,
            originScheduleID: scheduleID,
            originScheduleIndex: 0
        )
        let regenerated = PendingDownload(
            url: first.url,
            taskOptions: options,
            originScheduleID: scheduleID,
            originScheduleIndex: 0
        )
        var archive = PendingDownloadArchive()

        XCTAssertTrue(archive.add(first))
        XCTAssertFalse(archive.add(regenerated))
        XCTAssertEqual(archive.entries, [first])
    }

    func testArchiveAllowsDifferentRecurringScheduleOccurrences() {
        let scheduleID = UUID()
        let firstOccurrenceID = UUID()
        let secondOccurrenceID = UUID()
        let options = DownloadTaskOptions.defaults(directory: "/tmp")
        let first = PendingDownload(
            url: "https://example.com/file.zip",
            taskOptions: options,
            originScheduleID: scheduleID,
            originScheduleIndex: 0,
            originScheduleOccurrenceID: firstOccurrenceID
        )
        let duplicateOccurrence = PendingDownload(
            url: first.url,
            taskOptions: options,
            originScheduleID: scheduleID,
            originScheduleIndex: 0,
            originScheduleOccurrenceID: firstOccurrenceID
        )
        let nextOccurrence = PendingDownload(
            url: first.url,
            taskOptions: options,
            originScheduleID: scheduleID,
            originScheduleIndex: 0,
            originScheduleOccurrenceID: secondOccurrenceID
        )
        var archive = PendingDownloadArchive()

        XCTAssertTrue(archive.add(first))
        XCTAssertFalse(archive.add(duplicateOccurrence))
        XCTAssertTrue(archive.add(nextOccurrence))
        XCTAssertEqual(archive.entries.count, 2)
    }

    func testRepositoryRoundTripsSensitiveDataWithPrivatePermissions() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        var options = DownloadTaskOptions.defaults(directory: "/tmp")
        options.customHeaders = ["Authorization: Bearer local-token"]
        options.cookie = "session=local"
        options.username = "reader"
        options.password = "secret"
        let entry = PendingDownload(
            url: "https://example.com/private.zip",
            taskOptions: options
        )
        let archive = PendingDownloadArchive(entries: [entry])
        let fileURL = directory.appendingPathComponent("pending.json")
        let repository = PendingDownloadRepository(fileURL: fileURL)

        try repository.save(archive)
        let loadedEntry = try XCTUnwrap(repository.load().entries.first)
        XCTAssertEqual(loadedEntry.id, entry.id)
        XCTAssertEqual(loadedEntry.url, entry.url)
        XCTAssertEqual(loadedEntry.taskOptions, entry.taskOptions)
        XCTAssertEqual(loadedEntry.submissionGID, entry.submissionGID)
        XCTAssertEqual(
            loadedEntry.createdAt.timeIntervalSince1970,
            entry.createdAt.timeIntervalSince1970,
            accuracy: 0.000_001
        )

        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let permissions = try XCTUnwrap(
            attributes[.posixPermissions] as? NSNumber
        )
        XCTAssertEqual(permissions.intValue & 0o777, 0o600)
    }

    func testRepositoryRestoresLastValidBackup() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let repository = PendingDownloadRepository(
            fileURL: directory.appendingPathComponent("pending.json")
        )
        let first = PendingDownloadArchive(entries: [
            PendingDownload(
                url: "https://example.com/first.zip",
                taskOptions: .defaults(directory: "/tmp")
            )
        ])
        let second = PendingDownloadArchive(entries: first.entries + [
            PendingDownload(
                url: "https://example.com/second.zip",
                taskOptions: .defaults(directory: "/tmp")
            )
        ])

        try repository.save(first)
        try repository.save(second)
        try Data("{broken".utf8).write(to: repository.fileURL, options: .atomic)

        let result = try repository.loadResult()
        XCTAssertEqual(
            result.value.entries.map(\.id),
            second.entries.map(\.id)
        )
        XCTAssertEqual(
            result.value.entries.map(\.url),
            second.entries.map(\.url)
        )
        for (loaded, expected) in zip(result.value.entries, second.entries) {
            XCTAssertEqual(loaded.taskOptions, expected.taskOptions)
            XCTAssertEqual(loaded.submissionGID, expected.submissionGID)
            XCTAssertEqual(
                loaded.createdAt.timeIntervalSince1970,
                expected.createdAt.timeIntervalSince1970,
                accuracy: 0.000_001
            )
        }
        XCTAssertEqual(result.recovery, .restoredBackup)
    }

    func testRepositoryQuarantinesUnrecoverableCorruption() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let repository = PendingDownloadRepository(
            fileURL: directory.appendingPathComponent("pending.json")
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try Data("{broken".utf8).write(to: repository.fileURL)

        let result = try repository.loadResult()
        XCTAssertTrue(result.value.entries.isEmpty)
        guard case .resetCorruptedFile(let quarantinedURL) = result.recovery else {
            return XCTFail("Expected the corrupted file to be quarantined")
        }
        XCTAssertNotNil(quarantinedURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: repository.fileURL.path))
    }

    func testConnectionBackoffIsBounded() {
        let backoff = ConnectionRetryBackoff(
            initialDelay: 2.5,
            maximumDelay: 20
        )

        XCTAssertEqual(backoff.delay(afterFailure: 0), 0)
        XCTAssertEqual(backoff.delay(afterFailure: 1), 2.5)
        XCTAssertEqual(backoff.delay(afterFailure: 2), 5)
        XCTAssertEqual(backoff.delay(afterFailure: 4), 20)
        XCTAssertEqual(backoff.delay(afterFailure: 10), 20)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("AriaLanePendingTests-\(UUID().uuidString)")
    }
}
