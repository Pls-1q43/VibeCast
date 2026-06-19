// 发送决策闸门（纯逻辑，可单测）。PRD 11.4 / 16.6。
// 仅负责「是否允许进入第二阶段提交」与「幂等去重」的决策；不含任何 AX/键盘副作用。

struct SendGate {
    private var committed = Set<String>()

    static func key(sessionId: String, targetId: TargetId, revision: Int) -> String {
        "\(sessionId)|\(targetId.rawValue)|\(revision)"
    }

    enum Decision: Equatable {
        case duplicate          // 幂等命中，直接回成功，不再提交
        case staleRevision      // 最终版本尚未写入，拒绝
        case proceed            // 可进入第二阶段（重新校验 + 执行发送）
    }

    /// 决定一次 send 请求如何处理。
    /// - appliedRevision: 该目标当前已应用的最高 revision。
    func decide(sessionId: String, targetId: TargetId, revision: Int, appliedRevision: Int) -> Decision {
        let k = SendGate.key(sessionId: sessionId, targetId: targetId, revision: revision)
        if committed.contains(k) { return .duplicate }
        if revision > appliedRevision { return .staleRevision }
        return .proceed
    }

    /// 标记某次发送已提交（成功执行发送动作后调用）。
    mutating func markCommitted(sessionId: String, targetId: TargetId, revision: Int) {
        committed.insert(SendGate.key(sessionId: sessionId, targetId: targetId, revision: revision))
    }

    func isCommitted(sessionId: String, targetId: TargetId, revision: Int) -> Bool {
        committed.contains(SendGate.key(sessionId: sessionId, targetId: targetId, revision: revision))
    }
}
