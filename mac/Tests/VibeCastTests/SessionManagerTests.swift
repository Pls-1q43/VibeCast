import XCTest
@testable import VibeCast

final class SessionManagerTests: XCTestCase {

    func testReadOnlyStatusMessagesDoNotRequireActiveController() {
        XCTAssertFalse(SessionManager.requiresActiveController("hello"))
        XCTAssertFalse(SessionManager.requiresActiveController("ping"))
        XCTAssertFalse(SessionManager.requiresActiveController("get_status"))
        XCTAssertFalse(SessionManager.requiresActiveController("unknown_future_message"))
    }

    func testControlAndConfigMessagesRequireActiveController() {
        let activeOnly = [
            "select_target",
            "text_snapshot",
            "clear",
            "send",
            "get_config",
            "set_config",
            "test_target",
            "list_running_apps",
            "open_accessibility_settings",
            "create_target",
            "delete_target",
            "set_target_enabled"
        ]

        for type in activeOnly {
            XCTAssertTrue(SessionManager.requiresActiveController(type), "\(type) should require the active controller")
        }
    }
}
