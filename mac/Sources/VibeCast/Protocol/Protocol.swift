// VibeCast 同步协议 v1 — 与 shared/protocol.md 对齐。
// 前后端唯一对齐来源，修改前请同步更新 shared/protocol.md 与 web/src/ws/protocol.ts。

import Foundation

let kProtocolVersion = 1

struct TargetId: RawRepresentable, Codable, Hashable, Sendable, ExpressibleByStringLiteral {
    let rawValue: String

    static let codex = TargetId(rawValue: "codex")!
    static let workbuddy = TargetId(rawValue: "workbuddy")!
    static let notion = TargetId(rawValue: "notion")!
    static let obsidian = TargetId(rawValue: "obsidian")!
    static let codebuddycn = TargetId(rawValue: "codebuddycn")!
    static let codebuddy = TargetId(rawValue: "codebuddy")!
    static let presetIds: [TargetId] = [.codex, .workbuddy, .notion, .obsidian, .codebuddycn, .codebuddy]

    init?(_ rawValue: String) {
        self.init(rawValue: rawValue)
    }

    init?(rawValue: String) {
        guard TargetId.isValid(rawValue) else { return nil }
        self.rawValue = rawValue
    }

    init(stringLiteral value: String) {
        self.init(rawValue: value)!
    }

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        guard let id = TargetId(rawValue: value) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "非法 targetId: \(value)"))
        }
        self = id
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }

    private static func isValid(_ value: String) -> Bool {
        guard (2...64).contains(value.count) else { return false }
        return value.allSatisfy { ch in
            ch.isLetter || ch.isNumber || ch == "_" || ch == "-" || ch == "."
        }
    }
}

enum ErrorCode: String, Codable, Sendable {
    case unpaired = "UNPAIRED"
    case badToken = "BAD_TOKEN"
    case badMessage = "BAD_MESSAGE"
    case unknownTarget = "UNKNOWN_TARGET"
    case appNotRunning = "APP_NOT_RUNNING"
    case appLaunchFailed = "APP_LAUNCH_FAILED"
    case targetNotFocused = "TARGET_NOT_FOCUSED"
    case noAccessibilityPermission = "NO_ACCESSIBILITY_PERMISSION"
    case staleRevision = "STALE_REVISION"
    case writeFailed = "WRITE_FAILED"
    case sendFailed = "SEND_FAILED"
    case sendUnknown = "SEND_UNKNOWN"
    case rateLimited = "RATE_LIMITED"
    case inactiveSession = "INACTIVE_SESSION"
}

enum TargetStatus: String, Codable, Sendable {
    case focusing
    case focused
    case appNotRunning = "app_not_running"
    case notFocused = "not_focused"
    case noPermission = "no_permission"
    case error
}

// MARK: - 手机 → Mac

struct HelloMessage: Codable, Sendable {
    let type: String
    let protocolVersion: Int
    let clientId: String
    let deviceName: String
    let pairingToken: String
}

struct SelectTargetMessage: Codable, Sendable {
    let type: String
    let sessionId: String
    let targetId: TargetId
}

struct TextSnapshotMessage: Codable, Sendable {
    let type: String
    let sessionId: String
    let targetId: TargetId
    let revision: Int
    let text: String
    let selectionStart: Int
    let selectionEnd: Int
    let isComposing: Bool
    let clientTimestamp: Int64?
}

struct SendRequestMessage: Codable, Sendable {
    let type: String
    let sessionId: String
    let targetId: TargetId
    let revision: Int
}

struct ClearMessage: Codable, Sendable {
    let type: String
    let sessionId: String
    let targetId: TargetId
    let revision: Int
}

struct PingMessage: Codable, Sendable {
    let type: String
    let t: Int64
}

struct GetNetworkSettingsMessage: Codable, Sendable {
    let type: String
}

struct SetNetworkSettingsMessage: Codable, Sendable {
    let type: String
    let settings: NetworkSettings
}

struct CheckPortMessage: Codable, Sendable {
    let type: String
    let bindMode: NetworkBindMode
    let bindAddress: String?
    let port: UInt16
}

// 配置相关（手机配置页 → Mac）
struct GetConfigMessage: Codable, Sendable {
    let type: String
}

struct SetConfigMessage: Codable, Sendable {
    let type: String
    let targetId: TargetId
    let profile: TargetProfile
}

struct TestTargetMessage: Codable, Sendable {
    let type: String
    let targetId: TargetId
}

struct ListRunningAppsMessage: Codable, Sendable {
    let type: String
}

struct GetStatusMessage: Codable, Sendable {
    let type: String
}

struct OpenAccessibilitySettingsMessage: Codable, Sendable {
    let type: String
}

struct CreateTargetMessage: Codable, Sendable {
    let type: String
    let displayName: String
    let bundleId: String?
    let iconDataUrl: String?
}

struct DeleteTargetMessage: Codable, Sendable {
    let type: String
    let targetId: TargetId
}

struct SetTargetEnabledMessage: Codable, Sendable {
    let type: String
    let targetId: TargetId
    let enabled: Bool
}

// MARK: - Mac → 手机

struct TargetInfo: Codable, Sendable {
    let id: TargetId
    let displayName: String
    let iconDataUrl: String?
    let available: Bool
    let clearAfterSend: Bool
    let allowEmpty: Bool
    let syncMode: SyncMode

    init(id: TargetId, displayName: String, available: Bool, clearAfterSend: Bool = false, allowEmpty: Bool = false,
         syncMode: SyncMode = .mirror, iconDataUrl: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.iconDataUrl = iconDataUrl
        self.available = available
        self.clearAfterSend = clearAfterSend
        self.allowEmpty = allowEmpty
        self.syncMode = syncMode
    }
}

struct HelloAckMessage: Codable, Sendable {
    var type = "hello_ack"
    let serverName: String
    let protocolVersion: Int
    let targets: [TargetInfo]
    let accessibilityGranted: Bool
}

struct TargetStatusMessage: Codable, Sendable {
    var type = "target_status"
    let sessionId: String
    let targetId: TargetId
    let status: TargetStatus
    let errorCode: ErrorCode?
    let message: String?
}

struct TextAckMessage: Codable, Sendable {
    var type = "text_ack"
    let sessionId: String
    let targetId: TargetId
    let revision: Int
    let applied: Bool
    let errorCode: ErrorCode?
    var message: String? = nil
    var verified: Bool? = nil
}

struct SendResultMessage: Codable, Sendable {
    var type = "send_result"
    let sessionId: String
    let targetId: TargetId
    let revision: Int
    let success: Bool
    let errorCode: ErrorCode?
    let message: String?
}

struct ErrorMessage: Codable, Sendable {
    var type = "error"
    let errorCode: ErrorCode
    let message: String
}

struct PongMessage: Codable, Sendable {
    var type = "pong"
    let t: Int64
}

// 配置相关（Mac → 手机配置页）
struct ConfigMessage: Codable, Sendable {
    var type = "config"
    let targets: [ConfigTarget]
}

struct TestResultMessage: Codable, Sendable {
    var type = "test_result"
    let targetId: TargetId
    let success: Bool
    let errorCode: ErrorCode?
    let message: String?
}

struct RunningApp: Codable, Sendable {
    let bundleId: String
    let name: String
    let iconDataUrl: String?
}

struct RunningAppsMessage: Codable, Sendable {
    var type = "running_apps"
    let apps: [RunningApp]
}

enum TargetKind: String, Codable, Sendable {
    case preset
    case custom
}

struct ConfigTarget: Codable, Sendable {
    let id: TargetId
    let kind: TargetKind
    let enabled: Bool
    let profile: TargetProfile
}

struct ServerStatusMessage: Codable, Sendable {
    var type = "server_status"
    let serverName: String
    let accessibilityGranted: Bool
}

struct NetworkInterfaceInfo: Codable, Sendable, Equatable {
    let id: String
    let name: String
    let address: String
    let isPreferred: Bool
}

enum NetworkBindMode: String, Codable, Sendable {
    case address
    case all
}

struct NetworkSettings: Codable, Sendable, Equatable {
    var bindMode: NetworkBindMode
    var bindAddress: String?
    var port: UInt16

    static let defaultPort: UInt16 = 8787
}

enum PortAvailabilityStatus: String, Codable, Sendable {
    case available
    case unavailable
    case invalid
}

struct PortCheckResult: Codable, Sendable, Equatable {
    let bindMode: NetworkBindMode
    let bindAddress: String?
    let port: UInt16
    let status: PortAvailabilityStatus
    let message: String?
}

struct NetworkSettingsMessage: Codable, Sendable {
    var type = "network_settings"
    let settings: NetworkSettings
    let interfaces: [NetworkInterfaceInfo]
    let portStatus: PortCheckResult
    let accessUrl: String?
}

struct NetworkInterfacesMessage: Codable, Sendable {
    var type = "network_interfaces"
    let interfaces: [NetworkInterfaceInfo]
}

struct PortCheckMessage: Codable, Sendable {
    var type = "port_check"
    let result: PortCheckResult
}

// MARK: - 解码分发

/// 仅用于先读出 `type` 字段，再按类型二次解码。
struct MessageEnvelope: Codable, Sendable {
    let type: String
}

enum ProtocolError: Error {
    case badMessage(String)
}

enum ProtocolCodec {
    static let decoder = JSONDecoder()
    static let encoder = JSONEncoder()

    static func messageType(of data: Data) throws -> String {
        do {
            return try decoder.decode(MessageEnvelope.self, from: data).type
        } catch {
            throw ProtocolError.badMessage("无法解析消息 type 字段")
        }
    }

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        try encoder.encode(value)
    }
}
