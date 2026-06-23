import Foundation
import XCTest
@testable import VibeCast

final class TypelessVoiceBridgeTests: XCTestCase {
    func testStatusReadsKnownMicrophoneField() throws {
        let dir = try makeTempDir()
        let config = dir.appendingPathComponent("settings.json")
        try #"{"microphoneDeviceName":"Built-in Microphone","language":"en"}"#.data(using: .utf8)!.write(to: config)

        let status = TypelessVoiceBridge.status(virtualDeviceName: "BlackHole 2ch", configURLs: [config])

        XCTAssertTrue(status.installed)
        XCTAssertEqual(status.audioDevice, "Built-in Microphone")
        XCTAssertFalse(status.matchesVirtualMic)
    }

    func testBindWritesExistingMicrophoneFields() throws {
        let dir = try makeTempDir()
        let config = dir.appendingPathComponent("settings.json")
        try #"{"microphoneDeviceName":"Built-in Microphone","settings":{"audioDeviceName":"External Mic"},"language":"en"}"#.data(using: .utf8)!.write(to: config)

        let status = TypelessVoiceBridge.bindToVirtualMic("BlackHole 2ch", configURLs: [config])

        XCTAssertTrue(status.matchesVirtualMic)
        XCTAssertEqual(status.originalAudioDevice, "Built-in Microphone")
        let data = try Data(contentsOf: config)
        let root = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(root["microphoneDeviceName"] as? String, "BlackHole 2ch")
        let settings = root["settings"] as! [String: Any]
        XCTAssertEqual(settings["audioDeviceName"] as? String, "BlackHole 2ch")
        XCTAssertEqual(root["language"] as? String, "en")
    }

    func testBindCopiesBlackHoleDeviceObjectFromAppSettings() throws {
        let dir = try makeTempDir()
        let config = dir.appendingPathComponent("app-settings.json")
        try """
        {
          "microphoneDevices": [
            {"deviceId":"builtin-id","kind":"audioinput","label":"MacBook Air麦克风","groupId":"builtin-group","description":"Recommended"},
            {"deviceId":"blackhole-id","kind":"audioinput","label":"BlackHole 2ch","groupId":"blackhole-group","description":""}
          ],
          "selectedMicrophoneDevice": {"deviceId":"builtin-id","kind":"audioinput","label":"MacBook Air麦克风","groupId":"builtin-group","description":"Recommended"},
          "enabledMuteBackgroundAudio": true
        }
        """.data(using: .utf8)!.write(to: config)

        let status = TypelessVoiceBridge.bindToVirtualMic("BlackHole 2ch", configURLs: [config])

        XCTAssertTrue(status.matchesVirtualMic)
        XCTAssertEqual(status.originalAudioDevice, "MacBook Air麦克风")
        let data = try Data(contentsOf: config)
        let root = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let selected = root["selectedMicrophoneDevice"] as! [String: Any]
        XCTAssertEqual(selected["deviceId"] as? String, "blackhole-id")
        XCTAssertEqual(selected["label"] as? String, "BlackHole 2ch")
        let devices = root["microphoneDevices"] as! [[String: Any]]
        XCTAssertEqual(devices[0]["label"] as? String, "MacBook Air麦克风")
        XCTAssertEqual(devices[1]["deviceId"] as? String, "blackhole-id")
        XCTAssertEqual(root["enabledMuteBackgroundAudio"] as? Bool, true)
    }

    func testRestoreOnlyWhenCurrentDeviceIsManagedVirtualMic() throws {
        let dir = try makeTempDir()
        let config = dir.appendingPathComponent("settings.json")
        try #"{"microphoneDeviceName":"BlackHole 2ch","language":"en"}"#.data(using: .utf8)!.write(to: config)

        XCTAssertTrue(TypelessVoiceBridge.restoreIfManaged(originalAudioDevice: "Built-in Microphone",
                                                           virtualAudioDevice: "BlackHole 2ch",
                                                           configURLs: [config]))
        var data = try Data(contentsOf: config)
        var root = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(root["microphoneDeviceName"] as? String, "Built-in Microphone")

        root["microphoneDeviceName"] = "External Mic"
        data = try JSONSerialization.data(withJSONObject: root)
        try data.write(to: config)
        XCTAssertFalse(TypelessVoiceBridge.restoreIfManaged(originalAudioDevice: "Built-in Microphone",
                                                            virtualAudioDevice: "BlackHole 2ch",
                                                            configURLs: [config]))
        data = try Data(contentsOf: config)
        root = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(root["microphoneDeviceName"] as? String, "External Mic")
    }

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
