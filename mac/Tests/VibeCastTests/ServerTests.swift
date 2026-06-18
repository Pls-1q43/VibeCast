import XCTest
@testable import VibeCast

final class ServerTests: XCTestCase {

    // MARK: - WebSocket 帧

    func testAcceptKeyRFCExample() {
        // RFC 6455 §1.3 标准示例。
        XCTAssertEqual(WebSocketCodec.acceptKey(for: "dGhlIHNhbXBsZSBub25jZQ=="),
                       "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=")
    }

    func testDecodeMaskedTextFrame() {
        // 客户端帧：fin+text, masked, payload "Hi"
        let mask: [UInt8] = [0x37, 0xfa, 0x21, 0x3d]
        let payload: [UInt8] = [0x48, 0x69] // "Hi"
        var masked = [UInt8]()
        for (i, b) in payload.enumerated() { masked.append(b ^ mask[i % 4]) }
        var frame: [UInt8] = [0x81, 0x82] // fin+text, masked + len 2
        frame.append(contentsOf: mask)
        frame.append(contentsOf: masked)

        switch WebSocketCodec.decode(Data(frame)) {
        case .frame(let f, let consumed):
            XCTAssertEqual(f.opcode, .text)
            XCTAssertTrue(f.fin)
            XCTAssertEqual(String(data: f.payload, encoding: .utf8), "Hi")
            XCTAssertEqual(consumed, frame.count)
        default:
            XCTFail("应解出一帧")
        }
    }

    func testDecodeIncomplete() {
        if case .incomplete = WebSocketCodec.decode(Data([0x81])) {} else {
            XCTFail("半帧应判定 incomplete")
        }
    }

    func testRejectUnmaskedClientFrame() {
        // 未 mask 的客户端帧应报错。
        let frame: [UInt8] = [0x81, 0x02, 0x48, 0x69]
        if case .error = WebSocketCodec.decode(Data(frame)) {} else {
            XCTFail("未 mask 应报错")
        }
    }

    func testEncodeTextRoundTripLength() {
        let data = WebSocketCodec.encodeText("hello")
        XCTAssertEqual(data[0], 0x81)       // fin + text
        XCTAssertEqual(data[1], 0x05)       // len 5, 服务端不 mask
        XCTAssertEqual(data.count, 7)
    }

    func testEncodeMediumPayloadUses126() {
        let big = String(repeating: "x", count: 200)
        let data = WebSocketCodec.encodeText(big)
        XCTAssertEqual(data[1], 126)
        let len = Int(data[2]) << 8 | Int(data[3])
        XCTAssertEqual(len, 200)
    }

    // MARK: - HTTP 解析

    func testParseGetWithQuery() {
        let raw = "GET /?token=abc HTTP/1.1\r\nHost: x\r\n\r\n"
        let req = HTTPRequest.parse(Data(raw.utf8))
        XCTAssertEqual(req?.method, "GET")
        XCTAssertEqual(req?.path, "/")
        XCTAssertEqual(req?.rawTarget, "/?token=abc")
    }

    func testParseWebSocketUpgrade() {
        let raw = "GET /ws HTTP/1.1\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: k\r\n\r\n"
        let req = HTTPRequest.parse(Data(raw.utf8))
        XCTAssertTrue(req?.isWebSocketUpgrade ?? false)
        XCTAssertEqual(req?.header("sec-websocket-key"), "k")
    }

    func testParseIncompleteHeaderReturnsNil() {
        XCTAssertNil(HTTPRequest.parse(Data("GET / HTTP/1.1\r\nHost: x".utf8)))
    }

    // MARK: - 配对令牌

    func testPairingValidateRejectsWrong() {
        XCTAssertFalse(Pairing.validate(nil))
        XCTAssertFalse(Pairing.validate(""))
        XCTAssertFalse(Pairing.validate("definitely-wrong-token"))
    }

    func testPairingValidateAcceptsCurrent() {
        XCTAssertTrue(Pairing.validate(Pairing.token))
    }
}
