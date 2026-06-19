import XCTest
@testable import VibeCast

final class SendGateTests: XCTestCase {

    func testProceedWhenRevisionApplied() {
        let gate = SendGate()
        // 最终 revision 23 已写入（applied=23）→ 可提交。
        XCTAssertEqual(gate.decide(sessionId: "s", targetId: .codex, revision: 23, appliedRevision: 23), .proceed)
    }

    func testStaleWhenRevisionNotYetApplied() {
        let gate = SendGate()
        // 请求发送 rev 23，但只写入到 22 → 拒绝（PRD 11.4）。
        XCTAssertEqual(gate.decide(sessionId: "s", targetId: .codex, revision: 23, appliedRevision: 22), .staleRevision)
    }

    func testDuplicateAfterCommit() {
        var gate = SendGate()
        XCTAssertEqual(gate.decide(sessionId: "s", targetId: .codex, revision: 5, appliedRevision: 5), .proceed)
        gate.markCommitted(sessionId: "s", targetId: .codex, revision: 5)
        // 同 session+target+revision 再次发送 → 幂等命中（PRD 16.6）。
        XCTAssertEqual(gate.decide(sessionId: "s", targetId: .codex, revision: 5, appliedRevision: 5), .duplicate)
    }

    func testIdempotencyKeyScopedBySessionTargetRevision() {
        var gate = SendGate()
        gate.markCommitted(sessionId: "s1", targetId: .codex, revision: 5)
        // 不同 session / target / revision 不应命中幂等。
        XCTAssertFalse(gate.isCommitted(sessionId: "s2", targetId: .codex, revision: 5))
        XCTAssertFalse(gate.isCommitted(sessionId: "s1", targetId: .workbuddy, revision: 5))
        XCTAssertFalse(gate.isCommitted(sessionId: "s1", targetId: .codex, revision: 6))
        XCTAssertTrue(gate.isCommitted(sessionId: "s1", targetId: .codex, revision: 5))
    }

    func testKeyFormat() {
        XCTAssertEqual(SendGate.key(sessionId: "abc", targetId: .notion, revision: 9), "abc|notion|9")
    }
}
