import Foundation

struct ShanDianShuoVoiceStatus: Equatable {
    let installed: Bool
    let audioDevice: String?
    let matchesVirtualMic: Bool
    let message: String?
}

enum ShanDianShuoVoiceBridge {
    static var defaultConfigURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Shandianshuo/config.json")
    }

    static func status(virtualDeviceName: String?, configURL: URL = defaultConfigURL) -> ShanDianShuoVoiceStatus {
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            return ShanDianShuoVoiceStatus(installed: false, audioDevice: nil, matchesVirtualMic: false,
                                          message: "未检测到闪电说配置")
        }
        guard let audioDevice = readAudioDevice(configURL: configURL) else {
            return ShanDianShuoVoiceStatus(installed: true, audioDevice: nil, matchesVirtualMic: false,
                                          message: "无法读取闪电说麦克风配置")
        }
        guard let virtualDeviceName else {
            return ShanDianShuoVoiceStatus(installed: true, audioDevice: audioDevice, matchesVirtualMic: false,
                                          message: "需先检测到虚拟麦克风")
        }
        let matches = audioDevice == virtualDeviceName
        return ShanDianShuoVoiceStatus(installed: true, audioDevice: audioDevice, matchesVirtualMic: matches,
                                      message: matches ? nil : "闪电说当前未绑定到虚拟麦克风")
    }

    @discardableResult
    static func bindToVirtualMic(_ deviceName: String, configURL: URL = defaultConfigURL) -> ShanDianShuoVoiceStatus {
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            return ShanDianShuoVoiceStatus(installed: false, audioDevice: nil, matchesVirtualMic: false,
                                          message: "未检测到闪电说配置")
        }
        do {
            let data = try Data(contentsOf: configURL)
            guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return ShanDianShuoVoiceStatus(installed: true, audioDevice: nil, matchesVirtualMic: false,
                                              message: "闪电说配置格式无法识别")
            }
            try backupConfigIfNeeded(configURL)
            root["audio_device"] = deviceName
            let next = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
            try next.write(to: configURL, options: .atomic)
            return ShanDianShuoVoiceStatus(installed: true, audioDevice: deviceName, matchesVirtualMic: true,
                                          message: "已将闪电说麦克风绑定到 \(deviceName)")
        } catch {
            return ShanDianShuoVoiceStatus(installed: true, audioDevice: readAudioDevice(configURL: configURL),
                                          matchesVirtualMic: false,
                                          message: "写入闪电说配置失败：\(error.localizedDescription)")
        }
    }

    private static func readAudioDevice(configURL: URL) -> String? {
        guard let data = try? Data(contentsOf: configURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return root["audio_device"] as? String
    }

    private static func backupConfigIfNeeded(_ configURL: URL) throws {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let backupURL = configURL.deletingLastPathComponent()
            .appendingPathComponent("config.json.vibecast-backup-\(formatter.string(from: Date()))")
        try FileManager.default.copyItem(at: configURL, to: backupURL)
    }
}
