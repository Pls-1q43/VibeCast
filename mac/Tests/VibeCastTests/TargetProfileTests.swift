import XCTest
@testable import VibeCast

final class TargetProfileTests: XCTestCase {

    func testDefaultProfilesForAllTargets() {
        for id in TargetId.presetIds {
            let p = TargetProfile.defaultFor(id)
            XCTAssertFalse(p.displayName.isEmpty)
            XCTAssertTrue(p.bundleId.isEmpty, "默认不得写死 Bundle ID")
            XCTAssertEqual(p.maxTextLength, 10000)
        }
    }

    func testNotionDefaultsUseClipboardForAiInput() {
        // Notion AI 输入框不可靠支持 AXValue，默认使用剪贴板替换并允许 Enter 发送。
        let p = TargetProfile.defaultFor(.notion)
        XCTAssertEqual(p.writeMode, .clipboardReplace)
        XCTAssertTrue(p.allowSelectAllReplace)
        XCTAssertEqual(p.sendMode, .key)
        XCTAssertEqual(p.sendShortcut, .enter)
        XCTAssertTrue(p.clearAfterSend)
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

    func testNormalizeClampsRiskyValuesAndMigratesLegacyClipboardPaste() {
        var p = TargetProfile.defaultFor(.codex)
        p.displayName = "  "
        p.focusWaitMs = 0
        p.maxTextLength = 100_000
        p.writeMode = .clipboardPaste
        let normalized = p.normalized()
        XCTAssertEqual(normalized.displayName, "Target")
        XCTAssertEqual(normalized.focusWaitMs, 50)
        XCTAssertEqual(normalized.maxTextLength, 50_000)
        XCTAssertEqual(normalized.writeMode, .clipboardReplace)
    }

    func testCustomTargetIdDefaultsLikeGenericTarget() throws {
        let id = try XCTUnwrap(TargetId(rawValue: "custom_textedit"))
        let p = TargetProfile.defaultFor(id)
        XCTAssertEqual(p.displayName, "Custom_Textedit")
        XCTAssertEqual(p.focusMode, .shortcut)
        XCTAssertEqual(p.writeMode, .auto)
    }
}
