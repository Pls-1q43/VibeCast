import XCTest
@testable import VibeCast

final class NetworkSettingsStoreTests: XCTestCase {

    func testAllInterfacesNormalizationClearsAddress() {
        let settings = NetworkSettings(bindMode: .all, bindAddress: "192.168.1.2", port: 8788)
        let normalized = NetworkSettingsStore.normalized(settings)

        XCTAssertEqual(normalized.bindMode, .all)
        XCTAssertNil(normalized.bindAddress)
        XCTAssertEqual(normalized.port, 8788)
    }

    func testZeroPortNormalizesToDefaultForSavedSettings() {
        let settings = NetworkSettings(bindMode: .all, bindAddress: nil, port: 0)
        let normalized = NetworkSettingsStore.normalized(settings)

        XCTAssertEqual(normalized.port, NetworkSettings.defaultPort)
    }

    func testPortCheckRejectsZeroPort() {
        let settings = NetworkSettings(bindMode: .all, bindAddress: nil, port: 0)
        let result = PortAvailability.check(settings: settings)

        XCTAssertEqual(result.status, .invalid)
    }

    func testStorePersistsUpdatedSettings() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vibecast-network-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("network.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let store = NetworkSettingsStore(fileURL: url)
        store.update(NetworkSettings(bindMode: .all, bindAddress: nil, port: 8790))
        let reloaded = NetworkSettingsStore(fileURL: url)

        XCTAssertEqual(reloaded.settings.bindMode, .all)
        XCTAssertEqual(reloaded.settings.port, 8790)
    }
}
