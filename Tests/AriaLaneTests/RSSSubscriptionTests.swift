import Foundation
import XCTest
@testable import AriaLane

final class RSSSubscriptionTests: XCTestCase {
    func testParsesRSSFeedWithDownloadableEnclosure() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
          <channel>
            <title>Release Feed</title>
            <item>
              <guid>release-42</guid>
              <title>AriaLane 4.2</title>
              <link>https://example.com/releases/42</link>
              <enclosure url="https://example.com/files/arialane-4.2.dmg" type="application/x-apple-diskimage" />
              <pubDate>Mon, 27 Jul 2026 08:30:00 +0000</pubDate>
            </item>
          </channel>
        </rss>
        """

        let feed = try RSSFeedParser.parse(Data(xml.utf8))

        XCTAssertEqual(feed.title, "Release Feed")
        XCTAssertEqual(feed.items.count, 1)
        XCTAssertEqual(feed.items[0].id, "release-42")
        XCTAssertEqual(feed.items[0].displayTitle, "AriaLane 4.2")
        XCTAssertEqual(
            feed.items[0].downloadURL,
            "https://example.com/files/arialane-4.2.dmg"
        )
        XCTAssertNotNil(feed.items[0].publishedAt)
    }

    func testParsesAtomEnclosureAndAlternateLink() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <title>Video Feed</title>
          <entry>
            <id>video-1</id>
            <title>Episode One</title>
            <link rel="alternate" href="https://example.com/episodes/1" />
            <link rel="enclosure" href="https://cdn.example.com/episode-1.mp4" />
            <updated>2026-07-27T10:00:00Z</updated>
          </entry>
        </feed>
        """

        let feed = try RSSFeedParser.parse(Data(xml.utf8))

        XCTAssertEqual(feed.title, "Video Feed")
        XCTAssertEqual(feed.items.first?.link, "https://example.com/episodes/1")
        XCTAssertEqual(
            feed.items.first?.downloadURL,
            "https://cdn.example.com/episode-1.mp4"
        )
    }

    func testSubscriptionArchiveRejectsDuplicateFeedURLs() {
        let options = DownloadTaskOptions.defaults(directory: "/tmp")
        let first = RSSSubscription(
            title: "First",
            feedURL: "https://example.com/feed.xml",
            taskOptions: options
        )
        let duplicate = RSSSubscription(
            title: "Duplicate",
            feedURL: "HTTPS://EXAMPLE.COM/FEED.XML",
            taskOptions: options
        )
        var archive = RSSSubscriptionArchive()

        XCTAssertTrue(archive.add(first))
        XCTAssertFalse(archive.add(duplicate))
        XCTAssertEqual(archive.entries, [first])
    }

    func testSubscriptionDueDateUsesRefreshIntervalAndEnabledState() {
        let now = Date(timeIntervalSince1970: 10_000)
        var subscription = RSSSubscription(
            title: "Feed",
            feedURL: "https://example.com/feed.xml",
            refreshInterval: .thirtyMinutes,
            taskOptions: .defaults(directory: "/tmp"),
            lastCheckedAt: now
        )

        XCTAssertFalse(subscription.isDue(at: now.addingTimeInterval(1_799)))
        XCTAssertTrue(subscription.isDue(at: now.addingTimeInterval(1_800)))
        subscription.isEnabled = false
        XCTAssertFalse(subscription.isDue(at: now.addingTimeInterval(3_600)))
    }

    func testCustomRefreshIntervalDrivesDueDateAndKeepsLegacyCodingShape() throws {
        let customInterval = RSSRefreshInterval(seconds: 5_400)
        let now = Date(timeIntervalSince1970: 20_000)
        let subscription = RSSSubscription(
            title: "Custom Feed",
            feedURL: "https://example.com/custom.xml",
            refreshInterval: customInterval,
            taskOptions: .defaults(directory: "/tmp"),
            lastCheckedAt: now
        )

        XCTAssertEqual(customInterval.title, "每 90 分钟")
        XCTAssertFalse(subscription.isDue(at: now.addingTimeInterval(5_399)))
        XCTAssertTrue(subscription.isDue(at: now.addingTimeInterval(5_400)))

        let encoded = try JSONEncoder().encode(customInterval)
        XCTAssertEqual(String(decoding: encoded, as: UTF8.self), "5400")
        XCTAssertEqual(
            try JSONDecoder().decode(RSSRefreshInterval.self, from: encoded),
            customInterval
        )
    }
}
