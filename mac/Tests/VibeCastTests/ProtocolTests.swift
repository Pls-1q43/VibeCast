import XCTest
@testable import VibeCast

final class ProtocolTests: XCTestCase {

    func testTextSnapshotDecode() throws {
        let json = """
        {
          "type": "text_snapshot",
          "sessionId": "s1",
          "targetId": "codex",
          "revision": 23,
          "text": "帮我检查当前分支中的错误。",
          "selectionStart": 13,
          "selectionEnd": 13,
          "isComposing": false,
          "clientTimestamp": 1781760000000
        }
        """.data(using: .utf8)!
        XCTAssertEqual(try ProtocolCodec.messageType(of: json), "text_snapshot")
        let msg = try ProtocolCodec.decoder.decode(TextSnapshotMessage.self, from: json)
        XCTAssertEqual(msg.targetId, .codex)
        XCTAssertEqual(msg.revision, 23)
        XCTAssertEqual(msg.text, "帮我检查当前分支中的错误。")
        XCTAssertFalse(msg.isComposing)
    }

    func testHelloAckEncodeRoundTrip() throws {
        let targets = TargetId.presetIds.map { TargetInfo(id: $0, displayName: $0.rawValue, available: true) }
        let ack = HelloAckMessage(serverName: "Mac", protocolVersion: kProtocolVersion, targets: targets, accessibilityGranted: true)
        let data = try ProtocolCodec.encode(ack)
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(obj["type"] as? String, "hello_ack")
        XCTAssertEqual((obj["targets"] as? [[String: Any]])?.count, 4)
        let first = (obj["targets"] as! [[String: Any]])[0]
        XCTAssertNotNil(first["clearAfterSend"])
        XCTAssertNotNil(first["allowEmpty"])
    }

    func testAllTargetIdsCovered() {
        XCTAssertEqual(Set(TargetId.presetIds.map(\.rawValue)),
                       ["codex", "workbuddy", "notion", "codebuddy"])
    }

    func testCustomTargetIdDecode() throws {
        let json = """
        {"type":"select_target","sessionId":"s1","targetId":"custom_textedit"}
        """.data(using: .utf8)!
        let msg = try ProtocolCodec.decoder.decode(SelectTargetMessage.self, from: json)
        XCTAssertEqual(msg.targetId.rawValue, "custom_textedit")
    }

    func testInvalidTargetIdRejected() {
        let json = """
        {"type":"select_target","sessionId":"s1","targetId":"bad target"}
        """.data(using: .utf8)!
        XCTAssertThrowsError(try ProtocolCodec.decoder.decode(SelectTargetMessage.self, from: json))
    }

    func testConfigMessageEncodesTargetsArray() throws {
        let entry = ConfigTarget(id: .codex, kind: .preset, enabled: true, profile: .defaultFor(.codex))
        let data = try ProtocolCodec.encode(ConfigMessage(targets: [entry]))
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(obj["type"] as? String, "config")
        XCTAssertEqual((obj["targets"] as? [[String: Any]])?.count, 1)
    }

    func testSendResultFailureDecode() throws {
        let json = """
        {"type":"send_result","sessionId":"s1","targetId":"codex","revision":23,
         "success":false,"errorCode":"TARGET_NOT_FOCUSED","message":"无法确认 Codex 输入框焦点"}
        """.data(using: .utf8)!
        let msg = try ProtocolCodec.decoder.decode(SendResultMessage.self, from: json)
        XCTAssertFalse(msg.success)
        XCTAssertEqual(msg.errorCode, .targetNotFocused)
    }
}
