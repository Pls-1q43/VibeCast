import Foundation
import AppKit

struct TypelessVoiceStatus: Equatable {
    let installed: Bool
    let audioDevice: String?
    let matchesVirtualMic: Bool
    let message: String?
    let originalAudioDevice: String?
}

enum TypelessVoiceBridge {
    private static let selectedMicrophonePath = ["selectedMicrophoneDevice"]
    private static let microphoneDevicesPath = ["microphoneDevices"]
    private static let preferredBuiltInMicIdPath = ["preferredBuiltInMicId"]
    private static let defaultDeviceId = "default"
    private static let bundleIdentifier = "now.typeless.desktop"

    private static let candidateFileNames = [
        "app-settings.json",
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
        ["audioDeviceId"],
        ["audioInputDevice"],
        ["audioInputDeviceId"],
        ["audioInputDeviceName"],
        ["inputDevice"],
        ["inputDeviceId"],
        ["inputDeviceName"],
        ["microphone"],
        ["microphoneId"],
        ["microphone_id"],
        ["microphoneName"],
        ["microphoneDevice"],
        ["microphoneDeviceId"],
        ["microphoneDeviceName"],
        ["selectedMicrophone"],
        ["selectedMicrophoneId"],
        ["selectedMicrophoneName"],
        ["recordingDevice"],
        ["recordingDeviceId"],
        ["recordingDeviceName"],
        ["settings", "audio_device"],
        ["settings", "audioDeviceId"],
        ["settings", "audioDeviceName"],
        ["settings", "microphoneDeviceId"],
        ["settings", "microphoneDeviceName"],
        ["audio", "inputDeviceId"],
        ["audio", "inputDeviceName"],
        ["audio", "microphoneDeviceId"],
        ["audio", "microphoneDeviceName"],
        ["preferences", "microphoneDeviceId"],
        ["preferences", "microphoneDeviceName"]
    ]

    static var defaultConfigURLs: [URL] {
        let appSupport = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support")
        let dirs = [
            appSupport.appendingPathComponent("Typeless"),
            appSupport.appendingPathComponent("now.typeless.desktop"),
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

    static func status(virtualDeviceName: String?, virtualDeviceUID: String? = nil,
                       configURLs: [URL] = defaultConfigURLs) -> TypelessVoiceStatus {
        let existing = existingConfigURLs(configURLs)
        guard !existing.isEmpty else {
            return TypelessVoiceStatus(installed: false, audioDevice: nil, matchesVirtualMic: false,
                                       message: "未检测到 Typeless 麦克风配置", originalAudioDevice: nil)
        }
        guard let config = firstConfigWithAudioDevice(existing) else {
            return TypelessVoiceStatus(installed: true, audioDevice: nil, matchesVirtualMic: false,
                                       message: "无法识别 Typeless 麦克风字段（已扫描 \(existing.count) 个配置文件）",
                                       originalAudioDevice: nil)
        }
        guard let virtualDeviceName else {
            return TypelessVoiceStatus(installed: true, audioDevice: config.audioDevice, matchesVirtualMic: false,
                                       message: "需先检测到虚拟麦克风", originalAudioDevice: nil)
        }
        let matches = config.values.contains { value in
            value == virtualDeviceName || value == defaultDeviceId || (virtualDeviceUID != nil && value == virtualDeviceUID)
        }
        return TypelessVoiceStatus(installed: true, audioDevice: config.audioDevice, matchesVirtualMic: matches,
                                   message: matches ? nil : "Typeless 当前未绑定到虚拟麦克风",
                                   originalAudioDevice: nil)
    }

    @discardableResult
    static func bindToVirtualMic(_ deviceName: String, deviceUID: String? = nil, originalAudioDevice: String? = nil,
                                 reloadRunningApp: Bool = false,
                                 configURLs: [URL] = defaultConfigURLs) -> TypelessVoiceStatus {
        let existing = existingConfigURLs(configURLs)
        guard !existing.isEmpty else {
            return TypelessVoiceStatus(installed: false, audioDevice: nil, matchesVirtualMic: false,
                                       message: "未检测到 Typeless 麦克风配置", originalAudioDevice: originalAudioDevice)
        }
        guard let config = firstConfigWithAudioDevice(existing) else {
            return TypelessVoiceStatus(installed: true, audioDevice: nil, matchesVirtualMic: false,
                                       message: "未找到可写入的 Typeless 麦克风字段（已扫描 \(existing.count) 个配置文件）",
                                       originalAudioDevice: originalAudioDevice)
        }

        do {
            var root = config.root
            try backupConfigIfNeeded(config.url)
            var updated = false

            if let selected = selectedMicrophoneDevice(for: deviceName, deviceUID: deviceUID, in: root) {
                setValue(selected, in: &root, at: selectedMicrophonePath)
                updated = true
            } else if hasKey(in: root, at: selectedMicrophonePath) || arrayValue(in: root, at: microphoneDevicesPath) != nil {
                let defaultDevice = defaultMicrophoneDevice(for: deviceName)
                setValue(defaultDevice, in: &root, at: selectedMicrophonePath)
                updated = ensureDefaultMicrophoneDevice(defaultDevice, in: &root) || updated
                updated = true
            }

            for path in audioDeviceStringPaths(in: root) where stringValue(in: root, at: path) != nil {
                let replacement = isIdentifierPath(path) ? (deviceUID ?? deviceName) : deviceName
                setValue(replacement, in: &root, at: path)
                updated = true
            }
            if hasKey(in: root, at: preferredBuiltInMicIdPath) {
                setValue(NSNull(), in: &root, at: preferredBuiltInMicIdPath)
                updated = true
            }

            guard updated else {
                return TypelessVoiceStatus(installed: true, audioDevice: config.audioDevice, matchesVirtualMic: false,
                                           message: "未找到可写入的 Typeless 麦克风字段",
                                           originalAudioDevice: originalAudioDevice)
            }

            let next = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
            try next.write(to: config.url, options: .atomic)
            let boundToDefault = dictionaryValue(in: root, at: selectedMicrophonePath)?["deviceId"] as? String == defaultDeviceId
            let reload = reloadRunningApp ? reloadRunningTypelessIfNeeded() : nil
            let reloadMessage: String
            switch reload {
            case .some(true):
                reloadMessage = "；已重启 Typeless 以加载新麦克风配置"
            case .some(false):
                reloadMessage = "；请手动重启 Typeless 以加载新麦克风配置"
            case .none:
                reloadMessage = ""
            }
            return TypelessVoiceStatus(installed: true, audioDevice: boundToDefault ? "系统默认麦克风" : deviceName, matchesVirtualMic: true,
                                       message: boundToDefault
                                            ? "已将 Typeless 麦克风绑定到系统默认输入；VibeCast 语音时会临时切到 \(deviceName)\(reloadMessage)"
                                            : "已将 Typeless 麦克风绑定到 \(deviceName)\(reloadMessage)",
                                       originalAudioDevice: originalAudioDevice ?? config.audioDevice)
        } catch {
            return TypelessVoiceStatus(installed: true, audioDevice: readAudioDevice(configURL: config.url),
                                       matchesVirtualMic: false,
                                       message: "写入 Typeless 配置失败：\(error.localizedDescription)",
                                       originalAudioDevice: originalAudioDevice)
        }
    }

    @discardableResult
    static func restoreIfManaged(originalAudioDevice: String?, virtualAudioDevice: String?,
                                 configURLs: [URL] = defaultConfigURLs) -> Bool {
        guard let originalAudioDevice, let virtualAudioDevice,
              let config = firstConfigWithAudioDevice(existingConfigURLs(configURLs)) else {
            return false
        }
        var root = config.root
        var updated = false

        if let selected = dictionaryValue(in: root, at: selectedMicrophonePath),
           (microphoneDeviceMatches(selected, deviceName: virtualAudioDevice, deviceUID: nil) || selected["deviceId"] as? String == defaultDeviceId),
           let original = selectedMicrophoneDevice(for: originalAudioDevice, deviceUID: nil, in: root) {
            setValue(original, in: &root, at: selectedMicrophonePath)
            updated = true
        }

        for path in audioDeviceStringPaths(in: root) where stringValue(in: root, at: path) == virtualAudioDevice {
            setValue(originalAudioDevice, in: &root, at: path)
            updated = true
        }

        guard updated else { return false }
        do {
            try backupConfigIfNeeded(config.url)
            let next = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
            try next.write(to: config.url, options: .atomic)
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
        return audioDeviceValues(in: root).first
    }

    private static func selectedMicrophoneDevice(for deviceName: String, deviceUID: String?, in root: [String: Any]) -> [String: Any]? {
        guard let devices = arrayValue(in: root, at: microphoneDevicesPath) else { return nil }
        return devices.first { microphoneDeviceMatches($0, deviceName: deviceName, deviceUID: deviceUID) }
    }

    private static func defaultMicrophoneDevice(for deviceName: String) -> [String: Any] {
        [
            "deviceId": defaultDeviceId,
            "kind": "audioinput",
            "label": "系统默认麦克风",
            "groupId": defaultDeviceId,
            "description": "VibeCast will switch macOS default input to \(deviceName)"
        ]
    }

    private static func ensureDefaultMicrophoneDevice(_ defaultDevice: [String: Any], in root: inout [String: Any]) -> Bool {
        guard var devices = arrayValue(in: root, at: microphoneDevicesPath) else { return false }
        if let index = devices.firstIndex(where: { ($0["deviceId"] as? String) == defaultDeviceId }) {
            devices[index] = defaultDevice
        } else {
            devices.append(defaultDevice)
        }
        setValue(devices, in: &root, at: microphoneDevicesPath)
        return true
    }

    private static func reloadRunningTypelessIfNeeded() -> Bool? {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        guard !running.isEmpty else { return nil }
        for app in running {
            app.terminate()
        }

        let deadline = Date().addingTimeInterval(2.0)
        while Date() < deadline && running.contains(where: { !$0.isTerminated }) {
            Thread.sleep(forTimeInterval: 0.05)
        }

        return launchApp()
    }

    private static func launchApp() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-g", "-j", "-b", bundleIdentifier]
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private static func microphoneDeviceMatches(_ device: [String: Any], deviceName: String, deviceUID: String?) -> Bool {
        let label = device["label"] as? String
        let deviceId = device["deviceId"] as? String
        return label == deviceName || (deviceUID != nil && deviceId == deviceUID)
    }

    private static func audioDeviceValues(in root: [String: Any]) -> [String] {
        var values = audioDeviceStringPaths(in: root)
            .compactMap { stringValue(in: root, at: $0) }
            .filter { !$0.isEmpty }
        if let selected = dictionaryValue(in: root, at: selectedMicrophonePath) {
            values.append(contentsOf: ["label", "deviceId"].compactMap { selected[$0] as? String }.filter { !$0.isEmpty })
        }
        return values
    }

    private static func visibleAudioDeviceName(in root: [String: Any]) -> String? {
        if let selected = dictionaryValue(in: root, at: selectedMicrophonePath),
           let label = selected["label"] as? String,
           !label.isEmpty {
            return label
        }
        if let devices = arrayValue(in: root, at: microphoneDevicesPath),
           let recommended = devices.first(where: { ($0["description"] as? String) == "Recommended" }),
           let label = recommended["label"] as? String,
           !label.isEmpty {
            return label
        }
        if let devices = arrayValue(in: root, at: microphoneDevicesPath),
           let first = devices.first,
           let label = first["label"] as? String,
           !label.isEmpty {
            return label
        }
        return nil
    }

    private static func audioDeviceStringPaths(in root: [String: Any]) -> [[String]] {
        uniqueKeyPaths(audioDeviceKeyPaths + recursiveAudioDevicePaths(in: root)).filter { path in
            !path.starts(with: selectedMicrophonePath) && !path.starts(with: microphoneDevicesPath)
                && path != preferredBuiltInMicIdPath
        }
    }

    private static func recursiveAudioDevicePaths(in root: [String: Any], prefix: [String] = []) -> [[String]] {
        var result: [[String]] = []
        for (key, value) in root {
            let path = prefix + [key]
            if value is String, isLikelyAudioDevicePath(path) {
                result.append(path)
            } else if let dict = value as? [String: Any] {
                result.append(contentsOf: recursiveAudioDevicePaths(in: dict, prefix: path))
            }
        }
        return result
    }

    private static func isLikelyAudioDevicePath(_ path: [String]) -> Bool {
        guard let last = path.last?.lowercased() else { return false }
        let joined = path.joined(separator: ".").lowercased()
        if last.contains("microphone") || last == "mic" || last.contains("micdevice") {
            return true
        }
        if last.contains("inputdevice") || last.contains("recordingdevice") {
            return true
        }
        if joined.contains("audio") && last.contains("device") {
            return true
        }
        if joined.contains("microphone") && (last.contains("id") || last.contains("name") || last.contains("device")) {
            return true
        }
        return false
    }

    private static func isIdentifierPath(_ path: [String]) -> Bool {
        guard let last = path.last?.lowercased() else { return false }
        return last.hasSuffix("id") || last.contains("_id") || last.contains("deviceid")
    }

    private static func stringValue(in root: [String: Any], at path: [String]) -> String? {
        value(in: root, at: path) as? String
    }

    private static func dictionaryValue(in root: [String: Any], at path: [String]) -> [String: Any]? {
        value(in: root, at: path) as? [String: Any]
    }

    private static func arrayValue(in root: [String: Any], at path: [String]) -> [[String: Any]]? {
        value(in: root, at: path) as? [[String: Any]]
    }

    private static func value(in root: [String: Any], at path: [String]) -> Any? {
        guard !path.isEmpty else { return nil }
        var current: Any = root
        for key in path {
            if let dict = current as? [String: Any] {
                current = dict[key] as Any
            } else if let array = current as? [Any], let index = Int(key), array.indices.contains(index) {
                current = array[index]
            } else {
                return nil
            }
        }
        return current
    }

    private static func hasKey(in root: [String: Any], at path: [String]) -> Bool {
        guard let first = path.first else { return false }
        if path.count == 1 {
            return root.keys.contains(first)
        }
        guard let child = root[first] as? [String: Any] else { return false }
        return hasKey(in: child, at: Array(path.dropFirst()))
    }

    private static func setValue(_ value: Any, in root: inout [String: Any], at path: [String]) {
        guard let first = path.first else { return }
        if path.count == 1 {
            root[first] = value
            return
        }
        var child = root[first] as? [String: Any] ?? [:]
        setValue(value, in: &child, at: Array(path.dropFirst()))
        root[first] = child
    }

    private static func existingConfigURLs(_ urls: [URL]) -> [URL] {
        urls.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static func firstConfigWithAudioDevice(_ urls: [URL]) -> (url: URL, root: [String: Any], audioDevice: String, values: [String])? {
        for url in urls {
            guard let data = try? Data(contentsOf: url),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            let values = audioDeviceValues(in: root)
            if let audioDevice = values.first {
                return (url, root, audioDevice, values)
            }
            if let audioDevice = visibleAudioDeviceName(in: root),
               arrayValue(in: root, at: microphoneDevicesPath) != nil {
                return (url, root, audioDevice, values)
            }
        }
        return nil
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

    private static func uniqueKeyPaths(_ paths: [[String]]) -> [[String]] {
        var seen = Set<String>()
        var result: [[String]] = []
        for path in paths {
            let key = path.joined(separator: "\u{0}")
            if !seen.contains(key) {
                seen.insert(key)
                result.append(path)
            }
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
