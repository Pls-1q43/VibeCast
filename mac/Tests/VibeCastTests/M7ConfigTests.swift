import XCTest
@testable import VibeCast

final class M7ConfigTests: XCTestCase {

    func testNotionForbidsSelectAllReplace() {
        // Notion 文本块模式必须禁止全选替换，保护整页文档（PRD 14.2）。
        XCTAssertFalse(TargetProfile.defaultFor(.notion).allowSelectAllReplace)
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
        let profile = TargetProfile.defaultFor(.notion) // sendMode = .noneSyncOnly
        let binding = TargetBinding(targetId: .notion, sessionId: "s", pid: 0,
                                    bundleId: "x", element: AXUIElementCreateApplication(0), role: nil)
        if case .skipped = SendAction.perform(profile: profile, binding: binding) {} else {
            XCTFail("noneSyncOnly 应返回 skipped")
        }
    }

    func testConfigStoreFillsMissingTargetsWithDefaults() {
        // 即使配置文件缺失，也应补齐 4 个目标默认值。
        let store = TargetConfigStore()
        for id in TargetId.allCases {
            XCTAssertFalse(store.profile(id).displayName.isEmpty)
        }
    }
}
