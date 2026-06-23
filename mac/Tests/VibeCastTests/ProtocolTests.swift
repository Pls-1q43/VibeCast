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
        let targets = TargetId.presetIds.map {
            TargetInfo(id: $0, displayName: $0.rawValue, available: true, iconDataUrl: "data:image/png;base64,ZmFrZQ==")
        }
        let ack = HelloAckMessage(serverName: "Mac", protocolVersion: kProtocolVersion,
                                  targets: targets, accessibilityGranted: true,
                                  voiceRelayEnabled: false)
        let data = try ProtocolCodec.encode(ack)
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(obj["type"] as? String, "hello_ack")
        XCTAssertEqual(obj["voiceRelayEnabled"] as? Bool, false)
        XCTAssertEqual((obj["targets"] as? [[String: Any]])?.count, 6)
        let first = (obj["targets"] as! [[String: Any]])[0]
        XCTAssertNotNil(first["clearAfterSend"])
        XCTAssertNotNil(first["allowEmpty"])
        XCTAssertNotNil(first["iconDataUrl"])
        XCTAssertNotNil(first["syncMode"])
    }

    func testAllTargetIdsCovered() {
        XCTAssertEqual(Set(TargetId.presetIds.map(\.rawValue)),
                       ["codex", "workbuddy", "notion", "obsidian", "codebuddycn", "codebuddy"])
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

    func testVoiceStartDecode() throws {
        let json = """
        {"type":"voice_start","sessionId":"v1","targetId":"codex","sampleRate":48000,
         "channels":1,"codec":"pcm_s16le","clientTimestamp":1781760000000}
        """.data(using: .utf8)!
        XCTAssertEqual(try ProtocolCodec.messageType(of: json), "voice_start")
        let msg = try ProtocolCodec.decoder.decode(VoiceStartMessage.self, from: json)
        XCTAssertEqual(msg.sessionId, "v1")
        XCTAssertEqual(msg.targetId, .codex)
        XCTAssertEqual(msg.sampleRate, 48000)
        XCTAssertEqual(msg.channels, 1)
        XCTAssertEqual(msg.codec, "pcm_s16le")
    }

    func testVoiceEnvironmentEncode() throws {
        let env = VoiceEnvironmentMessage(enabled: true,
                                          provider: .shandianshuo,
                                          triggerMode: .toggle,
                                          shortcut: .rightCommand,
                                          installed: true, deviceName: "VibeCast Virtual Mic",
                                          dedicatedInstalled: true,
                                          usingCompatibilityDevice: false,
                                          defaultInputMatches: false, canAutoSwitch: true,
                                          message: nil,
                                          shandianshuoInstalled: true,
                                          shandianshuoAudioDevice: "VibeCast Virtual Mic",
                                          shandianshuoMatchesVirtualMic: true,
                                          shandianshuoMessage: nil)
        let data = try ProtocolCodec.encode(env)
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(obj["type"] as? String, "voice_environment")
        XCTAssertEqual(obj["enabled"] as? Bool, true)
        XCTAssertEqual(obj["provider"] as? String, "shandianshuo")
        XCTAssertEqual(obj["triggerMode"] as? String, "toggle")
        XCTAssertEqual(obj["installed"] as? Bool, true)
        XCTAssertEqual(obj["deviceName"] as? String, "VibeCast Virtual Mic")
        XCTAssertEqual(obj["dedicatedInstalled"] as? Bool, true)
        XCTAssertEqual(obj["usingCompatibilityDevice"] as? Bool, false)
        XCTAssertEqual(obj["canAutoSwitch"] as? Bool, true)
        XCTAssertEqual(obj["shandianshuoAudioDevice"] as? String, "VibeCast Virtual Mic")
        XCTAssertEqual(obj["shandianshuoMatchesVirtualMic"] as? Bool, true)
    }

    func testVoiceSettingsDecode() throws {
        let json = """
        {"type":"set_voice_settings","settings":{"enabled":true,"provider":"typeless",
         "triggerMode":"hold","shortcut":{"modifiers":[],"key":"fn"}}}
        """.data(using: .utf8)!
        XCTAssertEqual(try ProtocolCodec.messageType(of: json), "set_voice_settings")
        let msg = try ProtocolCodec.decoder.decode(SetVoiceSettingsMessage.self, from: json)
        XCTAssertTrue(msg.settings.enabled)
        XCTAssertEqual(msg.settings.provider, .typeless)
        XCTAssertEqual(msg.settings.triggerMode, .hold)
        XCTAssertEqual(msg.settings.shortcut, .fn)
    }
}
