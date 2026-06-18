import XCTest
@testable import VibeCast

final class TargetProfileTests: XCTestCase {

    func testDefaultProfilesForAllTargets() {
        for id in TargetId.allCases {
            let p = TargetProfile.defaultFor(id)
            XCTAssertFalse(p.displayName.isEmpty)
            XCTAssertTrue(p.bundleId.isEmpty, "默认不得写死 Bundle ID")
            XCTAssertEqual(p.maxTextLength, 10000)
        }
    }

    func testNotionDefaultsSyncOnlyNoSend() {
        // Notion 默认当前文本块模式：不自动发送、不清空（PRD 14.2）。
        let p = TargetProfile.defaultFor(.notion)
        XCTAssertEqual(p.sendMode, .noneSyncOnly)
        XCTAssertFalse(p.clearAfterSend)
        XCTAssertEqual(p.focusMode, .preserveLastFocus)
    }

    func testNonNotionDefaultsSendEnter() {
        let p = TargetProfile.defaultFor(.codex)
        XCTAssertEqual(p.sendMode, .key)
        XCTAssertEqual(p.sendShortcut, .enter)
        XCTAssertTrue(p.clearAfterSend)
        XCTAssertEqual(p.focusMode, .shortcut)
    }

    func testProfileCodableRoundTrip() throws {
        var p = TargetProfile.defaultFor(.codex)
        p.bundleId = "com.example.codex"
        p.focusShortcut = KeyShortcut(modifiers: ["command"], key: "l")
        let data = try JSONEncoder().encode(p)
        let back = try JSONDecoder().decode(TargetProfile.self, from: data)
        XCTAssertEqual(back.bundleId, "com.example.codex")
        XCTAssertEqual(back.focusShortcut, KeyShortcut(modifiers: ["command"], key: "l"))
    }

    func testKeyShortcutEnterConstant() {
        XCTAssertEqual(KeyShortcut.enter.key, "enter")
        XCTAssertTrue(KeyShortcut.enter.modifiers.isEmpty)
    }
}
