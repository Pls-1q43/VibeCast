import AudioToolbox
import CoreAudio
import Foundation

struct VoiceAudioDevice: Equatable {
    let id: AudioDeviceID
    let name: String
    let uid: String
    let hasInput: Bool
    let hasOutput: Bool
    let isVirtual: Bool
}

enum VoiceAudioDeviceManager {
    static let preferredDeviceName = "BlackHole 2ch"

    static func voiceEnvironment(settings: VoiceRelaySettings = .disabled) -> VoiceEnvironmentMessage {
        let device = dedicatedVoiceDevice()
        let defaultInput = defaultInputDevice()
        let defaultMatches = device != nil && defaultInput == device?.id
        let shandianshuo = ShanDianShuoVoiceBridge.status(virtualDeviceName: device?.name)
        let typeless = TypelessVoiceBridge.status(virtualDeviceName: device?.name, virtualDeviceUID: device?.uid)
        let doubao = settings.provider == .doubaoInput
            ? DoubaoVoiceBridge.microphoneStatus(targetDeviceUID: device?.uid ?? "BlackHole2ch_UID", timeout: 0.8)
            : nil
        return VoiceEnvironmentMessage(enabled: settings.enabled,
                                       provider: settings.provider,
                                       triggerMode: settings.triggerMode,
                                       shortcut: settings.shortcut,
                                       installed: device != nil,
                                       deviceName: device?.name,
                                       dedicatedInstalled: false,
                                       usingCompatibilityDevice: device != nil,
                                       defaultInputMatches: defaultMatches,
                                       canAutoSwitch: device != nil && isDefaultInputSettable(),
                                       message: device == nil ? "未检测到 BlackHole 2ch；首次开启语音投递模式时会下载并安装官方 BlackHole 2ch 虚拟音频驱动" : nil,
                                       shandianshuoInstalled: shandianshuo.installed,
                                       shandianshuoAudioDevice: shandianshuo.audioDevice,
                                       shandianshuoMatchesVirtualMic: shandianshuo.matchesVirtualMic,
                                       shandianshuoMessage: shandianshuo.message,
                                       typelessInstalled: typeless.installed,
                                       typelessAudioDevice: typeless.audioDevice,
                                       typelessMatchesVirtualMic: typeless.matchesVirtualMic,
                                       typelessMessage: typeless.message,
                                       doubaoInstalled: doubao?.installed,
                                       doubaoAudioDevice: doubao?.selectedName ?? doubao?.selectedId,
                                       doubaoMatchesVirtualMic: doubao?.matchesTarget,
                                       doubaoMessage: doubao?.message)
    }

    static func installVirtualMic(settings: VoiceRelaySettings = .disabled) -> VoiceEnvironmentMessage {
        if let device = dedicatedVoiceDevice() {
            let shandianshuo = ShanDianShuoVoiceBridge.status(virtualDeviceName: device.name)
            let typeless = TypelessVoiceBridge.status(virtualDeviceName: device.name, virtualDeviceUID: device.uid)
            return VoiceEnvironmentMessage(enabled: settings.enabled,
                                           provider: settings.provider,
                                           triggerMode: settings.triggerMode,
                                           shortcut: settings.shortcut,
                                           installed: true, deviceName: device.name,
                                           dedicatedInstalled: false,
                                           usingCompatibilityDevice: true,
                                           defaultInputMatches: defaultInputDevice() == device.id,
                                           canAutoSwitch: isDefaultInputSettable(),
                                           message: "已检测到 BlackHole 2ch",
                                           shandianshuoInstalled: shandianshuo.installed,
                                           shandianshuoAudioDevice: shandianshuo.audioDevice,
                                           shandianshuoMatchesVirtualMic: shandianshuo.matchesVirtualMic,
                                           shandianshuoMessage: shandianshuo.message,
                                           typelessInstalled: typeless.installed,
                                           typelessAudioDevice: typeless.audioDevice,
                                           typelessMatchesVirtualMic: typeless.matchesVirtualMic,
                                           typelessMessage: typeless.message)
        }
        let install = BlackHoleInstaller.install()
        return voiceEnvironment(settings: settings, message: install.message)
    }

    static func bindShanDianShuoToVirtualMic(settings: VoiceRelaySettings = .disabled) -> (VoiceEnvironmentMessage, VoiceRelaySettings) {
        guard let device = dedicatedVoiceDevice() else {
            let shandianshuo = ShanDianShuoVoiceBridge.status(virtualDeviceName: nil)
            let typeless = TypelessVoiceBridge.status(virtualDeviceName: nil)
            let env = VoiceEnvironmentMessage(enabled: settings.enabled,
                                           provider: settings.provider,
                                           triggerMode: settings.triggerMode,
                                           shortcut: settings.shortcut,
                                           installed: false, deviceName: nil,
                                           dedicatedInstalled: false,
                                           usingCompatibilityDevice: false,
                                           defaultInputMatches: false, canAutoSwitch: false,
                                           message: "未检测到 BlackHole 2ch",
                                           shandianshuoInstalled: shandianshuo.installed,
                                           shandianshuoAudioDevice: shandianshuo.audioDevice,
                                           shandianshuoMatchesVirtualMic: shandianshuo.matchesVirtualMic,
                                           shandianshuoMessage: shandianshuo.message,
                                           typelessInstalled: typeless.installed,
                                           typelessAudioDevice: typeless.audioDevice,
                                           typelessMatchesVirtualMic: typeless.matchesVirtualMic,
                                           typelessMessage: typeless.message)
            return (env, settings)
        }
        let shandianshuo = ShanDianShuoVoiceBridge.bindToVirtualMic(device.name, originalAudioDevice: settings.managedOriginalAudioDevice)
        let typeless = TypelessVoiceBridge.status(virtualDeviceName: device.name, virtualDeviceUID: device.uid)
        var nextSettings = settings
        nextSettings.managedOriginalAudioDevice = shandianshuo.originalAudioDevice ?? settings.managedOriginalAudioDevice
        nextSettings.managedVirtualAudioDevice = device.name
        let env = VoiceEnvironmentMessage(enabled: nextSettings.enabled,
                                       provider: nextSettings.provider,
                                       triggerMode: nextSettings.triggerMode,
                                       shortcut: nextSettings.shortcut,
                                       installed: true, deviceName: device.name,
                                       dedicatedInstalled: false,
                                       usingCompatibilityDevice: true,
                                       defaultInputMatches: defaultInputDevice() == device.id,
                                       canAutoSwitch: isDefaultInputSettable(),
                                       message: "已检测到 BlackHole 2ch",
                                       shandianshuoInstalled: shandianshuo.installed,
                                       shandianshuoAudioDevice: shandianshuo.audioDevice,
                                       shandianshuoMatchesVirtualMic: shandianshuo.matchesVirtualMic,
                                       shandianshuoMessage: shandianshuo.message,
                                       typelessInstalled: typeless.installed,
                                       typelessAudioDevice: typeless.audioDevice,
                                       typelessMatchesVirtualMic: typeless.matchesVirtualMic,
                                       typelessMessage: typeless.message)
        return (env, nextSettings)
    }

    static func bindTypelessToVirtualMic(settings: VoiceRelaySettings = .disabled,
                                         reloadRunningApp: Bool = false) -> (VoiceEnvironmentMessage, VoiceRelaySettings) {
        guard let device = dedicatedVoiceDevice() else {
            let shandianshuo = ShanDianShuoVoiceBridge.status(virtualDeviceName: nil)
            let typeless = TypelessVoiceBridge.status(virtualDeviceName: nil)
            let env = VoiceEnvironmentMessage(enabled: settings.enabled,
                                              provider: settings.provider,
                                              triggerMode: settings.triggerMode,
                                              shortcut: settings.shortcut,
                                              installed: false, deviceName: nil,
                                              dedicatedInstalled: false,
                                              usingCompatibilityDevice: false,
                                              defaultInputMatches: false, canAutoSwitch: false,
                                              message: "未检测到 BlackHole 2ch",
                                              shandianshuoInstalled: shandianshuo.installed,
                                              shandianshuoAudioDevice: shandianshuo.audioDevice,
                                              shandianshuoMatchesVirtualMic: shandianshuo.matchesVirtualMic,
                                              shandianshuoMessage: shandianshuo.message,
                                              typelessInstalled: typeless.installed,
                                              typelessAudioDevice: typeless.audioDevice,
                                              typelessMatchesVirtualMic: typeless.matchesVirtualMic,
                                              typelessMessage: typeless.message)
            return (env, settings)
        }
        let shandianshuo = ShanDianShuoVoiceBridge.status(virtualDeviceName: device.name)
        let typeless = TypelessVoiceBridge.bindToVirtualMic(device.name, deviceUID: device.uid,
                                                            originalAudioDevice: settings.managedOriginalAudioDevice,
                                                            reloadRunningApp: reloadRunningApp)
        var nextSettings = settings
        nextSettings.managedOriginalAudioDevice = typeless.originalAudioDevice ?? settings.managedOriginalAudioDevice
        nextSettings.managedVirtualAudioDevice = device.name
        let env = VoiceEnvironmentMessage(enabled: nextSettings.enabled,
                                          provider: nextSettings.provider,
                                          triggerMode: nextSettings.triggerMode,
                                          shortcut: nextSettings.shortcut,
                                          installed: true, deviceName: device.name,
                                          dedicatedInstalled: false,
                                          usingCompatibilityDevice: true,
                                          defaultInputMatches: defaultInputDevice() == device.id,
                                          canAutoSwitch: isDefaultInputSettable(),
                                          message: "已检测到 BlackHole 2ch",
                                          shandianshuoInstalled: shandianshuo.installed,
                                          shandianshuoAudioDevice: shandianshuo.audioDevice,
                                          shandianshuoMatchesVirtualMic: shandianshuo.matchesVirtualMic,
                                          shandianshuoMessage: shandianshuo.message,
                                          typelessInstalled: typeless.installed,
                                          typelessAudioDevice: typeless.audioDevice,
                                          typelessMatchesVirtualMic: typeless.matchesVirtualMic,
                                          typelessMessage: typeless.message)
        return (env, nextSettings)
    }

    static func preferredVoiceDevice() -> VoiceAudioDevice? {
        dedicatedVoiceDevice()
    }

    static func dedicatedVoiceDevice() -> VoiceAudioDevice? {
        let devices = allDevices()
        return devices.first { device in
            (device.name == preferredDeviceName || device.uid == "BlackHole2ch_UID" || device.uid == "BlackHole2ch")
                && device.hasInput && device.hasOutput
        }
    }

    static func allDevices() -> [VoiceAudioDevice] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else {
            return []
        }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else {
            return []
        }
        return ids.compactMap(deviceInfo)
    }

    static func defaultInputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != 0 else {
            return nil
        }
        return device
    }

    static func device(_ id: AudioDeviceID) -> VoiceAudioDevice? {
        deviceInfo(id)
    }

    static func deviceLabel(_ id: AudioDeviceID?) -> String {
        guard let id else { return "<none>" }
        if let info = deviceInfo(id) {
            return "\(info.name) uid=\(info.uid)"
        }
        return "#\(id)"
    }

    @discardableResult
    static func setDefaultInputDevice(_ device: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value = device
        return AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
                                          UInt32(MemoryLayout<AudioDeviceID>.size), &value) == noErr
    }

    private static func isDefaultInputSettable() -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var settable = DarwinBoolean(false)
        return AudioObjectIsPropertySettable(AudioObjectID(kAudioObjectSystemObject), &address, &settable) == noErr
            && settable.boolValue
    }

    private static func deviceInfo(_ id: AudioDeviceID) -> VoiceAudioDevice? {
        guard let name = stringProperty(id, kAudioObjectPropertyName),
              let uid = stringProperty(id, kAudioDevicePropertyDeviceUID) else {
            return nil
        }
        let input = hasStreams(id, scope: kAudioDevicePropertyScopeInput)
        let output = hasStreams(id, scope: kAudioDevicePropertyScopeOutput)
        return VoiceAudioDevice(id: id, name: name, uid: uid, hasInput: input, hasOutput: output,
                                isVirtual: transportType(id) == kAudioDeviceTransportTypeVirtual)
    }

    private static func stringProperty(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let value else { return nil }
        return value.takeUnretainedValue() as String
    }

    private static func transportType(_ id: AudioObjectID) -> UInt32 {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return 0 }
        return value
    }

    private static func hasStreams(_ id: AudioObjectID, scope: AudioObjectPropertyScope) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                                 mScope: scope,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr && size > 0
    }

    private static func voiceEnvironment(settings: VoiceRelaySettings, message: String?) -> VoiceEnvironmentMessage {
        let base = voiceEnvironment(settings: settings)
        return VoiceEnvironmentMessage(enabled: base.enabled,
                                       provider: base.provider,
                                       triggerMode: base.triggerMode,
                                       shortcut: base.shortcut,
                                       installed: base.installed,
                                       deviceName: base.deviceName,
                                       dedicatedInstalled: base.dedicatedInstalled,
                                       usingCompatibilityDevice: base.usingCompatibilityDevice,
                                       defaultInputMatches: base.defaultInputMatches,
                                       canAutoSwitch: base.canAutoSwitch,
                                       message: message ?? base.message,
                                       shandianshuoInstalled: base.shandianshuoInstalled,
                                       shandianshuoAudioDevice: base.shandianshuoAudioDevice,
                                       shandianshuoMatchesVirtualMic: base.shandianshuoMatchesVirtualMic,
                                       shandianshuoMessage: base.shandianshuoMessage,
                                       typelessInstalled: base.typelessInstalled,
                                       typelessAudioDevice: base.typelessAudioDevice,
                                       typelessMatchesVirtualMic: base.typelessMatchesVirtualMic,
                                       typelessMessage: base.typelessMessage,
                                       doubaoInstalled: base.doubaoInstalled,
                                       doubaoAudioDevice: base.doubaoAudioDevice,
                                       doubaoMatchesVirtualMic: base.doubaoMatchesVirtualMic,
                                       doubaoMessage: base.doubaoMessage)
    }
}

enum BlackHoleInstaller {
    struct InstallResult {
        let installed: Bool
        let message: String
    }

    private static let downloadURL = URL(string: "https://existential.audio/downloads/BlackHole2ch-0.7.0.pkg")!
    private static let expectedOrigin = "Developer ID Installer: Existential Audio Inc. (Q5C99V536K)"

    static func install() -> InstallResult {
        if VoiceAudioDeviceManager.dedicatedVoiceDevice() != nil {
            return InstallResult(installed: true, message: "已检测到 BlackHole 2ch")
        }
        let packageURL: URL
        do {
            packageURL = try downloadPackage()
        } catch {
            return InstallResult(installed: false, message: "无法下载 BlackHole 2ch 安装包：\(error.localizedDescription)。可稍后重试，或先通过 Homebrew 安装 blackhole-2ch。")
        }

        let assessment = run("/usr/sbin/spctl", arguments: ["--assess", "--type", "install", "-vv", packageURL.path])
        guard assessment.contains("accepted"), assessment.contains(expectedOrigin) else {
            return InstallResult(installed: false, message: "BlackHole 2ch 安装包签名校验失败，已取消安装。校验输出：\(assessment)")
        }

        let command = [
            "set -e",
            "/usr/sbin/installer -pkg \(shellQuote(packageURL.path)) -target /",
            "/bin/rm -rf /Library/Audio/Plug-Ins/HAL/VibeCastVirtualMic.driver 2>/dev/null || true",
            "/usr/bin/killall coreaudiod 2>/dev/null || true"
        ].joined(separator: "; ")

        let script = "do shell script \(appleScriptString(command + " 2>&1")) with administrator privileges"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return InstallResult(installed: false, message: "无法启动虚拟麦克风安装器：\(error.localizedDescription)")
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0 else {
            return InstallResult(installed: false, message: output?.isEmpty == false ? "BlackHole 2ch 安装失败：\(output!)" : "BlackHole 2ch 安装已取消或失败")
        }

        for _ in 0..<40 {
            if VoiceAudioDeviceManager.dedicatedVoiceDevice() != nil {
                return InstallResult(installed: true, message: "已安装 BlackHole 2ch")
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        let suffix = output?.isEmpty == false ? " 安装输出：\(output!)" : ""
        return InstallResult(installed: false, message: "BlackHole 2ch 已安装，但 CoreAudio 尚未枚举到设备。请重启 Mac 后重新检测。\(suffix)")
    }

    private static func downloadPackage() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("VibeCast-BlackHole-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let packageURL = directory.appendingPathComponent("BlackHole2ch.pkg")
        let result = run("/usr/bin/curl", arguments: ["-L", "--fail", "--silent", "--show-error", "-o", packageURL.path, downloadURL.absoluteString])
        guard FileManager.default.fileExists(atPath: packageURL.path) else {
            throw NSError(domain: "VibeCast.BlackHoleInstaller", code: 1, userInfo: [NSLocalizedDescriptionKey: result.isEmpty ? "下载失败" : result])
        }
        return packageURL
    }

    private static func run(_ executable: String, arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ""
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func appleScriptString(_ value: String) -> String {
        "\"" + value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}

final class VoiceAudioRelay {
    private var queue: AudioQueueRef?
    private let lock = NSLock()

    func start(deviceUID: String, sampleRate: Double, channels: UInt32) -> Bool {
        stop()
        var format = AudioStreamBasicDescription(mSampleRate: sampleRate,
                                                 mFormatID: kAudioFormatLinearPCM,
                                                 mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
                                                 mBytesPerPacket: channels * 2,
                                                 mFramesPerPacket: 1,
                                                 mBytesPerFrame: channels * 2,
                                                 mChannelsPerFrame: channels,
                                                 mBitsPerChannel: 16,
                                                 mReserved: 0)
        var newQueue: AudioQueueRef?
        let status = AudioQueueNewOutput(&format, { _, _, _ in }, nil, nil, nil, 0, &newQueue)
        guard status == noErr, let newQueue else { return false }

        let uid = deviceUID as CFString
        var unmanagedUID = Unmanaged.passUnretained(uid)
        let uidStatus = withUnsafePointer(to: &unmanagedUID) {
            AudioQueueSetProperty(newQueue, kAudioQueueProperty_CurrentDevice, $0,
                                  UInt32(MemoryLayout<Unmanaged<CFString>>.size))
        }
        guard uidStatus == noErr else {
            AudioQueueDispose(newQueue, true)
            return false
        }
        guard AudioQueueStart(newQueue, nil) == noErr else {
            AudioQueueDispose(newQueue, true)
            return false
        }
        lock.lock()
        queue = newQueue
        lock.unlock()
        return true
    }

    func enqueue(_ data: Data) {
        lock.lock()
        guard let queue else {
            lock.unlock()
            return
        }
        lock.unlock()
        var buffer: AudioQueueBufferRef?
        guard AudioQueueAllocateBuffer(queue, UInt32(data.count), &buffer) == noErr, let buffer else { return }
        data.withUnsafeBytes { raw in
            if let source = raw.baseAddress {
                memcpy(buffer.pointee.mAudioData, source, data.count)
            }
        }
        buffer.pointee.mAudioDataByteSize = UInt32(data.count)
        if AudioQueueEnqueueBuffer(queue, buffer, 0, nil) != noErr {
            AudioQueueFreeBuffer(queue, buffer)
        }
    }

    func stop() {
        lock.lock()
        let old = queue
        queue = nil
        lock.unlock()
        if let old {
            AudioQueueStop(old, true)
            AudioQueueDispose(old, true)
        }
    }

    deinit {
        stop()
    }
}
