import XCTest
@testable import AriaLane

final class ApplicationLifecycleTests: XCTestCase {
    func testReopenOnlyRequestsMainWindowWhenNoWindowIsVisible() async {
        let result = await MainActor.run {
            let coordinator = ApplicationLifecycleCoordinator()
            var openCount = 0
            coordinator.configure(
                openMainWindow: {
                    openCount += 1
                },
                resumeAfterSystemWake: {},
                shutdown: {}
            )

            let openedWithVisibleWindow = coordinator.reopenMainWindowIfNeeded(
                hasVisibleWindows: true
            )
            let openedWithoutVisibleWindow = coordinator.reopenMainWindowIfNeeded(
                hasVisibleWindows: false
            )
            return (
                openedWithVisibleWindow,
                openedWithoutVisibleWindow,
                openCount
            )
        }

        XCTAssertFalse(result.0)
        XCTAssertTrue(result.1)
        XCTAssertEqual(result.2, 1)
    }

    func testWakeAndTerminationCallbacksAreForwarded() async {
        let result = await MainActor.run {
            let coordinator = ApplicationLifecycleCoordinator()
            var wakeCount = 0
            var shutdownCount = 0
            coordinator.configure(
                openMainWindow: {},
                resumeAfterSystemWake: {
                    wakeCount += 1
                },
                shutdown: {
                    shutdownCount += 1
                }
            )

            coordinator.systemDidWake()
            coordinator.applicationWillTerminate()
            return (wakeCount, shutdownCount)
        }

        XCTAssertEqual(result.0, 1)
        XCTAssertEqual(result.1, 1)
    }
}
