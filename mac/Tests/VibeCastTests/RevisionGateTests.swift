import XCTest
@testable import VibeCast

final class RevisionGateTests: XCTestCase {

    func testAcceptsHigherRevisionOnly() {
        var gate = RevisionGate()
        XCTAssertTrue(gate.shouldApply(.codex, revision: 1))
        gate.markApplied(.codex, revision: 1)
        XCTAssertFalse(gate.shouldApply(.codex, revision: 1)) // 同版本拒绝
        XCTAssertTrue(gate.shouldApply(.codex, revision: 2))
    }

    func testStaleRevisionRejectedAfterNewer() {
        var gate = RevisionGate()
        gate.markApplied(.codex, revision: 10)
        // 迟到的旧包（rev 7）必须被拒绝（PRD 12.1）。
        XCTAssertFalse(gate.shouldApply(.codex, revision: 7))
        XCTAssertEqual(gate.current(.codex), 10)
    }

    func testMarkAppliedOnlyMovesForward() {
        var gate = RevisionGate()
        gate.markApplied(.codex, revision: 5)
        gate.markApplied(.codex, revision: 3) // 旧值不应回退
        XCTAssertEqual(gate.current(.codex), 5)
    }

    func testPerTargetIndependence() {
        var gate = RevisionGate()
        gate.markApplied(.codex, revision: 18)
        gate.markApplied(.workbuddy, revision: 2)
        // 各目标独立计数（PRD 12.1）。
        XCTAssertEqual(gate.current(.codex), 18)
        XCTAssertEqual(gate.current(.workbuddy), 2)
        XCTAssertTrue(gate.shouldApply(.workbuddy, revision: 3))
        XCTAssertFalse(gate.shouldApply(.codex, revision: 3))
    }

    func testResetOnNewSession() {
        var gate = RevisionGate()
        gate.markApplied(.codex, revision: 41)
        gate.reset(.codex)
        // 新会话后 rev 从 1 重新生效（PRD 12.3）。
        XCTAssertEqual(gate.current(.codex), 0)
        XCTAssertTrue(gate.shouldApply(.codex, revision: 1))
    }
}
