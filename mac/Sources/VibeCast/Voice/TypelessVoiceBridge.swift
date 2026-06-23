import Foundation

struct TypelessVoiceStatus: Equatable {
    let installed: Bool
    let audioDevice: String?
    let matchesVirtualMic: Bool
    let message: String?
    let originalAudioDevice: String?
}

enum TypelessVoiceBridge {
    private static let candidateFileNames = [
        "config.json",
        "settings.json",
        "preferences.json",
        "Preferences",
        "Local State"
    ]

    private static let audioDeviceKeyPaths = [
        ["audio_device"],
        ["audioDevice"],
        ["audioDeviceName"],
        ["audioInputDevice"],
        ["audioInputDeviceName"],
        ["inputDevice"],
        ["inputDeviceName"],
        ["microphone"],
        ["microphoneName"],
        ["microphoneDevice"],
        ["microphoneDeviceName"],
        ["selectedMicrophone"],
        ["selectedMicrophoneName"],
        ["recordingDevice"],
        ["recordingDeviceName"],
        ["settings", "audio_device"],
        ["settings", "audioDeviceName"],
        ["settings", "microphoneDeviceName"],
        ["audio", "inputDeviceName"],
        ["audio", "microphoneDeviceName"],
        ["preferences", "microphoneDeviceName"]
    ]

    static var defaultConfigURLs: [URL] {
        let appSupport = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support")
        let dirs = [
            appSupport.appendingPathComponent("Typeless"),
            appSupport.appendingPathComponent("typeless"),
            appSupport.appendingPathComponent("com.typeless.Typeless"),
            appSupport.appendingPathComponent("com.typeless.desktop"),
            appSupport.appendingPathComponent("com.typeless.app")
        ]
        var urls: [URL] = []
        for dir in dirs {
            urls.append(contentsOf: candidateConfigURLs(in: dir))
        }
        return uniqueURLs(urls)
    }

    static func status(virtualDeviceName: String?, configURLs: [URL] = defaultConfigURLs) -> TypelessVoiceStatus {
        guard let configURL = firstExistingConfigURL(configURLs) else {
            return TypelessVoiceStatus(installed: false, audioDevice: nil, matchesVirtualMic: false,
                                       message: "未检测到 Typeless 麦克风配置", originalAudioDevice: nil)
        }
        guard let audioDevice = readAudioDevice(configURL: configURL) else {
            return TypelessVoiceStatus(installed: true, audioDevice: nil, matchesVirtualMic: false,
                                       message: "无法识别 Typeless 麦克风字段", originalAudioDevice: nil)
        }
        guard let virtualDeviceName else {
            return TypelessVoiceStatus(installed: true, audioDevice: audioDevice, matchesVirtualMic: false,
                                       message: "需先检测到虚拟麦克风", originalAudioDevice: nil)
        }
        let matches = audioDevice == virtualDeviceName
        return TypelessVoiceStatus(installed: true, audioDevice: audioDevice, matchesVirtualMic: matches,
                                   message: matches ? nil : "Typeless 当前未绑定到虚拟麦克风",
                                   originalAudioDevice: nil)
    }

    @discardableResult
    static func bindToVirtualMic(_ deviceName: String, originalAudioDevice: String? = nil,
                                 configURLs: [URL] = defaultConfigURLs) -> TypelessVoiceStatus {
        guard let configURL = firstExistingConfigURL(configURLs) else {
            return TypelessVoiceStatus(installed: false, audioDevice: nil, matchesVirtualMic: false,
                                       message: "未检测到 Typeless 麦克风配置", originalAudioDevice: originalAudioDevice)
        }
        do {
            let data = try Data(contentsOf: configURL)
            guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return TypelessVoiceStatus(installed: true, audioDevice: nil, matchesVirtualMic: false,
                                           message: "Typeless 配置格式无法识别", originalAudioDevice: originalAudioDevice)
            }
            guard let current = readAudioDevice(root: root) else {
                return TypelessVoiceStatus(installed: true, audioDevice: nil, matchesVirtualMic: false,
                                           message: "未找到可写入的 Typeless 麦克风字段",
                                           originalAudioDevice: originalAudioDevice)
            }
            try backupConfigIfNeeded(configURL)
            var updated = false
            for path in audioDeviceKeyPaths where stringValue(in: root, at: path) != nil {
                setString(deviceName, in: &root, at: path)
                updated = true
            }
            guard updated else {
                return TypelessVoiceStatus(installed: true, audioDevice: current, matchesVirtualMic: false,
                                           message: "未找到可写入的 Typeless 麦克风字段",
                                           originalAudioDevice: originalAudioDevice)
            }
            let next = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
            try next.write(to: configURL, options: .atomic)
            return TypelessVoiceStatus(installed: true, audioDevice: deviceName, matchesVirtualMic: true,
                                       message: "已将 Typeless 麦克风绑定到 \(deviceName)",
                                       originalAudioDevice: originalAudioDevice ?? current)
        } catch {
            return TypelessVoiceStatus(installed: true, audioDevice: readAudioDevice(configURL: configURL),
                                       matchesVirtualMic: false,
                                       message: "写入 Typeless 配置失败：\(error.localizedDescription)",
                                       originalAudioDevice: originalAudioDevice)
        }
    }

    @discardableResult
    static func restoreIfManaged(originalAudioDevice: String?, virtualAudioDevice: String?,
                                 configURLs: [URL] = defaultConfigURLs) -> Bool {
        guard let originalAudioDevice, let virtualAudioDevice,
              let configURL = firstExistingConfigURL(configURLs),
              let data = try? Data(contentsOf: configURL),
              var root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        var updated = false
        for path in audioDeviceKeyPaths where stringValue(in: root, at: path) == virtualAudioDevice {
            setString(originalAudioDevice, in: &root, at: path)
            updated = true
        }
        guard updated else { return false }
        do {
            try backupConfigIfNeeded(configURL)
            let next = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
            try next.write(to: configURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    private static func readAudioDevice(configURL: URL) -> String? {
        guard let data = try? Data(contentsOf: configURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return readAudioDevice(root: root)
    }

    private static func readAudioDevice(root: [String: Any]) -> String? {
        for path in audioDeviceKeyPaths {
            if let value = stringValue(in: root, at: path), !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func stringValue(in root: [String: Any], at path: [String]) -> String? {
        guard !path.isEmpty else { return nil }
        var current: Any = root
        for key in path {
            guard let dict = current as? [String: Any],
                  let next = dict[key] else {
                return nil
            }
            current = next
        }
        return current as? String
    }

    private static func setString(_ value: String, in root: inout [String: Any], at path: [String]) {
        guard let first = path.first else { return }
        if path.count == 1 {
            root[first] = value
            return
        }
        var child = root[first] as? [String: Any] ?? [:]
        setString(value, in: &child, at: Array(path.dropFirst()))
        root[first] = child
    }

    private static func firstExistingConfigURL(_ urls: [URL]) -> URL? {
        urls.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static func candidateConfigURLs(in directory: URL) -> [URL] {
        var urls = candidateFileNames.map { directory.appendingPathComponent($0) }
        guard FileManager.default.fileExists(atPath: directory.path),
              let enumerator = FileManager.default.enumerator(at: directory,
                                                              includingPropertiesForKeys: [.isRegularFileKey],
                                                              options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
            return urls
        }
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true else {
                continue
            }
            let name = url.lastPathComponent.lowercased()
            if name.hasSuffix(".json") || name == "preferences" || name == "local state" {
                urls.append(url)
            }
        }
        return urls
    }

    private static func uniqueURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []
        for url in urls where !seen.contains(url.path) {
            seen.insert(url.path)
            result.append(url)
        }
        return result
    }

    private static func backupConfigIfNeeded(_ configURL: URL) throws {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let backupURL = configURL.deletingLastPathComponent()
            .appendingPathComponent("\(configURL.lastPathComponent).vibecast-backup-\(formatter.string(from: Date()))")
        try FileManager.default.copyItem(at: configURL, to: backupURL)
    }
}
