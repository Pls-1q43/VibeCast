// 每目标 Revision 单调闸门。PRD 12.1：只接受比已应用版本更高的 revision。

struct RevisionGate {
    private var applied: [TargetId: Int] = [:]

    /// 是否应接受该 revision（严格高于已应用）。
    func shouldApply(_ targetId: TargetId, revision: Int) -> Bool {
        revision > (applied[targetId] ?? 0)
    }

    /// 标记某目标已应用到 revision（仅前进）。
    mutating func markApplied(_ targetId: TargetId, revision: Int) {
        if revision > (applied[targetId] ?? 0) {
            applied[targetId] = revision
        }
    }

    /// 重置某目标（新会话）。
    mutating func reset(_ targetId: TargetId) {
        applied[targetId] = 0
    }

    func current(_ targetId: TargetId) -> Int {
        applied[targetId] ?? 0
    }
}
