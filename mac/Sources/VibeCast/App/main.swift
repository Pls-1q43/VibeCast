// VibeCast 菜单栏服务入口。
// M0 阶段：仅验证协议模型可编译、二进制可启动。
// 后续里程碑：M2 接入 HTTP+WebSocket 服务，挂菜单栏 UI。

import Foundation

FileHandle.standardError.write(Data("VibeCast \(kProtocolVersion) — M0 skeleton\n".utf8))

// 编译期自检：确保协议类型可用。
let bootTargets = TargetId.allCases.map { TargetInfo(id: $0, displayName: $0.rawValue, available: true) }
let bootAck = HelloAckMessage(serverName: "VibeCast", protocolVersion: kProtocolVersion, targets: bootTargets, accessibilityGranted: false)
if let data = try? ProtocolCodec.encode(bootAck), let s = String(data: data, encoding: .utf8) {
    FileHandle.standardError.write(Data("hello_ack sample: \(s)\n".utf8))
}
