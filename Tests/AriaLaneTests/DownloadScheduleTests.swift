import XCTest
@testable import AriaLane

final class DownloadScheduleTests: XCTestCase {
    func testNightScheduleSpansMidnight() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let schedule = NightSpeedSchedule(
            isEnabled: true,
            startMinute: 23 * 60,
            endMinute: 7 * 60,
            downloadLimitKiB: 2_048,
            uploadLimitKiB: 256
        )

        XCTAssertTrue(schedule.isActive(at: date(hour: 23, minute: 30, calendar: calendar), calendar: calendar))
        XCTAssertTrue(schedule.isActive(at: date(hour: 6, minute: 59, calendar: calendar), calendar: calendar))
        XCTAssertFalse(schedule.isActive(at: date(hour: 7, minute: 0, calendar: calendar), calendar: calendar))
        XCTAssertFalse(schedule.isActive(at: date(hour: 18, minute: 0, calendar: calendar), calendar: calendar))
    }

    func testDaytimeScheduleUsesHalfOpenRange() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let schedule = NightSpeedSchedule(
            isEnabled: true,
            startMinute: 9 * 60,
            endMinute: 17 * 60,
            downloadLimitKiB: 1,
            uploadLimitKiB: 1
        )

        XCTAssertFalse(schedule.isActive(at: date(hour: 8, minute: 59, calendar: calendar), calendar: calendar))
        XCTAssertTrue(schedule.isActive(at: date(hour: 9, minute: 0, calendar: calendar), calendar: calendar))
        XCTAssertFalse(schedule.isActive(at: date(hour: 17, minute: 0, calendar: calendar), calendar: calendar))
    }

    func testScheduleArchiveSortsFindsAndRemovesEntries() {
        let now = Date(timeIntervalSince1970: 10_000)
        let options = DownloadTaskOptions.defaults(directory: "/tmp")
        let later = ScheduledDownload(
            urls: ["https://example.com/later.zip"],
            taskOptions: options,
            scheduledAt: now.addingTimeInterval(120)
        )
        let sooner = ScheduledDownload(
            urls: ["https://example.com/sooner.zip"],
            taskOptions: options,
            scheduledAt: now.addingTimeInterval(30)
        )
        var archive = DownloadScheduleArchive()

        XCTAssertTrue(archive.add(later))
        XCTAssertTrue(archive.add(sooner))
        XCTAssertEqual(archive.entries.map(\.id), [sooner.id, later.id])
        XCTAssertEqual(archive.due(at: now.addingTimeInterval(60)).map(\.id), [sooner.id])
        XCTAssertTrue(archive.remove(id: sooner.id))
        XCTAssertEqual(archive.entries.map(\.id), [later.id])
    }

    func testScheduledDownloadRoundTripsSensitiveOptions() throws {
        var options = DownloadTaskOptions.defaults(directory: "/tmp")
        options.customHeaders = ["Authorization: Bearer local-token"]
        options.cookie = "session=local"
        options.username = "user"
        options.password = "password"
        let entry = ScheduledDownload(
            urls: ["https://example.com/file"],
            taskOptions: options,
            scheduledAt: Date(timeIntervalSince1970: 12_345)
        )

        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(ScheduledDownload.self, from: data)
        XCTAssertEqual(decoded, entry)
    }

    func testScheduleCanUpdateAndDuplicateWithoutReusingSubmissionGIDs() throws {
        let options = DownloadTaskOptions.defaults(directory: "/tmp")
        let original = ScheduledDownload(
            urls: ["https://example.com/original.zip"],
            taskOptions: options,
            scheduledAt: Date(timeIntervalSince1970: 10_000)
        )
        var archive = DownloadScheduleArchive(entries: [original])
        var updated = original
        updated.scheduledAt = Date(timeIntervalSince1970: 20_000)

        XCTAssertTrue(archive.update(updated))
        XCTAssertEqual(archive.entry(id: original.id)?.scheduledAt, updated.scheduledAt)

        let duplicate = try XCTUnwrap(
            archive.duplicate(
                id: original.id,
                scheduledAt: Date(timeIntervalSince1970: 30_000)
            )
        )
        XCTAssertNotEqual(duplicate.id, original.id)
        XCTAssertNotEqual(duplicate.submissionGIDs, original.submissionGIDs)
        XCTAssertEqual(archive.entries.map(\.id), [original.id, duplicate.id])
    }

    func testLegacyScheduleGetsStableSubmissionGIDsBeforeExecution() throws {
        let legacyJSON = """
        {
          "id": "B15226A1-11B7-4D5F-827E-5ABEA67C4430",
          "urls": ["https://example.com/legacy.zip"],
          "taskOptions": {
            "directory": "/tmp",
            "outputFileName": "",
            "maxDownloadLimitKiB": 0,
            "maxUploadLimitKiB": 0,
            "split": 8,
            "maxConnectionPerServer": 8,
            "referer": "",
            "userAgent": "",
            "customHeaders": [],
            "cookie": "",
            "username": "",
            "password": "",
            "checksumAlgorithm": "none",
            "checksumDigest": ""
          },
          "scheduledAt": "2026-07-26T12:00:00Z",
          "createdAt": "2026-07-26T11:00:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var decoded = try decoder.decode(
            ScheduledDownload.self,
            from: Data(legacyJSON.utf8)
        )

        XCTAssertNil(decoded.submissionGIDs)
        XCTAssertEqual(decoded.frequency, .once)
        decoded.prepareSubmissionGIDs()
        let gids = try XCTUnwrap(decoded.submissionGIDs)
        XCTAssertEqual(gids.count, 1)
        XCTAssertTrue(DownloadSubmissionIdentifier.isValidGID(gids[0]))
    }

    func testRecurringScheduleSkipsMissedDailyOccurrences() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let start = try XCTUnwrap(
            calendar.date(
                from: DateComponents(
                    year: 2026,
                    month: 7,
                    day: 20,
                    hour: 9,
                    minute: 30
                )
            )
        )
        let reference = try XCTUnwrap(
            calendar.date(byAdding: .hour, value: 52, to: start)
        )

        let next = ScheduleFrequency.daily.nextDate(
            after: reference,
            from: start,
            calendar: calendar
        )

        XCTAssertEqual(
            next,
            calendar.date(byAdding: .day, value: 3, to: start)
        )
    }

    func testWeekdayScheduleAdvancesFridayToMonday() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let friday = try XCTUnwrap(
            calendar.date(
                from: DateComponents(
                    year: 2026,
                    month: 7,
                    day: 24,
                    hour: 8
                )
            )
        )
        let monday = try XCTUnwrap(
            calendar.date(
                from: DateComponents(
                    year: 2026,
                    month: 7,
                    day: 27,
                    hour: 8
                )
            )
        )

        XCTAssertEqual(
            ScheduleFrequency.weekdays.nextDate(
                after: friday,
                from: friday,
                calendar: calendar
            ),
            monday
        )
    }

    private func date(hour: Int, minute: Int, calendar: Calendar) -> Date {
        calendar.date(
            from: DateComponents(
                calendar: calendar,
                timeZone: calendar.timeZone,
                year: 2026,
                month: 7,
                day: 26,
                hour: hour,
                minute: minute
            )
        )!
    }
}
