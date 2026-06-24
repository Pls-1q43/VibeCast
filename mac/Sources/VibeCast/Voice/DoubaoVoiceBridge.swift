import CoreAudio
import Foundation

struct DoubaoMicrophoneStatus {
    var installed: Bool
    var selectedId: String?
    var selectedName: String?
    var targetId: String?
    var targetName: String?
    var targetAvailable: Bool
    var matchesTarget: Bool
    var deviceCount: Int
    var message: String?
}

enum DoubaoVoiceBridge {
    private static let requestMicrophoneListNotification = Notification.Name("DoubaoImeSettings.requestMicrophoneList")
    private static let updateMicrophoneListNotification = Notification.Name("DoubaoImeSettings.updateMicrophoneList")

    static func microphoneStatus(targetDeviceUID: String, timeout: TimeInterval = 1.0) -> DoubaoMicrophoneStatus {
        let center = DistributedNotificationCenter.default()
        let semaphore = DispatchSemaphore(value: 0)
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1

        var devices: [[String: Any]] = []
        let token = center.addObserver(forName: updateMicrophoneListNotification, object: nil, queue: queue) { note in
            devices = parseDevices(note.userInfo?["devices"])
            semaphore.signal()
        }
        defer {
            center.removeObserver(token)
            queue.cancelAllOperations()
        }

        center.postNotificationName(requestMicrophoneListNotification, object: nil, userInfo: nil, deliverImmediately: true)
        _ = semaphore.wait(timeout: .now() + timeout)

        guard !devices.isEmpty else {
            return DoubaoMicrophoneStatus(installed: isInstalled(),
                                          selectedId: nil,
                                          selectedName: nil,
                                          targetId: targetDeviceUID,
                                          targetName: nil,
                                          targetAvailable: false,
                                          matchesTarget: false,
                                          deviceCount: 0,
                                          message: "无法读取豆包输入法麦克风列表")
        }

        let selected = devices.first { boolValue($0["isDefault"]) }
        let target = devices.first { stringValue($0["id"]) == targetDeviceUID }
        let selectedId = stringValue(selected?["id"])
        let targetId = stringValue(target?["id"])
        let matches = selectedId != nil && selectedId == targetId
        let message: String?
        if target == nil {
            message = "豆包输入法麦克风列表中未发现 BlackHole 2ch"
        } else if !matches {
            let current = stringValue(selected?["name"]) ?? selectedId ?? "<none>"
            message = "豆包输入法当前麦克风是 \(current)，不是 BlackHole 2ch"
        } else {
            message = nil
        }

        return DoubaoMicrophoneStatus(installed: true,
                                      selectedId: selectedId,
                                      selectedName: stringValue(selected?["name"]),
                                      targetId: targetId,
                                      targetName: stringValue(target?["name"]),
                                      targetAvailable: target != nil,
                                      matchesTarget: matches,
                                      deviceCount: devices.count,
                                      message: message)
    }

    private static func isInstalled() -> Bool {
        FileManager.default.fileExists(atPath: "/Library/Input Methods/DoubaoIme.app")
    }

    private static func parseDevices(_ value: Any?) -> [[String: Any]] {
        guard let array = value as? [Any] else { return [] }
        return array.compactMap { item in
            if let dict = item as? [String: Any] { return dict }
            if let dict = item as? NSDictionary { return dict as? [String: Any] }
            return nil
        }
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let value = value as? NSString { return value as String }
        return nil
    }

    private static func boolValue(_ value: Any?) -> Bool {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        return false
    }
}
