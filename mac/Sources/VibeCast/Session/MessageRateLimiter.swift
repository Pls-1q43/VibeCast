// Per-connection message rate limiting. Keeps noisy or stale LAN clients from
// starving the single-user control session.

struct MessageRateLimiter {
    private var events: [Int64] = []
    private let windowMs: Int64
    private let maxEvents: Int

    init(windowMs: Int64 = 1_000, maxEvents: Int = 40) {
        self.windowMs = windowMs
        self.maxEvents = maxEvents
    }

    mutating func allow(nowMs: Int64) -> Bool {
        let cutoff = nowMs - windowMs
        events.removeAll { $0 < cutoff }
        guard events.count < maxEvents else { return false }
        events.append(nowMs)
        return true
    }
}
