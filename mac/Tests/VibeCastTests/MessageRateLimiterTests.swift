import XCTest
@testable import VibeCast

final class MessageRateLimiterTests: XCTestCase {

    func testAllowsEventsWithinLimit() {
        var limiter = MessageRateLimiter(windowMs: 1_000, maxEvents: 3)
        XCTAssertTrue(limiter.allow(nowMs: 1_000))
        XCTAssertTrue(limiter.allow(nowMs: 1_100))
        XCTAssertTrue(limiter.allow(nowMs: 1_200))
    }

    func testRejectsWhenWindowIsFull() {
        var limiter = MessageRateLimiter(windowMs: 1_000, maxEvents: 2)
        XCTAssertTrue(limiter.allow(nowMs: 1_000))
        XCTAssertTrue(limiter.allow(nowMs: 1_100))
        XCTAssertFalse(limiter.allow(nowMs: 1_200))
    }

    func testWindowSlidesForward() {
        var limiter = MessageRateLimiter(windowMs: 1_000, maxEvents: 2)
        XCTAssertTrue(limiter.allow(nowMs: 1_000))
        XCTAssertTrue(limiter.allow(nowMs: 1_100))
        XCTAssertTrue(limiter.allow(nowMs: 2_101))
    }
}
