import XCTest
@testable import VibeCast

final class TargetProfileTests: XCTestCase {

    func testDefaultProfilesForAllTargets() {
        let expectedBundleIds = [
            TargetId.codex: "com.openai.codex",
            .workbuddy: "com.workbuddy.workbuddy",
            .notion: "notion.id",
            .obsidian: "md.obsidian",
            .codebuddycn: "com.tencent.codebuddycn",
            .codebuddy: "com.tencent.codebuddy"
        ]
        for id in TargetId.presetIds {
            let p = TargetProfile.defaultFor(id)
            XCTAssertFalse(p.displayName.isEmpty)
            XCTAssertEqual(p.bundleId, expectedBundleIds[id])
            XCTAssertEqual(p.maxTextLength, 10000)
        }
    }

    func testPresetDisplayNamesUseProductNames() {
        XCTAssertEqual(TargetProfile.defaultFor(.workbuddy).displayName, "WorkBuddy")
        XCTAssertEqual(TargetProfile.defaultFor(.codebuddycn).displayName, "CodeBuddyCN")
        XCTAssertEqual(TargetProfile.defaultFor(.codebuddy).displayName, "CodeBuddy")
    }

    func testNotionDefaultsUseClipboardForAiInput() {
        // Notion AI 输入框不可靠支持 AXValue，默认使用剪贴板替换并允许 Enter 发送。
        let p = TargetProfile.defaultFor(.notion)
        XCTAssertEqual(p.writeMode, .clipboardReplace)
        XCTAssertEqual(p.syncMode, .mirror)
        XCTAssertTrue(p.allowSelectAllReplace)
        XCTAssertEqual(p.sendMode, .key)
        XCTAssertEqual(p.sendShortcut, .enter)
        XCTAssertTrue(p.clearAfterSend)
        XCTAssertEqual(p.focusMode, .preserveLastFocus)
    }

    func testNotionMirrorClipboardReplaceNormalizesAllowReplace() {
        var p = TargetProfile.defaultFor(.notion)
        p.syncMode = .mirror
        p.writeMode = .clipboardReplace
        p.allowSelectAllReplace = false

        let normalized = p.normalized(for: .notion)

        XCTAssertEqual(normalized.writeMode, .clipboardReplace)
        XCTAssertTrue(normalized.allowSelectAllReplace)
    }

    func testObsidianDefaultsUseEditorMode() {
        let p = TargetProfile.defaultFor(.obsidian)
        XCTAssertEqual(p.displayName, "Obsidian")
        XCTAssertEqual(p.bundleId, "md.obsidian")
        XCTAssertEqual(p.syncMode, .editor)
        XCTAssertEqual(p.writeMode, .clipboardInsert)
        XCTAssertFalse(p.allowSelectAllReplace)
        XCTAssertEqual(p.sendMode, .noneSyncOnly)
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
        p.syncMode = .editor
        p.voiceShortcut = KeyShortcut(modifiers: ["control"], key: "space")
        let data = try JSONEncoder().encode(p)
        let back = try JSONDecoder().decode(TargetProfile.self, from: data)
        XCTAssertEqual(back.bundleId, "com.example.codex")
        XCTAssertEqual(back.focusShortcut, KeyShortcut(modifiers: ["command"], key: "l"))
        XCTAssertEqual(back.syncMode, .editor)
        XCTAssertEqual(back.voiceShortcut, KeyShortcut(modifiers: ["control"], key: "space"))
    }

    func testKeyShortcutEnterConstant() {
        XCTAssertEqual(KeyShortcut.enter.key, "enter")
        XCTAssertTrue(KeyShortcut.enter.modifiers.isEmpty)
    }

    func testVoiceShortcutDefaultsToRightOption() throws {
        XCTAssertEqual(TargetProfile.defaultFor(.codex).voiceShortcut, .rightOption)

        let json = """
        {
          "displayName": "Codex",
          "bundleId": "com.openai.codex",
          "activationMode": "bundle_id",
          "launchIfNotRunning": false,
          "focusMode": "shortcut",
          "focusShortcut": null,
          "focusWaitMs": 300,
          "sendMode": "key",
          "sendShortcut": { "modifiers": [], "key": "enter" },
          "sendButtonTitleContains": null,
          "clearAfterSend": true,
          "allowEmpty": false,
          "keepForeground": false,
          "maxTextLength": 10000,
          "allowSelectAllReplace": true,
          "writeMode": "auto",
          "syncMode": "mirror"
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(TargetProfile.self, from: json)
        XCTAssertEqual(decoded.voiceShortcut, .rightOption)
    }

    func testVoiceRelaySettingsPersistInConfigStore() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("targets.json")
        let store = TargetConfigStore(fileURL: file, isBundleInstalled: { _ in false })
        let settings = VoiceRelaySettings(enabled: true,
                                          provider: .typeless,
                                          triggerMode: .hold,
                                          shortcut: .fn,
                                          managedOriginalAudioDevice: "MacBook Pro Microphone",
                                          managedVirtualAudioDevice: "BlackHole 2ch")

        store.updateVoiceRelaySettings(settings)

        let reloaded = TargetConfigStore(fileURL: file, isBundleInstalled: { _ in false })
        XCTAssertEqual(reloaded.voiceRelaySettings, settings)
    }

    func testNormalizeClampsRiskyValuesAndMigratesLegacyClipboardPaste() {
        var p = TargetProfile.defaultFor(.codex)
        p.displayName = "  "
        p.focusWaitMs = 0
        p.maxTextLength = 100_000
        p.writeMode = .clipboardPaste
        p.syncMode = .editor
        p.allowSelectAllReplace = true
        p.iconDataUrl = "https://example.com/icon.png"
        let normalized = p.normalized()
        XCTAssertEqual(normalized.displayName, "Target")
        XCTAssertEqual(normalized.focusWaitMs, 50)
        XCTAssertEqual(normalized.maxTextLength, 50_000)
        XCTAssertEqual(normalized.writeMode, .clipboardInsert)
        XCTAssertFalse(normalized.allowSelectAllReplace)
        XCTAssertNil(normalized.iconDataUrl)
    }

    func testNormalizeKeepsSafeIconDataURL() {
        var p = TargetProfile.defaultFor(.codex)
        p.iconDataUrl = " data:image/png;base64,ZmFrZQ== "
        XCTAssertEqual(p.normalized().iconDataUrl, "data:image/png;base64,ZmFrZQ==")
    }

    func testCustomTargetIdDefaultsLikeGenericTarget() throws {
        let id = try XCTUnwrap(TargetId(rawValue: "custom_textedit"))
        let p = TargetProfile.defaultFor(id)
        XCTAssertEqual(p.displayName, "Custom_Textedit")
        XCTAssertTrue(p.bundleId.isEmpty)
        XCTAssertEqual(p.focusMode, .shortcut)
        XCTAssertEqual(p.writeMode, .auto)
    }
}
