import XCTest
@testable import VibeCast

final class SessionManagerTests: XCTestCase {

    func testReadOnlyStatusMessagesDoNotRequireActiveController() {
        XCTAssertFalse(SessionManager.requiresActiveController("hello"))
        XCTAssertFalse(SessionManager.requiresActiveController("ping"))
        XCTAssertFalse(SessionManager.requiresActiveController("get_status"))
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
}
