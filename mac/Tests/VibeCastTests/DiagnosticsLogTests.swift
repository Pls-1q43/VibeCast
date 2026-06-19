import XCTest
@testable import VibeCast

final class DiagnosticsLogTests: XCTestCase {

    func testTextDigestNeverLeaksContent() {
        let secret = "这是一段绝不应出现在日志中的私密文本"
        let digest = DiagnosticsLog.textDigest(secret)
        // 摘要只含长度与短哈希，不含原文任何子串。
        XCTAssertFalse(digest.contains("私密"))
        XCTAssertTrue(digest.contains("len=\(secret.count)"))
        XCTAssertTrue(digest.contains("sha="))
    }

    func testTextDigestStableForSameInput() {
        let a = DiagnosticsLog.textDigest("hello")
        let b = DiagnosticsLog.textDigest("hello")
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, DiagnosticsLog.textDigest("hello!"))
    }

    func testRedactPairingToken() {
        let line = "paired Phone token=X6I1kXZEMAdpEza1EKJ9cSb7mYKwjxU-"
        let redacted = DiagnosticsLog.redact(line)
        XCTAssertFalse(redacted.contains("X6I1kXZEMAdpEza1EKJ9cSb7mYKwjxU-"))
        XCTAssertTrue(redacted.contains("<redacted>"))
    }

    func testRedactPairingTokenJSONStyle() {
        let line = "hello { \"pairingToken\": \"secret-abc-123\" }"
        let redacted = DiagnosticsLog.redact(line)
        XCTAssertFalse(redacted.contains("secret-abc-123"))
    }

    func testRedactLeavesNonSensitiveIntact() {
        let line = "text_applied codex rev=23 len=18 via=axvalue"
        XCTAssertEqual(DiagnosticsLog.redact(line), line)
    }
}
