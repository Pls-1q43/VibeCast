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
    static let preferredDeviceName = "VibeCast Virtual Mic"

    static func voiceEnvironment(settings: VoiceRelaySettings = .disabled) -> VoiceEnvironmentMessage {
        let device = dedicatedVoiceDevice()
        let defaultInput = defaultInputDevice()
        let defaultMatches = device != nil && defaultInput == device?.id
        let shandianshuo = ShanDianShuoVoiceBridge.status(virtualDeviceName: device?.name)
        return VoiceEnvironmentMessage(enabled: settings.enabled,
                                       provider: settings.provider,
                                       triggerMode: settings.triggerMode,
                                       shortcut: settings.shortcut,
                                       installed: device != nil,
                                       deviceName: device?.name,
                                       dedicatedInstalled: dedicatedVoiceDevice() != nil,
                                       usingCompatibilityDevice: false,
                                       defaultInputMatches: defaultMatches,
                                       canAutoSwitch: device != nil && isDefaultInputSettable(),
                                       message: device == nil ? "未检测到 VibeCast Virtual Mic；首次开启语音投递模式时会安装专属虚拟麦克风" : nil,
                                       shandianshuoInstalled: shandianshuo.installed,
                                       shandianshuoAudioDevice: shandianshuo.audioDevice,
                                       shandianshuoMatchesVirtualMic: shandianshuo.matchesVirtualMic,
                                       shandianshuoMessage: shandianshuo.message)
    }

    static func installVirtualMic(settings: VoiceRelaySettings = .disabled) -> VoiceEnvironmentMessage {
        if let device = dedicatedVoiceDevice() {
            let shandianshuo = ShanDianShuoVoiceBridge.status(virtualDeviceName: device.name)
            return VoiceEnvironmentMessage(enabled: settings.enabled,
                                           provider: settings.provider,
                                           triggerMode: settings.triggerMode,
                                           shortcut: settings.shortcut,
                                           installed: true, deviceName: device.name,
                                           dedicatedInstalled: true,
                                           usingCompatibilityDevice: false,
                                           defaultInputMatches: defaultInputDevice() == device.id,
                                           canAutoSwitch: isDefaultInputSettable(),
                                           message: "已检测到可用虚拟麦克风",
                                           shandianshuoInstalled: shandianshuo.installed,
                                           shandianshuoAudioDevice: shandianshuo.audioDevice,
                                           shandianshuoMatchesVirtualMic: shandianshuo.matchesVirtualMic,
                                           shandianshuoMessage: shandianshuo.message)
        }
        let install = VoiceVirtualMicInstaller.installBundledDriver()
        return voiceEnvironment(settings: settings, message: install.message)
    }

    static func bindShanDianShuoToVirtualMic(settings: VoiceRelaySettings = .disabled) -> (VoiceEnvironmentMessage, VoiceRelaySettings) {
        guard let device = dedicatedVoiceDevice() else {
            let shandianshuo = ShanDianShuoVoiceBridge.status(virtualDeviceName: nil)
            let env = VoiceEnvironmentMessage(enabled: settings.enabled,
                                           provider: settings.provider,
                                           triggerMode: settings.triggerMode,
                                           shortcut: settings.shortcut,
                                           installed: false, deviceName: nil,
                                           dedicatedInstalled: false,
                                           usingCompatibilityDevice: false,
                                           defaultInputMatches: false, canAutoSwitch: false,
                                           message: "未检测到 VibeCast Virtual Mic",
                                           shandianshuoInstalled: shandianshuo.installed,
                                           shandianshuoAudioDevice: shandianshuo.audioDevice,
                                           shandianshuoMatchesVirtualMic: shandianshuo.matchesVirtualMic,
                                           shandianshuoMessage: shandianshuo.message)
            return (env, settings)
        }
        let shandianshuo = ShanDianShuoVoiceBridge.bindToVirtualMic(device.name, originalAudioDevice: settings.managedOriginalAudioDevice)
        var nextSettings = settings
        nextSettings.managedOriginalAudioDevice = shandianshuo.originalAudioDevice ?? settings.managedOriginalAudioDevice
        nextSettings.managedVirtualAudioDevice = device.name
        let env = VoiceEnvironmentMessage(enabled: nextSettings.enabled,
                                       provider: nextSettings.provider,
                                       triggerMode: nextSettings.triggerMode,
                                       shortcut: nextSettings.shortcut,
                                       installed: true, deviceName: device.name,
                                       dedicatedInstalled: dedicatedVoiceDevice() != nil,
                                       usingCompatibilityDevice: false,
                                       defaultInputMatches: defaultInputDevice() == device.id,
                                       canAutoSwitch: isDefaultInputSettable(),
                                       message: "已检测到可用虚拟麦克风",
                                       shandianshuoInstalled: shandianshuo.installed,
                                       shandianshuoAudioDevice: shandianshuo.audioDevice,
                                       shandianshuoMatchesVirtualMic: shandianshuo.matchesVirtualMic,
                                       shandianshuoMessage: shandianshuo.message)
        return (env, nextSettings)
    }

    static func preferredVoiceDevice() -> VoiceAudioDevice? {
        dedicatedVoiceDevice()
    }

    static func dedicatedVoiceDevice() -> VoiceAudioDevice? {
        let devices = allDevices()
        return devices.first { $0.name == preferredDeviceName && $0.hasInput && $0.hasOutput }
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
                                       usingCompatibilityDevice: false,
                                       defaultInputMatches: base.defaultInputMatches,
                                       canAutoSwitch: base.canAutoSwitch,
                                       message: message ?? base.message,
                                       shandianshuoInstalled: base.shandianshuoInstalled,
                                       shandianshuoAudioDevice: base.shandianshuoAudioDevice,
                                       shandianshuoMatchesVirtualMic: base.shandianshuoMatchesVirtualMic,
                                       shandianshuoMessage: base.shandianshuoMessage)
    }
}

enum VoiceVirtualMicInstaller {
    struct InstallResult {
        let installed: Bool
        let message: String
    }

    private static let bundleName = "VibeCastVirtualMic"
    private static let destinationPath = "/Library/Audio/Plug-Ins/HAL/VibeCastVirtualMic.driver"

    static func installBundledDriver() -> InstallResult {
        if VoiceAudioDeviceManager.dedicatedVoiceDevice() != nil {
            return InstallResult(installed: true, message: "已检测到 VibeCast Virtual Mic")
        }
        guard let sourceURL = bundledDriverURL() else {
            return InstallResult(installed: false, message: "未找到内包的 VibeCastVirtualMic.driver，请重新安装 VibeCast")
        }

        let command = [
            "mkdir -p /Library/Audio/Plug-Ins/HAL",
            "rm -rf \(shellQuote(destinationPath))",
            "ditto --norsrc --noqtn --noextattr --noacl \(shellQuote(sourceURL.path)) \(shellQuote(destinationPath))",
            "xattr -cr \(shellQuote(destinationPath)) 2>/dev/null || true",
            "killall coreaudiod 2>/dev/null || true"
        ].joined(separator: " && ")

        let script = "do shell script \(appleScriptString(command)) with administrator privileges"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let pipe = Pipe()
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return InstallResult(installed: false, message: "无法启动虚拟麦克风安装器：\(error.localizedDescription)")
        }

        guard process.terminationStatus == 0 else {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let detail = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return InstallResult(installed: false, message: detail?.isEmpty == false ? "虚拟麦克风安装失败：\(detail!)" : "虚拟麦克风安装已取消或失败")
        }

        for _ in 0..<40 {
            if VoiceAudioDeviceManager.dedicatedVoiceDevice() != nil {
                return InstallResult(installed: true, message: "已安装 VibeCast Virtual Mic")
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return InstallResult(installed: false, message: "已复制虚拟麦克风驱动，但 CoreAudio 尚未加载到 VibeCast Virtual Mic；请重启 VibeCast 或 macOS 后再试")
    }

    private static func bundledDriverURL() -> URL? {
        let candidates = [
            Bundle.main.url(forResource: bundleName, withExtension: "driver"),
            Bundle.module.url(forResource: bundleName, withExtension: "driver")
        ].compactMap { $0 }
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
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
