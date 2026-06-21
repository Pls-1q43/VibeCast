import XCTest
@testable import VibeCast

final class M7ConfigTests: XCTestCase {

    func testNotionAiDefaultAllowsSelectAllReplace() {
        // Notion 目标默认面向 AI 输入框，允许在已聚焦输入框内替换草稿。
        XCTAssertTrue(TargetProfile.defaultFor(.notion).allowSelectAllReplace)
    }

    func testNonNotionAllowsSelectAllReplace() {
        for id in [TargetId.codex, .workbuddy, .codebuddycn, .codebuddy] {
            XCTAssertTrue(TargetProfile.defaultFor(id).allowSelectAllReplace)
        }
    }

    func testObsidianDefaultDisablesSelectAllReplace() {
        XCTAssertFalse(TargetProfile.defaultFor(.obsidian).allowSelectAllReplace)
        XCTAssertEqual(TargetProfile.defaultFor(.obsidian).syncMode, .editor)
    }

    func testProfileCodableIncludesNewFields() throws {
        var p = TargetProfile.defaultFor(.notion)
        p.sendButtonTitleContains = "发送"
        p.allowSelectAllReplace = false
        p.iconDataUrl = "data:image/png;base64,ZmFrZQ=="
        p.syncMode = .editor
        let data = try JSONEncoder().encode(p)
        let back = try JSONDecoder().decode(TargetProfile.self, from: data)
        XCTAssertEqual(back.sendButtonTitleContains, "发送")
        XCTAssertFalse(back.allowSelectAllReplace)
        XCTAssertEqual(back.iconDataUrl, "data:image/png;base64,ZmFrZQ==")
        XCTAssertEqual(back.syncMode, .editor)
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
        // 即使配置文件缺失，也应补齐预置目标默认值。
        let store = TargetConfigStore(fileURL: tempConfigURL(), isBundleInstalled: { _ in false })
        for id in TargetId.presetIds {
            XCTAssertFalse(store.profile(id).displayName.isEmpty)
            XCTAssertFalse(store.profile(id).bundleId.isEmpty)
        }
    }

    func testConfigStoreAutoEnablesInstalledPresetsOnFirstRun() {
        let installed: Set<String> = ["com.openai.codex", "notion.id", "com.tencent.codebuddycn"]
        let store = TargetConfigStore(fileURL: tempConfigURL(), isBundleInstalled: { installed.contains($0) })

        XCTAssertTrue(store.entry(.codex)?.enabled == true)
        XCTAssertFalse(store.entry(.workbuddy)?.enabled == true)
        XCTAssertTrue(store.entry(.notion)?.enabled == true)
        XCTAssertTrue(store.entry(.codebuddycn)?.enabled == true)
        XCTAssertFalse(store.entry(.codebuddy)?.enabled == true)
    }

    func testConfigStoreMigratesEmptyPresetBundleIds() throws {
        var profile = TargetProfile.defaultFor(.codex)
        profile.bundleId = ""
        let entry = TargetConfigEntry(id: .codex, kind: .preset, enabled: true, profile: profile)
        let url = tempConfigURL()
        let data = try JSONEncoder().encode(["targets": [entry]])
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)

        let store = TargetConfigStore(fileURL: url, isBundleInstalled: { _ in false })

        XCTAssertEqual(store.profile(.codex).bundleId, "com.openai.codex")
        XCTAssertFalse(store.entry(.codex)?.enabled == true)
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

    func testCustomTargetAcceptsProvidedIconDataURL() {
        let store = TargetConfigStore(fileURL: tempConfigURL())
        let entry = store.createCustom(displayName: "Icon App", bundleId: nil,
                                       iconDataUrl: "data:image/png;base64,ZmFrZQ==")
        XCTAssertEqual(entry.profile.iconDataUrl, "data:image/png;base64,ZmFrZQ==")
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
