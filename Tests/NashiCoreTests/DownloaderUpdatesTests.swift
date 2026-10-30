import XCTest
@testable import NashiCore

final class DownloaderUpdatesTests: XCTestCase {
    private final class Counter: @unchecked Sendable { var calls = 0 }

    func testUnsupportedLinksAreNotRetried() async {
        let counter = Counter()
        do {
            _ = try await DownloaderUpdates.retryingAfterUpdate(token: .init()) { () async throws -> Int in
                counter.calls += 1; throw NashiError.unsupported("Login-required media")
            }
            XCTFail("The error must reach the caller")
        } catch { XCTAssertEqual(counter.calls, 1, "An unsupported link is not a stale downloader") }
    }

    func testCancelledDownloadsAreNotRetried() async {
        let counter = Counter(), token = CancellationToken()
        token.cancel()
        do {
            _ = try await DownloaderUpdates.retryingAfterUpdate(token: token) { () async throws -> Int in
                counter.calls += 1; throw NashiError.failed("stopped")
            }
            XCTFail("The error must reach the caller")
        } catch { XCTAssertEqual(counter.calls, 1) }
    }

    func testSuccessfulStepsRunOnce() async throws {
        let counter = Counter()
        let value = try await DownloaderUpdates.retryingAfterUpdate(token: .init()) { () async throws -> Int in counter.calls += 1; return 7 }
        XCTAssertEqual(value, 7); XCTAssertEqual(counter.calls, 1)
    }

    func testWeeklyCheckIsSkippedWhenRecent() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "DownloaderUpdatesTests-\(UUID().uuidString)"))
        let recent = Date().addingTimeInterval(-3600)
        defaults.set(recent, forKey: DownloaderUpdates.checkedKey)
        DownloaderUpdates.refreshIfDue(defaults: defaults)
        XCTAssertEqual(defaults.object(forKey: DownloaderUpdates.checkedKey) as? Date, recent, "A check within the week is not repeated")
    }
}
