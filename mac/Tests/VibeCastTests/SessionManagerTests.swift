import XCTest
@testable import VibeCast

final class SessionManagerTests: XCTestCase {

    private final class DelegateSpy: SessionManagerDelegate {
        var networkSettingsChanged: NetworkSettings?

        func sessionPairedCountChanged(_ count: Int) {}
        func sessionDidLog(_ line: String) {}

        func sessionNetworkSettingsChanged(_ settings: NetworkSettings) {
            networkSettingsChanged = settings
        }
    }

    func testReadOnlyStatusMessagesDoNotRequireActiveController() {
        XCTAssertFalse(SessionManager.requiresActiveController("hello"))
        XCTAssertFalse(SessionManager.requiresActiveController("ping"))
        XCTAssertFalse(SessionManager.requiresActiveController("get_status"))
        XCTAssertFalse(SessionManager.requiresActiveController("get_network_settings"))
        XCTAssertFalse(SessionManager.requiresActiveController("set_network_settings"))
        XCTAssertFalse(SessionManager.requiresActiveController("check_port"))
        XCTAssertFalse(SessionManager.requiresActiveController("get_config"))
        XCTAssertFalse(SessionManager.requiresActiveController("set_config"))
        XCTAssertFalse(SessionManager.requiresActiveController("test_target"))
        XCTAssertFalse(SessionManager.requiresActiveController("list_running_apps"))
        XCTAssertFalse(SessionManager.requiresActiveController("open_accessibility_settings"))
        XCTAssertFalse(SessionManager.requiresActiveController("create_target"))
        XCTAssertFalse(SessionManager.requiresActiveController("delete_target"))
        XCTAssertFalse(SessionManager.requiresActiveController("set_target_enabled"))
        XCTAssertFalse(SessionManager.requiresActiveController("unknown_future_message"))
    }

    func testInputControlMessagesRequireActiveController() {
        let activeOnly = [
            "select_target",
            "text_snapshot",
            "clear",
            "send"
        ]

        for type in activeOnly {
            XCTAssertTrue(SessionManager.requiresActiveController(type), "\(type) should require the active controller")
        }
    }

    func testNetworkSettingsChangedDispatchesThroughDelegateProtocol() {
        let spy = DelegateSpy()
        let delegate: SessionManagerDelegate = spy
        let settings = NetworkSettings(bindMode: .address, bindAddress: "192.168.1.23", port: 8790)

        delegate.sessionNetworkSettingsChanged(settings)

        XCTAssertEqual(spy.networkSettingsChanged?.bindMode, .address)
        XCTAssertEqual(spy.networkSettingsChanged?.bindAddress, "192.168.1.23")
        XCTAssertEqual(spy.networkSettingsChanged?.port, 8790)
    }
}
