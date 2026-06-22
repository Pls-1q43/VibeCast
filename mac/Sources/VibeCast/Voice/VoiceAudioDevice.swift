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
    static let compatibleDeviceNames = ["VibeCast Virtual Mic", "BlackHole 2ch"]

    static func voiceEnvironment() -> VoiceEnvironmentMessage {
        let device = preferredVoiceDevice()
        let defaultInput = defaultInputDevice()
        let defaultMatches = device != nil && defaultInput == device?.id
        return VoiceEnvironmentMessage(installed: device != nil,
                                       deviceName: device?.name,
                                       defaultInputMatches: defaultMatches,
                                       canAutoSwitch: device != nil && isDefaultInputSettable(),
                                       message: device == nil ? "未检测到 VibeCast Virtual Mic 或 BlackHole 2ch" : nil)
    }

    static func installVirtualMic() -> VoiceEnvironmentMessage {
        if let device = preferredVoiceDevice() {
            return VoiceEnvironmentMessage(installed: true, deviceName: device.name,
                                           defaultInputMatches: defaultInputDevice() == device.id,
                                           canAutoSwitch: isDefaultInputSettable(),
                                           message: "已检测到可用虚拟麦克风")
        }
        return VoiceEnvironmentMessage(installed: false, deviceName: nil,
                                       defaultInputMatches: false, canAutoSwitch: false,
                                       message: "当前实验版需要 VibeCast Virtual Mic HAL 插件或 BlackHole 2ch；未找到可安装的内置驱动包")
    }

    static func preferredVoiceDevice() -> VoiceAudioDevice? {
        let devices = allDevices()
        for name in compatibleDeviceNames {
            if let device = devices.first(where: { $0.name == name && $0.hasInput && $0.hasOutput }) {
                return device
            }
        }
        return devices.first { device in
            device.isVirtual && device.hasInput && device.hasOutput && device.name.localizedCaseInsensitiveContains("blackhole")
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
