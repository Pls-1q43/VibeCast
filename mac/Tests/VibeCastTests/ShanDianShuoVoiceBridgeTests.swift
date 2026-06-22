import Foundation
import XCTest
@testable import VibeCast

final class ShanDianShuoVoiceBridgeTests: XCTestCase {
    func testStatusReadsAudioDevice() throws {
        let dir = try makeTempDir()
        let config = dir.appendingPathComponent("config.json")
        try #"{"audio_device":"system","language":"zh"}"#.data(using: .utf8)!.write(to: config)

        let status = ShanDianShuoVoiceBridge.status(virtualDeviceName: "BlackHole 2ch", configURL: config)

        XCTAssertTrue(status.installed)
        XCTAssertEqual(status.audioDevice, "system")
        XCTAssertFalse(status.matchesVirtualMic)
    }

    func testBindWritesVirtualMic() throws {
        let dir = try makeTempDir()
        let config = dir.appendingPathComponent("config.json")
        try #"{"audio_device":"system","language":"zh"}"#.data(using: .utf8)!.write(to: config)

        let status = ShanDianShuoVoiceBridge.bindToVirtualMic("BlackHole 2ch", configURL: config)

        XCTAssertTrue(status.matchesVirtualMic)
        let data = try Data(contentsOf: config)
        let root = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(root["audio_device"] as? String, "BlackHole 2ch")
        XCTAssertEqual(root["language"] as? String, "zh")
    }

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
