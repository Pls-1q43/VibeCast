import XCTest
@testable import VibeCast

final class M7ConfigTests: XCTestCase {

    func testNotionAiDefaultAllowsSelectAllReplace() {
        // Notion 目标默认面向 AI 输入框，允许在已聚焦输入框内替换草稿。
        XCTAssertTrue(TargetProfile.defaultFor(.notion).allowSelectAllReplace)
    }

    func testNonNotionAllowsSelectAllReplace() {
        for id in [TargetId.codex, .workbuddy, .codebuddy] {
            XCTAssertTrue(TargetProfile.defaultFor(id).allowSelectAllReplace)
        }
    }

    func testProfileCodableIncludesNewFields() throws {
        var p = TargetProfile.defaultFor(.notion)
        p.sendButtonTitleContains = "发送"
        p.allowSelectAllReplace = false
        let data = try JSONEncoder().encode(p)
        let back = try JSONDecoder().decode(TargetProfile.self, from: data)
        XCTAssertEqual(back.sendButtonTitleContains, "发送")
        XCTAssertFalse(back.allowSelectAllReplace)
    }

    func testSendActionNoneSyncOnlySkips() {
        // 仅同步模式：不执行发送（PRD 14.2）。纯逻辑，提前返回，不触碰 AX。
        var profile = TargetProfile.defaultFor(.notion)
        profile.sendMode = .noneSyncOnly
        let binding = TargetBinding(targetId: .notion, sessionId: "s", pid: 0,
                                    bundleId: "x", element: AXUIElementCreateApplication(0), role: nil)
        if case .skipped = SendAction.perform(profile: profile, binding: binding) {} else {
            XCTFail("noneSyncOnly 应返回 skipped")
        }
    }

    func testConfigStoreFillsMissingTargetsWithDefaults() {
        // 即使配置文件缺失，也应补齐 4 个目标默认值。
        let store = TargetConfigStore(fileURL: tempConfigURL())
        for id in TargetId.presetIds {
            XCTAssertFalse(store.profile(id).displayName.isEmpty)
        }
    }

    func testConfigStoreCreatesAndDeletesCustomTargets() {
        let store = TargetConfigStore(fileURL: tempConfigURL())
        let entry = store.createCustom(displayName: "TextEdit", bundleId: "com.apple.TextEdit")
        XCTAssertEqual(entry.kind, .custom)
        XCTAssertTrue(entry.enabled)
        XCTAssertEqual(store.entry(entry.id)?.profile.bundleId, "com.apple.TextEdit")
        XCTAssertTrue(store.isUsable(entry.id))
        XCTAssertTrue(store.deleteCustom(entry.id))
        XCTAssertNil(store.entry(entry.id))
    }

    func testPresetTargetsCannotBeDeleted() {
        let store = TargetConfigStore(fileURL: tempConfigURL())
        XCTAssertFalse(store.deleteCustom(.codex))
        XCTAssertNotNil(store.entry(.codex))
    }

    private func tempConfigURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("vibecast-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("targets.json")
    }
}
