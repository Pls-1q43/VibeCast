import Foundation
import XCTest
@testable import VibeCast

final class ShanDianShuoVoiceBridgeTests: XCTestCase {
    func testStatusReadsAudioDevice() throws {
        let dir = try makeTempDir()
        let config = dir.appendingPathComponent("config.json")
        try #"{"audio_device":"system","language":"zh"}"#.data(using: .utf8)!.write(to: config)

        let status = ShanDianShuoVoiceBridge.status(virtualDeviceName: "VibeCast Virtual Mic", configURL: config)

        XCTAssertTrue(status.installed)
        XCTAssertEqual(status.audioDevice, "system")
        XCTAssertFalse(status.matchesVirtualMic)
    }

    func testBindWritesVirtualMic() throws {
        let dir = try makeTempDir()
        let config = dir.appendingPathComponent("config.json")
        try #"{"audio_device":"system","language":"zh"}"#.data(using: .utf8)!.write(to: config)

        let status = ShanDianShuoVoiceBridge.bindToVirtualMic("VibeCast Virtual Mic", configURL: config)

        XCTAssertTrue(status.matchesVirtualMic)
        XCTAssertEqual(status.originalAudioDevice, "system")
        let data = try Data(contentsOf: config)
        let root = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(root["audio_device"] as? String, "VibeCast Virtual Mic")
        XCTAssertEqual(root["language"] as? String, "zh")
    }

    func testRestoreOnlyWhenCurrentDeviceIsManagedVirtualMic() throws {
        let dir = try makeTempDir()
        let config = dir.appendingPathComponent("config.json")
        try #"{"audio_device":"VibeCast Virtual Mic","language":"zh"}"#.data(using: .utf8)!.write(to: config)

        XCTAssertTrue(ShanDianShuoVoiceBridge.restoreIfManaged(originalAudioDevice: "system",
                                                               virtualAudioDevice: "VibeCast Virtual Mic",
                                                               configURL: config))
        var data = try Data(contentsOf: config)
        var root = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(root["audio_device"] as? String, "system")

        root["audio_device"] = "External Mic"
        data = try JSONSerialization.data(withJSONObject: root)
        try data.write(to: config)
        XCTAssertFalse(ShanDianShuoVoiceBridge.restoreIfManaged(originalAudioDevice: "system",
                                                                virtualAudioDevice: "VibeCast Virtual Mic",
                                                                configURL: config))
        data = try Data(contentsOf: config)
        root = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(root["audio_device"] as? String, "External Mic")
    }

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
