// RFC 6455 WebSocket 帧编解码（纯逻辑，可单测）。
// 仅实现本产品所需：text / close / ping / pong；客户端→服务端帧必带 mask。

import Foundation
import CryptoKit

enum WSOpcode: UInt8 {
    case continuation = 0x0
    case text = 0x1
    case binary = 0x2
    case close = 0x8
    case ping = 0x9
    case pong = 0xA
}

struct WSFrame {
    let fin: Bool
    let opcode: WSOpcode
    let payload: Data
}

enum WSDecodeResult {
    /// 数据不足，需等待更多字节。
    case incomplete
    /// 解出一帧，并返回消耗的字节数。
    case frame(WSFrame, consumed: Int)
    /// 协议错误，应关闭连接。
    case error(String)
}

enum WebSocketCodec {

    /// 从缓冲区头部尝试解析一帧。不修改入参。
    static func decode(_ buffer: Data) -> WSDecodeResult {
        guard buffer.count >= 2 else { return .incomplete }
        let bytes = [UInt8](buffer)

        let fin = (bytes[0] & 0x80) != 0
        let rsv = bytes[0] & 0x70
        if rsv != 0 { return .error("RSV 位非零") }
        guard let opcode = WSOpcode(rawValue: bytes[0] & 0x0F) else {
            return .error("未知 opcode")
        }

        let masked = (bytes[1] & 0x80) != 0
        var payloadLen = Int(bytes[1] & 0x7F)
        var offset = 2

        if payloadLen == 126 {
            guard bytes.count >= offset + 2 else { return .incomplete }
            payloadLen = Int(bytes[offset]) << 8 | Int(bytes[offset + 1])
            offset += 2
        } else if payloadLen == 127 {
            guard bytes.count >= offset + 8 else { return .incomplete }
            var len = 0
            for i in 0..<8 { len = (len << 8) | Int(bytes[offset + i]) }
            payloadLen = len
            offset += 8
        }

        // 客户端发往服务端的帧必须 mask（RFC 6455 §5.1）。
        guard masked else { return .error("客户端帧未 mask") }

        guard bytes.count >= offset + 4 else { return .incomplete }
        let maskKey = Array(bytes[offset..<offset + 4])
        offset += 4

        guard bytes.count >= offset + payloadLen else { return .incomplete }
        var payload = [UInt8](repeating: 0, count: payloadLen)
        for i in 0..<payloadLen {
            payload[i] = bytes[offset + i] ^ maskKey[i % 4]
        }
        offset += payloadLen

        return .frame(WSFrame(fin: fin, opcode: opcode, payload: Data(payload)), consumed: offset)
    }

    /// 服务端→客户端编码（不 mask）。
    static func encode(opcode: WSOpcode, payload: Data, fin: Bool = true) -> Data {
        var out = Data()
        out.append((fin ? 0x80 : 0x00) | opcode.rawValue)

        let len = payload.count
        if len < 126 {
            out.append(UInt8(len))
        } else if len <= 0xFFFF {
            out.append(126)
            out.append(UInt8((len >> 8) & 0xFF))
            out.append(UInt8(len & 0xFF))
        } else {
            out.append(127)
            for shift in stride(from: 56, through: 0, by: -8) {
                out.append(UInt8((len >> shift) & 0xFF))
            }
        }
        out.append(payload)
        return out
    }

    static func encodeText(_ s: String) -> Data {
        encode(opcode: .text, payload: Data(s.utf8))
    }

    static func encodeClose(code: UInt16 = 1000) -> Data {
        var p = Data()
        p.append(UInt8(code >> 8))
        p.append(UInt8(code & 0xFF))
        return encode(opcode: .close, payload: p)
    }

    /// 计算 Sec-WebSocket-Accept（RFC 6455 §4.2.2）。
    static func acceptKey(for clientKey: String) -> String {
        let magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
        let combined = clientKey + magic
        let digest = Insecure.SHA1.hash(data: Data(combined.utf8))
        return Data(digest).base64EncodedString()
    }
}
